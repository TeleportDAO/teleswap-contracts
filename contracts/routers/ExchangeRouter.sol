pragma solidity 0.8.0;

import '../libraries/TeleportDAOLibrary.sol';
import '../libraries/SafeMath.sol';
import '../libraries/TransferHelper.sol';
import '../pools/interfaces/ILiquidityPoolFactory.sol';
import '../pools/interfaces/IInstantPool.sol';
import '../erc20/interfaces/IERC20.sol';
import '../erc20/interfaces/IWAVAX.sol';
import './interfaces/IExchangeRouter.sol';
import "hardhat/console.sol";

contract ExchangeRouter is IExchangeRouter {
    using SafeMath for uint;

    address public immutable override liquidityPoolFactory;
    address public immutable override WAVAX;

    modifier ensure(uint deadline) {
        require(deadline >= block.number, 'ExchangeRouter: EXPIRED');
        _;
    }

    constructor(
        address _liquidityPoolFactory, 
        address _WAVAX
    ) public {
        liquidityPoolFactory = _liquidityPoolFactory;
        WAVAX = _WAVAX;
        // owner = msg.sender;
    }

    receive() external payable {
        assert(msg.sender == WAVAX); // only accept AVAX via fallback from the WAVAX contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the liquidity pool if it doesn't exist yet
        if (ILiquidityPoolFactory(liquidityPoolFactory).getLiquidityPool(tokenA, tokenB) == address(0)) {
            ILiquidityPoolFactory(liquidityPoolFactory).createLiquidityPool(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = TeleportDAOLibrary.getReserves(liquidityPoolFactory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = TeleportDAOLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'ExchangeRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = TeleportDAOLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'ExchangeRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB, 
            amountADesired,
            amountBDesired, 
            amountAMin, 
            amountBMin
        );

        address pair = TeleportDAOLibrary.pairFor(liquidityPoolFactory, tokenA, tokenB);

        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        // ExchangeRouter transfers rest of user's tokens to itself  
        TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), amountADesired - amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amountBDesired - amountB);        
        liquidity = ILiquidityPool(pair).mint(to);
    }
        
    function addLiquidityAVAX(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountAVAX, uint liquidity) {
        (amountToken, amountAVAX) = _addLiquidity(
            token,
            WAVAX,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountAVAXMin
        );
        address pair = TeleportDAOLibrary.pairFor(liquidityPoolFactory, token, WAVAX);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWAVAX(WAVAX).deposit{value: amountAVAX}();
        IWAVAX(WAVAX).transfer(pair, amountAVAX);
        liquidity = ILiquidityPool(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountAVAX) {
            TransferHelper.safeTransferAVAX(msg.sender, msg.value - amountAVAX);
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity( // remove from liquidity pool, not instant pools
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = TeleportDAOLibrary.pairFor(liquidityPoolFactory, tokenA, tokenB);
        // uint totalLiquidity = ILiquidityPool(pair).balanceOf(msg.sender);
        ILiquidityPool(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ILiquidityPool(pair).burn(to);
        (address token0,) = TeleportDAOLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'ExchangeRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'ExchangeRouter: INSUFFICIENT_B_AMOUNT');
        
    }
        
    function removeLiquidityAVAX(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountAVAX) {
        (amountToken, amountAVAX) = removeLiquidity(
            token,
            WAVAX,
            liquidity,
            amountTokenMin,
            amountAVAXMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWAVAX(WAVAX).withdraw(amountAVAX); 
        TransferHelper.safeTransferAVAX(to, amountAVAX);
    }
    
    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = TeleportDAOLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? TeleportDAOLibrary.pairFor(liquidityPoolFactory, output, path[i + 2]) : _to;
            ILiquidityPool(TeleportDAOLibrary.pairFor(liquidityPoolFactory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
        
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts, bool result) {
        amounts = TeleportDAOLibrary.getAmountsOut(liquidityPoolFactory, amountIn, path);
        // require(amounts[amounts.length - 1] >= amountOutMin, 'ExchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        if (amounts[amounts.length - 1] >= amountOutMin) {
            TransferHelper.safeTransferFrom(
                path[0], msg.sender, TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, to);
            result = true;
        } else {
            result = false;
        }
    }
    
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = TeleportDAOLibrary.getAmountsIn(liquidityPoolFactory, amountOut, path);
        require(amounts[0] <= amountInMax, 'ExchangeRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    function swapExactAVAXForTokens (
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WAVAX, 'ExchangeRouter: INVALID_PATH');
        amounts = TeleportDAOLibrary.getAmountsOut(liquidityPoolFactory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'ExchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWAVAX(WAVAX).deposit{value: amounts[0]}(); 
        IWAVAX(WAVAX).transfer(TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    
    function swapTokensForExactAVAX(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WAVAX, 'ExchangeRouter: INVALID_PATH');
        amounts = TeleportDAOLibrary.getAmountsIn(liquidityPoolFactory, amountOut, path);
        require(amounts[0] <= amountInMax, 'ExchangeRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWAVAX(WAVAX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferAVAX(to, amounts[amounts.length - 1]);
    }
    
    function swapExactTokensForAVAX (
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts, bool result) {
        require(path[path.length - 1] == WAVAX, 'ExchangeRouter: INVALID_PATH');
        amounts = TeleportDAOLibrary.getAmountsOut(liquidityPoolFactory, amountIn, path);
        // require(amounts[amounts.length - 1] >= amountOutMin, 'ExchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        if (amounts[amounts.length - 1] >= amountOutMin) {
            TransferHelper.safeTransferFrom(
                path[0], msg.sender, TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amounts[0]
            );
            _swap(amounts, path, address(this));
            IWAVAX(WAVAX).withdraw(amounts[amounts.length - 1]);
            TransferHelper.safeTransferAVAX(to, amounts[amounts.length - 1]);
            result = true;
        } else {
            result = false;
        }

    }
    
    function swapAVAXForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WAVAX, 'ExchangeRouter: INVALID_PATH');
        amounts = TeleportDAOLibrary.getAmountsIn(liquidityPoolFactory, amountOut, path);
        require(amounts[0] <= msg.value, 'ExchangeRouter: EXCESSIVE_INPUT_AMOUNT');
        IWAVAX(WAVAX).deposit{value: amounts[0]}(); 
        assert(IWAVAX(WAVAX).transfer(TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amounts[0])); 
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferAVAX(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = TeleportDAOLibrary.sortTokens(input, output);
            ILiquidityPool pair = ILiquidityPool(TeleportDAOLibrary.pairFor(liquidityPoolFactory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = TeleportDAOLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? TeleportDAOLibrary.pairFor(liquidityPoolFactory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'ExchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    
    function swapExactAVAXForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WAVAX, 'ExchangeRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWAVAX(WAVAX).deposit{value: amountIn}();
        assert(IWAVAX(WAVAX).transfer(TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to); 
        _swapSupportingFeeOnTransferTokens(path, to);
        require( 
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'ExchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    
    function swapExactTokensForAVAXSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WAVAX, 'ExchangeRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, TeleportDAOLibrary.pairFor(liquidityPoolFactory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WAVAX).balanceOf(address(this)); 
        require(amountOut >= amountOutMin, 'ExchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWAVAX(WAVAX).withdraw(amountOut);
        TransferHelper.safeTransferAVAX(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return TeleportDAOLibrary.quote(amountA, reserveA, reserveB);
    }

    // Library functions
    function getReserves (address tokenA, address tokenB) external override returns (uint reserveA, uint reserveB) {
        return TeleportDAOLibrary.getReserves(liquidityPoolFactory, tokenA, tokenB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return TeleportDAOLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return TeleportDAOLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        virtual
        override
        returns (uint[] memory amounts)
    {
        return TeleportDAOLibrary.getAmountsOut(liquidityPoolFactory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        virtual
        override
        returns (uint[] memory amounts)
    {
        return TeleportDAOLibrary.getAmountsIn(liquidityPoolFactory, amountOut, path);
    }
}
