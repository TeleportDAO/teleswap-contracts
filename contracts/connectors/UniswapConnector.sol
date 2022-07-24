// SPDX-License-Identifier: <SPDX-License>
pragma solidity ^0.8.0;

import "./interfaces/IExchangeConnector.sol";
import "../routers/interfaces/IExchangeRouter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract UniswapConnector is IExchangeConnector, Ownable, ReentrancyGuard {

    string public override name;
    address public override exchangeRouter;
    address public override wrappedNativeToken;

    /// @notice                          Setter for exchange router
    /// @param _name                     Name of the connected exchange
    /// @param _exchangeRouter           Address of the connected exchange
    /// @param _wrappedNativeToken       Address of the wrapped native token that exchange uses
    constructor(string memory _name, address _exchangeRouter, address _wrappedNativeToken) {
        name = _name;
        exchangeRouter = _exchangeRouter;
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @notice                             Setter for exchange router
    /// @param _exchangeRouter              Address of the exchange router contract
    function setExchangeRouter(address _exchangeRouter) external override onlyOwner {
        exchangeRouter = _exchangeRouter;
    }

    /// @notice                              Setter for wrapped native token
    /// @param _wrappedNativeToken           Address of the wrapped native token contract
    function setWrappedNativeToken(address _wrappedNativeToken) external override onlyOwner {
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @notice                     Exchanges input token for output token through exchange router
    /// @dev                        Checks exchange conditions before exchanging
    /// @param _inputAmount         Amount of input token
    /// @param _outputAmount        Amount of output token
    /// @param _path                List of tokens that are used for exchanging
    /// @param _to                  Receiver address
    /// @param _deadline            Deadline of exchanging tokens
    /// @param _isFixedToken        True if the first token amount is fixed
    /// @return _result            
    /// @return _amounts   
    function swap(
        uint256 _inputAmount,
        uint256 _outputAmount,
        address[] memory _path,
        address _to,
        uint256 _deadline,
        bool _isFixedToken
    ) external override nonReentrant returns(bool _result, uint[] memory _amounts) {
            _result = _checkExchangeConditions(
                _inputAmount,
                _outputAmount,
                _path,
                _to,
                _deadline,
                _isFixedToken
            );
        if (_result) {
            if (_isFixedToken == false && _path[_path.length-1] != wrappedNativeToken) {
                // TODO: use the original uniswap router
                (_amounts,) = IExchangeRouter(exchangeRouter).swapExactTokensForTokens(
                    _inputAmount,
                    _outputAmount,
                    _path,
                    _to,
                    _deadline
                );
            }

            if (_isFixedToken == false && _path[_path.length-1] == wrappedNativeToken) {
                (_amounts,) = IExchangeRouter(exchangeRouter).swapExactTokensForAVAX(
                    _inputAmount,
                    _outputAmount,
                    _path,
                    _to,
                    _deadline
                );    
            }

            if (_isFixedToken == true && _path[_path.length-1] != wrappedNativeToken) {
                _amounts = IExchangeRouter(exchangeRouter).swapTokensForExactTokens(
                    _inputAmount,
                    _outputAmount,
                    _path,
                    _to,
                    _deadline
                );    
            }

            if (_isFixedToken == true && _path[_path.length-1] == wrappedNativeToken) {
                _amounts = IExchangeRouter(exchangeRouter).swapTokensForExactAVAX(
                    _inputAmount,
                    _outputAmount,
                    _path,
                    _to,
                    _deadline
                );   
            }
        }
    }

    /// @notice                           Checks if exchanging can happen successfully
    /// @dev                              Avoids reverting the request by exchange router                 
    /// @return                           True if exchange conditions are satisfied
    function _checkExchangeConditions(
        uint256 _inputAmount,
        uint256 _outputAmount,
        address[] memory _path,
        address _to,
        uint256 _deadline,
        bool _isFixedToken
    ) internal returns (bool) {
        // Checks deadline has not passed
        if (_deadline < block.number) {
            return false;
        }

        // Gets reserves of input token and output token
        (uint reserveIn, uint reserveOut) = IExchangeRouter(exchangeRouter).getReserves(
            _path[0],
            _path[1]
        );

        // Checks that enough liquidity for output token exists
        if (_outputAmount < reserveOut) {
            return false;
        }

        if (_isFixedToken == false) {
            // Checks that the input amount is enough
            uint requiredAmountIn = IExchangeRouter(exchangeRouter).getAmountIn(
                _outputAmount,
                reserveIn,
                reserveOut
            );
            return _inputAmount >= requiredAmountIn ? true : false;
        } else {
            // Checks that the output amount is enough
            uint exchangedAmountOut = IExchangeRouter(exchangeRouter).getAmountOut(
                _outputAmount,
                reserveIn,
                reserveOut
            );
            return exchangedAmountOut >= _outputAmount ? true : false;
        }
    }

}