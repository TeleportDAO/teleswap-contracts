pragma solidity 0.7.6;

import './interfaces/ILiquidityPool.sol';
import './interfaces/ILiquidityPoolFactory.sol';
import './interfaces/ITeleportDAOCallee.sol';
import '../erc20/interfaces/IERC20.sol';
import '../erc20/ERC20.sol';
import '../libraries/UQ112x112.sol';
import '../libraries/Math.sol';
import '../libraries/SafeMath.sol';
import "hardhat/console.sol";

contract LiquidityPool is ILiquidityPool, ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;
    
    uint public override constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public override factory;
    address public override token0;
    address public override token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public override  price0CumulativeLast;
    uint public override  price1CumulativeLast;
    uint public override  kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, 'TeleportDAO: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public override view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TeleportDAO: TRANSFER_FAILED');
    }

    constructor(address _token0, address _token1, string memory _name, string memory _symbol) ERC20(_name, _symbol, 0) public {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    // // called once by the factory at time of deployment
    // function initialize(address _token0, address _token1) public override {
    //     require(msg.sender == factory, 'TeleportDAO: FORBIDDEN'); // sufficient check
    //     token0 = _token0;
    //     token1 = _token1;
    // }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'TeleportDAO: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = ILiquidityPoolFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply().mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) public override lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'TeleportDAO: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) public override lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf(address(this)); // user transferred his liquidity to pair contract 
        // uint amountTDT;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        // amountTDT = liquidity.mul(balanceTDT) / _totalSupply; // using balances ensures pro-rata distribution //ADDED

        require(amount0 > 0 && amount1 > 0, 'TeleportDAO: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) public override lock {
        require(amount0Out > 0 || amount1Out > 0, 'TeleportDAO: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'TeleportDAO: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'TeleportDAO: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) ITeleportDAOCallee(to).TeleportDAOCall(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'TeleportDAO: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3)); // substitute 0.3% fee
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3)); // substitute 0.3% fee
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'TeleportDAO: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    
    // function swapUsingTDT(uint amount0Out, uint amount1Out, address to, bytes calldata data) public override lock {
    //     require(amount0Out > 0 || amount1Out > 0, 'TeleportDAO: INSUFFICIENT_OUTPUT_AMOUNT');
    //     (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
    //     require(amount0Out < _reserve0 && amount1Out < _reserve1, 'TeleportDAO: INSUFFICIENT_LIQUIDITY');

    //     uint balance0;
    //     uint balance1;
    //     { // scope for _token{0,1}, avoids stack too deep errors
    //     address _token0 = token0;
    //     address _token1 = token1;
    //     require(to != _token0 && to != _token1, 'TeleportDAO: INVALID_TO');
    //     if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
    //     if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
    //     if (data.length > 0) ITeleportDAOCallee(to).TeleportDAOCall(msg.sender, amount0Out, amount1Out, data);
    //     balance0 = IERC20(_token0).balanceOf(address(this));
    //     balance1 = IERC20(_token1).balanceOf(address(this));
    //     }
    //     uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    //     uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
    //     require(amount0In > 0 || amount1In > 0, 'TeleportDAO: INSUFFICIENT_INPUT_AMOUNT');
    //     require(balance0.mul(balance1) >= uint(_reserve0).mul(_reserve1), 'TeleportDAO: K');
        
    //     feeAmountUsingTDT(amount0Out, amount1Out, to);
        
    //     _update(balance0, balance1, _reserve0, _reserve1);
    //     emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    // }

    // function feeAmountUsingTDT(uint amount0Out, uint amount1Out, address to) private {
        
    //     address _pair;
    //     uint112 _reserve0;
    //     uint112 _reserve1;
    //     uint feeInTDT;
    //     address _token0;

    //     if(amount1Out == 0){

    //         _pair = ILiquidityPoolFactory(factory).getLiquidityPool(TeleportDAOToken, token0);
            
    //         if(_pair != address(0)) {

    //             _token0 = ILiquidityPool(_pair).token0();

    //             if(TeleportDAOToken == _token0){
    //                 (_reserve0, _reserve1,) = ILiquidityPool(_pair).getReserves();
    //                 feeInTDT = amount0Out.mul(10).mul(_reserve0).div(_reserve1).div(1000);
    //                 IERC20(TeleportDAOToken).transferFrom(to, address(this), feeInTDT);
    //             }

    //             if(TeleportDAOToken != _token0){
    //                 (_reserve0, _reserve1,) = ILiquidityPool(_pair).getReserves();
    //                 feeInTDT = amount0Out.mul(10).mul(_reserve1).div(_reserve0).div(1000);
    //                 IERC20(TeleportDAOToken).transferFrom(to, address(this), feeInTDT);
    //             }
    //         }

    //         if(_pair == address(0)){
    //             require(false, "Cannot pay by TDT"); // TODO: using X-BTC + BTC-TDT to find ratio
    //         }
    //     }

    //     if(amount0Out == 0){

    //         _pair = ILiquidityPoolFactory(factory).getLiquidityPool(TeleportDAOToken, token1);
            
    //         if(_pair != address(0)) {

    //             _token0 = ILiquidityPool(_pair).token0();

    //             if(TeleportDAOToken == _token0){
    //                 (_reserve0, _reserve1,) = ILiquidityPool(_pair).getReserves();
    //                 feeInTDT = amount1Out.mul(10).mul(_reserve0).div(_reserve1).div(1000);
    //                 IERC20(TeleportDAOToken).transferFrom(to, address(this), feeInTDT);
    //             }

    //             if(TeleportDAOToken != _token0){
    //                 (_reserve0, _reserve1,) = ILiquidityPool(_pair).getReserves();
    //                 feeInTDT = amount1Out.mul(10).mul(_reserve1).div(_reserve0).div(1000);
    //                 IERC20(TeleportDAOToken).transferFrom(to, address(this), feeInTDT);
    //             }
    //         }

    //         if(_pair == address(0)){
    //             require(false, "Cannot pay by TDT"); // TODO: using X-BTC + BTC-TDT to find ratio
    //         }
    //     }
    // }

    // force balances to match reserves
    function skim(address to) public override lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() public override lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
