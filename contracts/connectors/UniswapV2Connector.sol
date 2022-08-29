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
    ) external override nonReentrant returns (bool _result, uint[] memory _amounts) {
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

    /// @notice                     Returns true if the exchange path is valid
    /// @param _path                List of tokens that are used for exchanging
    function isPathValid(address[] memory _path) public view override returns (bool _result) {
        address liquidityPool;

        // Checks that path length is greater than one
        if (_path.length < 2) {
            return false;
        }

        for (uint i = 0; i < _path.length - 1; i++) {
            liquidityPool =
                IUniswapV2Factory(liquidityPoolFactory).getPair(_path[i], _path[i + 1]);
            if (liquidityPool == address(0)) {
                return false;
            }
        }

        return true;
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
        if (!isPathValid(_path)) {
            return (false, 0);
        }

        // Finds maximum output amount
        uint[] memory outputResult = IUniswapV2Router02(exchangeRouter).getAmountsOut(
                _inputAmount,
                _path
        );

        // Checks that exchanging is possible or not
        if (_outputAmount > outputResult[_path.length - 1]) {
            return (false, 0);
        } else {
            if (_isFixedToken == true) {
                return (true, _inputAmount);
            } else {
                uint[] memory inputResult = IUniswapV2Router02(exchangeRouter).getAmountsIn(
                    _outputAmount, 
                    _path
                );
                return (true, inputResult[0]);
            }
        }
    }

}