// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import './interfaces/IPriceOracle.sol';
import '../connectors/interfaces/IExchangeConnector.sol';
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "hardhat/console.sol"; // Just for test


contract PriceOracle is IPriceOracle, Ownable {

    using SafeCast for uint;

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "PriceOracle: zero address");
        _;
    }

    // Public variables
    mapping(address => mapping (address => address)) public override ChainlinkPriceProxy; // Given two token addresses returns related Chainlink price proxy
    mapping(address => address) public override exchangeConnector; // Mapping from exchange router to exchnage connector
    address[] public override exchangeRoutersList; // List of available exchange routers
    uint public override acceptableDelay;
    address public constant NATIVE_TOKEN = address(1); // ONE_ADDRESS is used for getting price of blockchain native token 
    address public override oracleNativeToken;

    /// @notice                         This contract is used to get relative price of two assets from Chainlink and available exchanges 
    /// @param _acceptableDelay         Maximum acceptable delay for data given from Chainlink
    constructor(uint _acceptableDelay,address _oracleNativeToken) {
        _setAcceptableDelay(_acceptableDelay);
        _setOracleNativeToken(_oracleNativeToken);
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice                 Getter for the length of exchange router list
    function getExchangeRoutersListLength() public view override returns (uint) {
        return exchangeRoutersList.length;
    }

    /// @notice                         Finds amount of output token that has same value as the input amount of the input token
    /// @dev                            First we try to get the output amount from Chain Link
    ///                                 Only if the price is not available or out-of-date we will 
    ///                                 reach to exchange routers
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
    ) external view nonZeroAddress(_inputToken) nonZeroAddress(_outputToken) override returns (uint) {
        // Gets output amount from oracle
        (bool result, uint outputAmount, uint timestamp) = _equivalentOutputAmountFromOracle(
            _inputAmount,
            _inputDecimals,
            _outputDecimals,
            _inputToken,
            _outputToken
        );

        // Checks timestamp of the oracle result
        if (result == true && _abs(timestamp.toInt256() - block.timestamp.toInt256()) < acceptableDelay) {
            return outputAmount;
        } else {
            uint _totalAmount;
            uint _totalNumber;

            // If Chainlink price is available but out-of-date, we still use it
            if (result == true) {
                _totalAmount = outputAmount;
                _totalNumber = 1;
            }

            // Gets output amounts from exchange routers
            // note: we assume that the decimal of exchange returned result is _outputDecimals. Is that right?
            for (uint i = 0; i < getExchangeRoutersListLength(); i++) {
                (result, outputAmount) = _equivalentOutputAmountFromExchange(
                    exchangeRoutersList[i],
                    _inputAmount,
                    _inputToken,
                    _outputToken
                );

                if (result == true) {
                    _totalNumber = _totalNumber + 1;
                    _totalAmount = _totalAmount + outputAmount;
                }
            }

            require(_totalNumber > 0, "PriceOracle: no price feed is available");

            // Returns average of results from different sources
            return _totalAmount/_totalNumber;
        }
    }

    /// @notice                         Finds amount of output token that has equal value
    ///                                 as the input amount of the input token
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
    ) external view nonZeroAddress(_inputToken) nonZeroAddress(_outputToken) override returns (uint _outputAmount) {
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

    /// @notice                         Finds amount of output token that has same value 
    ///                                 as the input amount of the input token
    /// @dev                            Input amount should have the same decimal as input token
    ///                                 Output amount has the same decimal as output token
    /// @param _exchangeRouter          Address of the exchange router we are reading the price from
    /// @param _inputAmount             Amount of the input token
    /// @param _inputToken              Address of the input token
    /// @param _outputToken             Address of output token
    /// @return                         Amount of the output token
    function equivalentOutputAmountFromExchange(
        address _exchangeRouter,
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) external view nonZeroAddress(_inputToken) nonZeroAddress(_outputToken) override returns (uint) {
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
    function addExchangeConnector(
        address _exchangeRouter, 
        address _exchangeConnector
    ) external nonZeroAddress(_exchangeRouter) nonZeroAddress(_exchangeConnector) override onlyOwner {
        require(exchangeConnector[_exchangeRouter] == address(0), "PriceOracle: exchange router already exists");
        exchangeRoutersList.push(_exchangeRouter);
        exchangeConnector[_exchangeRouter] = _exchangeConnector;
        emit ExchangeConnectorAdded(_exchangeRouter, _exchangeConnector);
    }

    /// @notice                       Removes an exchange connector
    /// @dev                          Only owner can call this
    /// @param _exchangeRouterIndex   The exchange router index in the list
    function removeExchangeConnector(uint _exchangeRouterIndex) external override onlyOwner {
        require(_exchangeRouterIndex < exchangeRoutersList.length, "PriceOracle: Index is out of bound");
        address exchangeRouterAddress = exchangeRoutersList[_exchangeRouterIndex];
        _removeElementFromExchangeRoutersList(_exchangeRouterIndex);
        exchangeConnector[exchangeRouterAddress] = address(0);
        emit ExchangeConnectorRemoved(exchangeRouterAddress);
    }

    /// @notice                     Sets a price proxy for a pair of tokens
    /// @dev                        Only owner can call this
    ///                             This price proxy gives exchange rate of _firstToken/_secondToken
    ///                             Setting price proxy address to zero means that we remove it
    /// @param _firstToken          Address of the first token
    /// @param _secondToken         Address of the second token
    /// @param _priceProxyAddress   The address of the proxy price
    function setPriceProxy(
        address _firstToken, 
        address _secondToken, 
        address _priceProxyAddress
    ) external nonZeroAddress(_firstToken) nonZeroAddress(_secondToken) override onlyOwner {
        ChainlinkPriceProxy[_firstToken][_secondToken] = _priceProxyAddress;
        emit SetPriceProxy(_firstToken, _secondToken, _priceProxyAddress);
    }

    /// @notice                     Sets acceptable delay for oracle responses
    /// @dev                        If oracle data has not been updated for a while, 
    ///                             we will get data from exchange routers
    /// @param _acceptableDelay     Maximum acceptable delay (in seconds)
    function setAcceptableDelay(uint _acceptableDelay) external override onlyOwner {
        _setAcceptableDelay(_acceptableDelay);
    }

    /// @notice                     Sets oracle native token address
    function setOracleNativeToken(address _oracleNativeToken) external override onlyOwner {
       _setOracleNativeToken(_oracleNativeToken);
    }

    /// @notice                     Internal setter for acceptable delay for oracle responses
    /// @dev                        If oracle data has not been updated for a while, 
    ///                             we will get data from exchange routers
    /// @param _acceptableDelay     Maximum acceptable delay (in seconds)
    function _setAcceptableDelay(uint _acceptableDelay) private {
        emit NewAcceptableDelay(acceptableDelay, _acceptableDelay);
        require(
            _acceptableDelay > 0,
            "PriceOracle: zero amount"
        );
        acceptableDelay = _acceptableDelay;
    }

    /// @notice                     Internal setter for oracle native token address
    function _setOracleNativeToken(address _oracleNativeToken) private nonZeroAddress(_oracleNativeToken) {
        emit NewOracleNativeToken(oracleNativeToken, _oracleNativeToken);
        oracleNativeToken = _oracleNativeToken;
    }

    /// @notice                         Finds amount of output token that has same value 
    ///                                 as the input amount of the input token
    /// @param _exchangeRouter          Address of the exchange we are reading the price from
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
    ) private view returns (bool _result, uint _outputAmount) {
        if (_inputToken == NATIVE_TOKEN) {
            // note: different exchanges may use different wrapped native token versions
            address wrappedNativeToken = IExchangeConnector(exchangeConnector[_exchangeRouter]).wrappedNativeToken();

            (_result, _outputAmount) = IExchangeConnector(exchangeConnector[_exchangeRouter]).getOutputAmount(
                _inputAmount,
                wrappedNativeToken,
                _outputToken
            );
        } else if (_outputToken == NATIVE_TOKEN) {
            // note: different exchanges may use different wrapped native token versions
            address wrappedNativeToken = IExchangeConnector(exchangeConnector[_exchangeRouter]).wrappedNativeToken();

            (_result, _outputAmount) = IExchangeConnector(exchangeConnector[_exchangeRouter]).getOutputAmount(
                _inputAmount,
                _inputToken,
                wrappedNativeToken
            );
        } else {
            (_result, _outputAmount) = IExchangeConnector(exchangeConnector[_exchangeRouter]).getOutputAmount(
                _inputAmount,
                _inputToken,
                _outputToken
            );
        }

    }

    /// @notice                         Finds amount of output token that is equal as the input amount of the input token
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
    ) private view returns (bool _result, uint _outputAmount, uint _timestamp) {
        uint decimals;
        int price;

        if (_inputToken == NATIVE_TOKEN) {
            _inputToken = oracleNativeToken;
        }

        if (_outputToken == NATIVE_TOKEN) {
            _outputToken = oracleNativeToken;
        }

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

            require(price != 0, "PriceOracle: zero price");

            // note: to make inside of power parentheses greater than zero, we add them with one
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
            
            require(price != 0, "PriceOracle: zero price");

            // note: to make inside of power parentheses greater than zero, we add them with one
            _outputAmount = (10**(decimals + _outputDecimals + 1))*_inputAmount/(10**(_inputDecimals + 1)*uint(price));
            
            _result = true;
        } else {
            return (false, 0, 0);
        }

    }

    /// @notice             Removes an element of excahngeRouterList
    /// @dev                Deletes and shifts the array
    /// @param _index       Index of the element that will be deleted
    function _removeElementFromExchangeRoutersList(uint _index) private {
        for (uint i = _index; i < exchangeRoutersList.length - 1; i++) {
            exchangeRoutersList[i] = exchangeRoutersList[i+1];
        }
        exchangeRoutersList.pop();
    }

    /// @notice             Returns absolute value
    function _abs(int _value) private pure returns (uint) {
        return _value >= 0 ? uint(_value) : uint(-_value);
    }

}