// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/ICcExchangeRouter.sol";

abstract contract CcExchangeRouterStorage is ICcExchangeRouter {

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
    mapping(uint => address) public override exchangeConnector; 
    // ^ Mapping from app id to exchange connector address 

    // Private variables
    mapping(bytes32 => ccExchangeRequest) internal ccExchangeRequests;

    // New variables (filler)

    address constant NATIVE_TOKEN = address(1);

    // note: should be set after deplyment
    uint public fillerWithdrawInterval;

    mapping(bytes32 => mapping(address => FillerData)) public fillersData;
    // ^ [txId][filler] to FillerData
    mapping(bytes32 => mapping(address => PrefixFillSum)) public prefixFillSums;
    // ^ [txId][token] to PrefixFillSum
    mapping(bytes32 => FillData) public fillsData;
    mapping(bytes32 => uint) public teleBtcAmount;
    // ^ txId to remained teleBTC amount

    // New variables (Ethereum support)
    
    mapping(address => bool) public override isTokenSupported; 
    // ^ Mapping to store supported exchange tokens
    mapping(uint => bool) public override isChainSupported; 
    // ^ Mapping to store supported chainIds
    mapping(bytes32 => extendedCcExchangeRequest) public extendedCcExchangeRequests;
     
    address public override across;
    address public wrappedNativeToken;
    int64 public override acrossRelayerFee;
    address public override burnRouter;
}
