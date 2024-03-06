// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/ICcExchangeRouter.sol";

abstract contract CcExchangeRouterStorageV2 is ICcExchangeRouter {
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
    
    mapping(address => bool) public override isTokenSupported; 
    // ^ Mapping to store supported exchange tokens
    mapping(uint => bool) public override isChainSupported; 
    // ^ Mapping to store supported chainIds
    mapping(bytes32 => extendedCcExchangeRequest) public extendedCcExchangeRequests;
     
    address public override across;
    address public wrappedNativeToken;
    address public override burnRouter;

    // New variables (path support)
    address public wmatic;

    mapping(uint => chainIdStruct) chainIdMapping;

    // third party
    mapping(uint => uint) public thirdPartyFee;
    mapping(uint => address) public thirdPartyAddress;
}
