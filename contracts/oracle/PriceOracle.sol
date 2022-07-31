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

    /// @notice                 Getter for the length of the exchange router list
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
    ) external override returns (uint) {
        // Gets output amount from oracle
        (uint outputAmount, uint timestamp, bool result) = _equivalentOutputAmountFromOracle(
            _inputAmount, 
            _inputDecimals,
            _outputDecimals,
            _inputToken, 
            _outputToken
        );

        // Checks timestamp of the oracle result
        console.log("timestamp", timestamp, "block.timestamp", block.timestamp);
        if (_abs(int(timestamp) - int(block.timestamp)) < acceptableDelay) {
            console.log("outputAmount", outputAmount);
            return outputAmount;
        } else {
            bool _result;
            uint _outputAmount;
            uint _totalAmount;
            uint _totalNumber;
            _totalAmount = outputAmount;
            _totalNumber = 1;
            for (uint i = 0; i < getExchangeRoutersListLength(); i++) {
                (_outputAmount, _result) = _equivalentOutputAmountFromExchange(
                    exchangeRoutersList[i],
                    _inputAmount, 
                    _inputToken, 
                    _outputToken
                );
                if (result == true) {
                    _totalNumber = _totalNumber + 1;
                    _totalAmount = _totalAmount + _outputAmount;
                } 
            }
            console.log("_totalAmount", _totalAmount, "_totalNumber", _totalNumber);
            return _totalAmount/_totalNumber;
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
        (_outputAmount, , result) = _equivalentOutputAmountFromOracle(
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
    ) external override returns (uint) {
        (uint outputAmount, bool result) = _equivalentOutputAmountFromExchange(
            _exchangeRouter, 
            _inputAmount, 
            _inputToken, 
            _outputToken
        );
        require(result == true, "PriceOracle: Pair does not exist on exchange");
        return outputAmount;
    }

    /// @notice                 Adds an exchange router to the list of exchanges
    /// @dev                    Only owner can call this
    /// @param _exchangeRouter The new exchange router contract address
    function addExchangeRouter(address _exchangeRouter, address _exchangeConnector) external override onlyOwner {
        exchangeRoutersList.push(_exchangeRouter);
        exchangeConnector[_exchangeRouter] = _exchangeConnector;
        emit ExchangeRouterAdded(_exchangeRouter);
        emit SetExchangeConnector(_exchangeRouter, _exchangeConnector);
    }

    /// @notice                 Removes an exchange router from the list of exchanges
    /// @dev                    Only owner can call this
    /// @param _exchangeIndex   The exchange router contract address
    function removeExchangeRouter(uint _exchangeIndex) external override onlyOwner {
        address exchangeRouterAddress = exchangeRoutersList[_exchangeIndex];
        _removeElementFromExchangeRoutersList(_exchangeIndex);
        exchangeConnector[exchangeRouterAddress] = address(0);
        emit ExchangeRouterRemoved(exchangeRouterAddress);
    }

    /// @notice                     Sets a price proxy of ChainLink
    /// @dev                        Only owner can call this
    /// @param _firstToken          Address of the first token
    /// @param _secondToken         Address of the second token
    /// @param _priceProxyAddress   The address of the proxy price
    function setPriceProxy(address _firstToken, address _secondToken, address _priceProxyAddress) external override onlyOwner {
        ChainlinkPriceProxy[_firstToken][_secondToken] = _priceProxyAddress;
        emit SetPriceProxy(_firstToken, _secondToken, _priceProxyAddress);
    }

    /// @notice                         Sets a price proxy of ChainLink
    /// @dev                            Only owner can call this
    /// @param _exchangeRouter          Address of the first token
    /// @param _exchangeConnector       Address of the second token
    function setExchangeConnector(address _exchangeRouter, address _exchangeConnector) external override onlyOwner {
        exchangeConnector[_exchangeRouter] = _exchangeConnector;
        emit SetExchangeConnector(_exchangeRouter, _exchangeConnector);
    }

    /// @notice                         Finds amount of output token that is equal to the input amount of the input token
    /// @dev                            The exchange should be Uniswap like. And have getReserves() and getAmountOut()
    /// @param _exchangeRouter         Address of the exchange we are reading the price from
    /// @param _inputAmount             Amount of the input token
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return _outputAmount                   Amount of the output token
    /// @return _result                   Amount of the output token
    function _equivalentOutputAmountFromExchange(
        address _exchangeRouter,
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) internal returns (uint _outputAmount, bool _result) {
        
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
    /// @return _outputAmount           Amount of the output token
    /// @return _timestamp              Timestamp of the result
    function _equivalentOutputAmountFromOracle(
        uint _inputAmount,
        uint _inputDecimals,
        uint _outputDecimals,
        address _inputToken,
        address _outputToken
    ) internal view returns (uint _outputAmount, uint _timestamp, bool result) {
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

            _outputAmount = uint(price)*_inputAmount*(10**(_outputDecimals + 1))/(10**(decimals + _inputDecimals + 1));
            result = true;
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
            
            _outputAmount = (10**(decimals + 1))*_inputAmount*(10**(_outputDecimals + 1))/10/(10**(_inputDecimals + 1))/uint(price);
            result = true;
        } else {
            return (0, 0, false);
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