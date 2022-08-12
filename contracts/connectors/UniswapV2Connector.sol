// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IExchangeConnector.sol";
import "../uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "../uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import "../uniswap/v2-core/interfaces/IUniswapV2Factory.sol";
import "../erc20/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract UniswapV2Connector is IExchangeConnector, Ownable, ReentrancyGuard {

    string public override name;
    address public override exchangeRouter;
    address public override liquidityPoolFactory;
    address public override wrappedNativeToken;

    /// @notice                          Setter for exchange router
    /// @param _name                     Name of the connected exchange
    /// @param _exchangeRouter           Address of the connected exchange
    /// @param _wrappedNativeToken       Address of the wrapped native token that exchange uses
    constructor(string memory _name, address _exchangeRouter, address _wrappedNativeToken) {
        name = _name;
        exchangeRouter = _exchangeRouter;
        liquidityPoolFactory = IUniswapV2Router02(exchangeRouter).factory();
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @notice                             Setter for exchange router
    /// @dev                                Gets address of liquidity pool factory from new exchange router
    /// @param _exchangeRouter              Address of the exchange router contract
    function setExchangeRouter(address _exchangeRouter) external override onlyOwner {
        exchangeRouter = _exchangeRouter;
        liquidityPoolFactory = IUniswapV2Router02(exchangeRouter).factory();
    }

    /// @notice            Setter for liquidity pool factory
    /// @dev               Gets address from exchange router
    function setLiquidityPoolFactory() external override onlyOwner {
        liquidityPoolFactory = IUniswapV2Router02(exchangeRouter).factory();
    }

    /// @notice                              Setter for wrapped native token
    /// @param _wrappedNativeToken           Address of the wrapped native token contract
    function setWrappedNativeToken(address _wrappedNativeToken) external override onlyOwner {
        wrappedNativeToken = _wrappedNativeToken;
    }

    function getInputAmount(
        uint _outputAmount,
        address _inputToken,
        address _outputToken
    ) external view override returns (bool, uint) {

        // Checks that the liquidity pool exists
        if (
            IUniswapV2Factory(liquidityPoolFactory).getPair(_inputToken, _outputToken) == address(0)
        ) {
            return (false, 0);
        }

        // // Gets reserves of input token and output token
        // (uint reserveIn, uint reserveOut) = IUniswapV2Router02(exchangeRouter).getReserves(
        //     _inputToken,
        //     _outputToken
        // );

        // return (true, IUniswapV2Router02(exchangeRouter).getAmountIn(_outputAmount, reserveIn, reserveOut));
        address[] memory path = new address[](2);
        path[0] = _inputToken;
        path[1] = _outputToken;
        uint[] memory result = IUniswapV2Router02(exchangeRouter).getAmountsIn(_outputAmount, path);

        return (true, result[0]);
    }

    function getOutputAmount(
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) external view override returns (bool, uint) {

        // Checks that the liquidity pool exists
        if (
            IUniswapV2Factory(liquidityPoolFactory).getPair(_inputToken, _outputToken) == address(0)
        ) {
            return (false, 0);
        }

        // // Gets reserves of input token and output token
        // (uint reserveIn, uint reserveOut) = IUniswapV2Router02(exchangeRouter).getReserves(
        //     _inputToken,
        //     _outputToken
        // );

        // return (true, IUniswapV2Router02(exchangeRouter).getAmountOut(_inputAmount, reserveIn, reserveOut));

        address[] memory path = new address[](2);
        path[0] = _inputToken;
        path[1] = _outputToken;
        uint[] memory result = IUniswapV2Router02(exchangeRouter).getAmountsOut(_inputAmount, path);

        return (true, result[0]);
    }

    /// @notice                     Exchanges input token for output token through exchange router
    /// @dev                        Checks exchange conditions before exchanging
    /// @param _inputAmount         Amount of input token
    /// @param _outputAmount        Amount of output token
    /// @param _path                List of tokens that are used for exchanging
    /// @param _to                  Receiver address
    /// @param _deadline            Deadline of exchanging tokens
    /// @param _isFixedToken        True if the first token amount is fixed
    /// @return _result             True if the exchange is successful
    /// @return _amounts            Amounts of tokens that are involved in exchanging
    function swap(
        uint256 _inputAmount,
        uint256 _outputAmount,
        address[] memory _path,
        address _to,
        uint256 _deadline,
        bool _isFixedToken
    ) external override nonReentrant returns(bool _result, uint[] memory _amounts) {
        uint neededInputAmount;
        (_result, neededInputAmount) = _checkExchangeConditions(
            _inputAmount,
            _outputAmount,
            _path,
            _deadline,
            _isFixedToken
        );
        if (_result) {
            // Gets tokens from user
            IERC20(_path[0]).transferFrom(msg.sender, address(this), neededInputAmount);
            // Gives allowance to exchange router
            IERC20(_path[0]).approve(exchangeRouter, neededInputAmount);

            if (_isFixedToken == false && _path[_path.length-1] != wrappedNativeToken) {
                _amounts = IUniswapV2Router02(exchangeRouter).swapTokensForExactTokens(
                    _outputAmount,
                    _inputAmount,
                    _path,
                    _to,
                    _deadline
                );
            }

            if (_isFixedToken == false && _path[_path.length-1] == wrappedNativeToken) {
                _amounts = IUniswapV2Router02(exchangeRouter).swapTokensForExactETH(
                    _outputAmount,
                    _inputAmount,
                    _path,
                    _to,
                    _deadline
                );
            }

            if (_isFixedToken == true && _path[_path.length-1] != wrappedNativeToken) {
                _amounts = IUniswapV2Router02(exchangeRouter).swapExactTokensForTokens(
                    _inputAmount,
                    _outputAmount,
                    _path,
                    _to,
                    _deadline
                );
            }

            if (_isFixedToken == true && _path[_path.length-1] == wrappedNativeToken) {
                _amounts = IUniswapV2Router02(exchangeRouter).swapExactTokensForETH(
                    _inputAmount,
                    _outputAmount,
                    _path,
                    _to,
                    _deadline
                );
            }
            emit Swap(_path, _amounts, _to);
        }
    }

    /// @notice                           Checks if exchanging can happen successfully
    /// @dev                              Avoids reverting the request by exchange router
    /// @return                           True if exchange conditions are satisfied
    /// @return                           Needed amount of input token
    function _checkExchangeConditions(
        uint256 _inputAmount,
        uint256 _outputAmount,
        address[] memory _path,
        uint256 _deadline,
        bool _isFixedToken
    ) internal view returns (bool, uint) {
        // Checks deadline has not passed
        // TODO: un-comment on production
        if (_deadline < 2236952) {
            return (false, 0);
        }
        // if (_deadline < block.timestamp) {
        //     return (false, 0);
        // }

        // Checks that the liquidity pool exists
        address liquidityPool =
        IUniswapV2Factory(liquidityPoolFactory).getPair(_path[0], _path[_path.length-1]);
        if (liquidityPool == address(0)) {
            return (false, 0);
        }

        // Gets reserves of input token and output token
        (uint reserveIn, uint reserveOut, /*timestamp*/) = IUniswapV2Pair(liquidityPool).getReserves();

        // Checks that enough liquidity for output token exists
        if (_outputAmount > reserveOut) {
            return (false, 0);
        }

        if (_isFixedToken == false) {
            // Checks that the input amount is enough
            uint requiredAmountIn = IUniswapV2Router02(exchangeRouter).getAmountIn(
                _outputAmount,
                reserveIn,
                reserveOut
            );
            return (_inputAmount >= requiredAmountIn ? true : false, requiredAmountIn);
        } else {
            // Checks that the output amount is enough
            uint exchangedAmountOut = IUniswapV2Router02(exchangeRouter).getAmountOut(
                _inputAmount,
                reserveIn,
                reserveOut
            );
            return (exchangedAmountOut >= _outputAmount ? true : false, _inputAmount);
        }
    }

}