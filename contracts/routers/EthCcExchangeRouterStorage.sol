// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/IEthCcExchangeRouterStorage.sol";

contract EthCcExchangeRouterStorage is IEthCcExchangeRouterStorage {

    // Constants
    uint constant MAX_PROTOCOL_FEE = 10000;

    // Public variables
    uint public override startingBlockNumber;
    uint public override chainId;
    uint public override protocolPercentageFee; // A number between 0 to 10000
    address public override relay;
    address public override instantRouter;
    address public override lockers;
    address public override teleBTC;
    address public override treasury;
    mapping(uint => address) public override exchangeConnector; // mapping from app id to exchange connector address 
    mapping(address => bool) public override isExchangeTokenSupported; // mapping to store supported exchange tokens

    // Private variables
    mapping(bytes32 => ethCcExchangeRequest) internal ethCcExchangeRequests;

    address public override across;

    int64 public override acrossRelayerFee;

    address public override burnRouter;
}
