// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./interfaces/IBurnRouter.sol";

abstract contract BurnRouterStorageV2 is IBurnRouter {
    // third party
    mapping(uint => uint) public thirdPartyFee;
    mapping(uint => address) public thirdPartyAddress;

}