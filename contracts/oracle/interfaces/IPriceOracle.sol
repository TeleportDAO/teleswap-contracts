// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceOracle {

    /// @notice                     Emits when new exchange router is added
    /// @param exchangeRouter       The address of the new exchange router
    /// @param exchangeConnector    The address of the exchange connector
    event ExchangeRouterAdded(address exchangeRouter, address exchangeConnector);

    /// @notice                     Emits when an exchange router is removed
    /// @param exchangeRouter       The address of the new exchange router
    event ExchangeRouterRemoved(address exchangeRouter);

    /// @notice                     Emits when a price proxy is updated
    /// @param _firstToken          Address of the first token
    /// @param _secondToken         Address of the second token
    /// @param _priceProxyAddress   The address of the price proxy
    event SetPriceProxy(address _firstToken, address _secondToken, address _priceProxyAddress);

    // Read-only functions
    
    function ChainlinkPriceProxy(address _firstToken, address _secondToken) external view returns (address);

    function exchangeConnector(address _exchangeRouter) external view returns (address);

    function exchangeRoutersList(uint _index) external view returns (address);

    function getExchangeRoutersListLength() external view returns (uint);

    function acceptableDelay() external view returns (uint);

    function equivalentOutputAmount(
        uint _inputAmount,
        uint _inputDecimals,
        uint _outputDecimals,
        address _inputToken,
        address _outputToken
    ) external view returns (uint);

    function equivalentOutputAmountFromOracle(
        uint _inputAmount,
        uint _inputDecimals,
        uint _outputDecimals,
        address _inputToken,
        address _outputToken
    ) external view returns (uint);

    function equivalentOutputAmountFromExchange(
        address _exchangeRouter,
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) external view returns (uint);
    
    // State-changing functions
    
    function addExchangeRouter(address _exchangeRouter, address _exchangeConnector) external;

    function removeExchangeRouter(uint _exchangeIndex) external;

    function setPriceProxy(address _firstToken, address _secondToken, address _priceProxyAddress) external;
}