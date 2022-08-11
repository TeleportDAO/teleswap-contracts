// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../oracle/interfaces/IPriceOracle.sol";
import "./interfaces/ILockers.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/IERC20.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "hardhat/console.sol";

contract LockersStorageStructure is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    // Structures

    /// @notice                             Structure for registering lockers
    /// @dev
    /// @param lockerRedeemScript           Locker redeem script
    /// @param TDTLockedAmount              Bond amount of locker in TDT
    /// @param nativeTokenLockedAmount      Bond amount of locker in native token of the target chain
    /// @param netMinted                    Total minted - total burnt
    /// @param isScriptHash                 Determines if the lockerScriptHash is pub key hash or redeem script hash
    /// @param isActive                     Shows if a locker is active (has not requested for removal and
    ///                                     has enough collateral to accept more minting requests)
    struct locker {
        bytes lockerRedeemScript;
        address lockerScriptHash;
        uint TDTLockedAmount;
        uint nativeTokenLockedAmount;
        uint netMinted;
        bool isLocker;
        // TODO: isScriptHash is used for p2pkh and p2sh, but what about segwit
        bool isScriptHash;
        bool isActive;
    }

    // Events

    event RequestAddLocker(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        bool indexed isScriptHash
    );

    event RequestRemoveLocker(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount,
        uint netMinted        //   = totalMinted  - totalBurnt which needs to be burnt
    );

    event LockerAdded(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        bool isScriptHash
    // uint addingTime
    );

    event LockerRemoved(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount
    // uint removingTime
    );

    address public lockersLogic;

    uint public lockerPercentageFee;
    address public TeleportDAOToken;
    address public teleBTC;
    address public ccBurnRouter;
    address public exchangeConnector;
    // TODO: these are minimum amounts, so change their names
    uint public minRequiredTDTLockedAmount;
    uint public minRequiredTNTLockedAmount;
    address public NATIVE_TOKEN = address(1);

    // 10000 means 100%
    uint public collateralRatio;
    uint public liquidationRatio;
    // ^ this is because of price volitility and making minted coins for some collateral secure
    address public priceOracle;

    uint public totalNumberOfLockers;
    
    mapping(address => locker) public lockersMapping; // lockerTargetAddress -> locker structure

    uint public totalNumberOfCandidates;
    // remember to remove from candidates when becomes locker
    mapping(address => locker) public candidatesMapping;

    // TODO: Combining the 2 mapping into 1 mapping to a struct
    mapping(address => bool) public lockerLeavingRequests;
    mapping(address => bool) public lockerLeavingAcceptance;

    mapping(address => address) public lockerTargetAddress;

    mapping(address => bool) minters;
    mapping(address => bool) burners;
}
