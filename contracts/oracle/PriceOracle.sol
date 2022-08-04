// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './interfaces/IPriceOracle.sol';
import '../connectors/interfaces/IExchangeConnector.sol';
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "hardhat/console.sol"; // Just for test

contract PriceOracle is IPriceOracle, Ownable {

    mapping(address => mapping (address => address)) public override ChainlinkPriceProxy;
    mapping(address => address) public override exchangeConnector;
    address[] public override exchangeRoutersList;
    uint public override acceptableDelay;

    constructor(uint _acceptableDelay) public {
        acceptableDelay = _acceptableDelay;
    }

    /// @notice                 Getter for the length of exchange router list
    function getExchangeRoutersListLength() public view override returns (uint) {
        return exchangeRoutersList.length;
    }

    /// @notice                         Finds amount of output token that has equal value to the input amount of the input token
    /// @param _inputAmount             Amount of the input token
    /// @param _inputDecimals           Number of input token decimals
    /// @param _outputDecimals          Number of output token decimals
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return                         Amount of the output token
    function equivalentOutputAmount(
        uint _inputAmount,
        uint _inputDecimals,
        uint _outputDecimals,
        address _inputToken,
        address _outputToken
    ) external view override returns (uint) {
        // Gets output amount from oracle
        (bool result, uint outputAmount, uint timestamp) = _equivalentOutputAmountFromOracle(
            _inputAmount,
            _inputDecimals,
            _outputDecimals,
            _inputToken,
            _outputToken
        );

        // Checks timestamp of the oracle result
        if (result == true && _abs(int(timestamp) - int(block.timestamp)) < acceptableDelay) {
            return outputAmount;
        } else {
            bool _result;
            uint _outputAmount;
            uint _totalAmount;
            uint _totalNumber;

            if (result == true) {
                _totalAmount = outputAmount;
                _totalNumber = 1;
            }

            // Gets output amounts from exchange routers
            for (uint i = 0; i < getExchangeRoutersListLength(); i++) {
                (_result, _outputAmount) = _equivalentOutputAmountFromExchange(
                    exchangeRoutersList[i],
                    _inputAmount,
                    _inputToken,
                    _outputToken
                );

                if (_result == true) {
                    _totalNumber = _totalNumber + 1;
                    _totalAmount = _totalAmount + _outputAmount;
                }
            }

            // Returns average of results from different sources
            return _totalNumber > 0 ? _totalAmount/_totalNumber : 0;

        }
    }

    /// @notice                         Finds amount of output token that is equal to the input amount of the input token
    /// @dev                            The oracle is ChainLink
    /// @param _inputAmount             Amount of the input token
    /// @param _inputDecimals           Number of input token decimals
    /// @param _outputDecimals          Number of output token decimals
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return _outputAmount           Amount of the output token
    function equivalentOutputAmountFromOracle(
        uint _inputAmount,
        uint _inputDecimals,
        uint _outputDecimals,
        address _inputToken,
        address _outputToken
    ) external view override returns (uint _outputAmount) {
        bool result;
        (result, _outputAmount, /*timestamp*/) = _equivalentOutputAmountFromOracle(
            _inputAmount,
            _inputDecimals,
            _outputDecimals,
            _inputToken,
            _outputToken
        );
        require(result == true, "PriceOracle: Price proxy does not exist");
    }

    /// @notice                         Finds amount of output token that is equal to the input amount of the input token
    /// @param _exchangeRouter          Address of the exchange we are reading the price from
    /// @param _inputAmount             Amount of the input token
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return                         Amount of the output token
    function equivalentOutputAmountFromExchange(
        address _exchangeRouter,
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) external view override returns (uint) {
        (bool result, uint outputAmount) = _equivalentOutputAmountFromExchange(
            _exchangeRouter,
            _inputAmount,
            _inputToken,
            _outputToken
        );
        require(result == true, "PriceOracle: Pair does not exist on exchange");
        return outputAmount;
    }

    /// @notice                    Adds an exchange connector
    /// @dev                       Only owner can call this
    /// @param _exchangeRouter     Exchange router contract address
    /// @param _exchangeConnector  New exchange connector contract address
    function addExchangeConnector(address _exchangeRouter, address _exchangeConnector) external override onlyOwner {
        exchangeRoutersList.push(_exchangeRouter);
        exchangeConnector[_exchangeRouter] = _exchangeConnector;
        emit ExchangeConnectorAdded(_exchangeRouter, _exchangeConnector);
    }

    /// @notice                       Removes an exchange connector
    /// @dev                          Only owner can call this
    /// @param _exchangeRouterIndex   The exchange router index in the list
    function removeExchangeConnector(uint _exchangeRouterIndex) external override onlyOwner {
        address exchangeRouterAddress = exchangeRoutersList[_exchangeRouterIndex];
        _removeElementFromExchangeRoutersList(_exchangeRouterIndex);
        exchangeConnector[exchangeRouterAddress] = address(0);
        emit ExchangeConnectorRemoved(exchangeRouterAddress);
    }

    /// @notice                     Sets a price proxy for a pair of tokens
    /// @dev                        Only owner can call this
    /// @param _firstToken          Address of the first token
    /// @param _secondToken         Address of the second token
    /// @param _priceProxyAddress   The address of the proxy price
    function setPriceProxy(address _firstToken, address _secondToken, address _priceProxyAddress) external override onlyOwner {
        ChainlinkPriceProxy[_firstToken][_secondToken] = _priceProxyAddress;
        emit SetPriceProxy(_firstToken, _secondToken, _priceProxyAddress);
    }

    /// @notice                     Sets acceptable delay for oracle responses
    /// @dev                        If oracle data has not been updated for a while, we will get data from exchange routers
    /// @param _acceptableDelay     Maximum acceptable delay (in seconds)
    function setAcceptableDelay(uint _acceptableDelay) external override onlyOwner {
        acceptableDelay = _acceptableDelay;
    }

    /// @notice                         Finds amount of output token that is equal to the input amount of the input token
    /// @dev                            The exchange should be Uniswap like. And have getReserves() and getAmountOut()
    /// @param _exchangeRouter         Address of the exchange we are reading the price from
    /// @param _inputAmount             Amount of the input token
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return _result                 True if getting amount was successful
    /// @return _outputAmount           Amount of the output token
    function _equivalentOutputAmountFromExchange(
        address _exchangeRouter,
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) internal view returns (bool _result, uint _outputAmount) {

        (_result, _outputAmount) = IExchangeConnector(exchangeConnector[_exchangeRouter]).getOutputAmount(
            _inputAmount,
            _inputToken,
            _outputToken
        );
    }

    /// @notice                         Finds amount of output token that is equal to the input amount of the input token
    /// @dev                            The oracle is ChainLink
    /// @param _inputAmount             Amount of the input token
    /// @param _inputDecimals           Number of input token decimals
    /// @param _outputDecimals          Number of output token decimals
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return _result                 True if getting amount was successful
    /// @return _outputAmount           Amount of the output token
    /// @return _timestamp              Timestamp of the result
    function _equivalentOutputAmountFromOracle(
        uint _inputAmount,
        uint _inputDecimals,
        uint _outputDecimals,
        address _inputToken,
        address _outputToken
    ) internal view returns (bool _result, uint _outputAmount, uint _timestamp) {
        uint decimals;
        int price;

        if (ChainlinkPriceProxy[_inputToken][_outputToken] != address(0)) {
            // Gets price of _inputToken/_outputToken
            (
            /*uint80 roundID*/,
            price,
            /*uint startedAt*/,
            _timestamp,
            /*uint80 answeredInRound*/
            ) = AggregatorV3Interface(ChainlinkPriceProxy[_inputToken][_outputToken]).latestRoundData();

            // Gets number of decimals
            decimals = AggregatorV3Interface(ChainlinkPriceProxy[_inputToken][_outputToken]).decimals();

            // TODO: check the logic again
            _outputAmount = uint(price)*_inputAmount*(10**(_outputDecimals + 1))/(10**(decimals + _inputDecimals + 1));
            _result = true;
        } else if (ChainlinkPriceProxy[_outputToken][_inputToken] != address(0)) {
            // Gets price of _outputToken/_inputToken
            (
            /*uint80 roundID*/,
            price,
            /*uint startedAt*/,
            _timestamp,
            /*uint80 answeredInRound*/
            ) = AggregatorV3Interface(ChainlinkPriceProxy[_outputToken][_inputToken]).latestRoundData();

            // Gets number of decimals
            decimals = AggregatorV3Interface(ChainlinkPriceProxy[_outputToken][_inputToken]).decimals();

            // TODO: check the logic again
            _outputAmount = (10**(decimals + 1))*_inputAmount*(10**(_outputDecimals + 1))/10/(10**(_inputDecimals + 1))/uint(price);
            _result = true;
        } else {
            return (false, 0, 0);
        }

    }

    /// @notice             Removes an element of excahngeRouterList
    /// @dev                Deletes and shifts the array
    /// @param _index       Index of the element that will be deleted
    function _removeElementFromExchangeRoutersList(uint _index) internal {
        require(_index < exchangeRoutersList.length, "PriceOracle: Index is out of bound");
        for (uint i = _index; i < exchangeRoutersList.length - 1; i++) {
            exchangeRoutersList[i] = exchangeRoutersList[i+1];
        }
        exchangeRoutersList.pop();
    }

    function _abs(int x) internal pure returns (uint) {
        return x >= 0 ? uint(x) : uint(-x);
    }

}