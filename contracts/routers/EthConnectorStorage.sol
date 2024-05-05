// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./interfaces/IEthConnector.sol";

abstract contract EthConnectorStorage is IEthConnector {
    
    uint constant public ONE_HUNDRED_PERCENT = 10000;
    address constant public ETH_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // ^ Native token representative

    address public across; // Across bridge
    address public targetChainConnectorProxy;
    address public targetChainTeleBTC;
    uint public targetChainId;
    address public wrappedNativeToken;
    uint public uniqueCounter;
}