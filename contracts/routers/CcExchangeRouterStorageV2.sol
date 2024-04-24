// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./interfaces/ICcExchangeRouter.sol";

abstract contract CcExchangeRouterStorageV2 is ICcExchangeRouter {
    // Constants
    uint constant MAX_BRIDGE_FEE = 10**18;

    // New variables (filler)

    address constant NATIVE_TOKEN = address(1);

    // note: should be set after deplyment
    uint public fillerWithdrawInterval;

    mapping(bytes32 => mapping(address => FillerData)) public fillersData;
    // ^ [txId][filler] to FillerData
    mapping(bytes32 => mapping(address => PrefixFillSum)) public prefixFillSums;
    // ^ [txId][token] to PrefixFillSum
    mapping(bytes32 => FillData) public fillsData;

    // New variables (Ethereum support)
    
    mapping (uint => mapping (address => bool)) public override isTokenSupported; 
    // ^ Mapping to store supported exchange tokens
    mapping(uint => bool) public override isChainSupported; 
    // ^ Mapping to store supported chainIds
    mapping(bytes32 => extendedCcExchangeRequest) public extendedCcExchangeRequests;
     
    address public override across;
    address public wrappedNativeToken;
    address public override burnRouter;

    mapping(uint => chainIdStruct) public chainIdMapping;

    // third party 
    // other applications can use our smart contracts as a third party, 
    // an id will be assigned to them
    // and they will receive a third party fee for each transaction that is sent by them
    // this fee will be send to their third party address

    mapping(uint => uint) public thirdPartyFee;
    mapping(uint => address) public thirdPartyAddress;
}
