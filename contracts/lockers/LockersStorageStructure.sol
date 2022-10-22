// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/ILockersStorage.sol";

contract LockersStorageStructure is ILockersStorage {

    // Constants
    uint public constant ONE_HUNDRED_PERCENT = 10000;
    uint public constant HEALTH_FACTOR = 10000;
    uint public constant UPPER_HEALTH_FACTOR = 12000;
    uint public constant MAX_LOCKER_FEE = 10000;
    uint public constant NATIVE_TOKEN_DECIMAL = 18;
    address public constant NATIVE_TOKEN = address(1);

    // Public variables
    address public override TeleportDAOToken;
    address public override teleBTC;
    address public override ccBurnRouter;
    address public override exchangeConnector;
    address public override priceOracle;

    uint public override minRequiredTDTLockedAmount;
    uint public override minRequiredTNTLockedAmount;
    uint public override lockerPercentageFee;
    uint public override collateralRatio;
    uint public override liquidationRatio;
    uint public override priceWithDiscountRatio;
    uint public override totalNumberOfCandidates;
    uint public override totalNumberOfLockers;

    mapping(address => DataTypes.locker) public lockersMapping; // locker's target address -> locker structure
    mapping(address => bool) public lockerLeavingRequests;
    mapping(address => bool) public lockerLeavingAcceptance;
    mapping(bytes => address) public lockerTargetAddress; // locker's locking script -> locker's target address
    mapping(address => bool) minters;
    mapping(address => bool) burners;

    DataTypes.lockersLibConstants public libConstants;
    DataTypes.lockersLibParam public libParams;

}
