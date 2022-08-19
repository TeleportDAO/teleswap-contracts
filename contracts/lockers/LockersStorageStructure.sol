// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../oracle/interfaces/IPriceOracle.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/IERC20.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "hardhat/console.sol";

contract LockersStorageStructure is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    // Structures

    /// @notice                             Structure for registering lockers
    /// @dev
    /// @param lockerLockingScript           Locker redeem script
    /// @param TDTLockedAmount              Bond amount of locker in TDT
    /// @param nativeTokenLockedAmount      Bond amount of locker in native token of the target chain
    /// @param netMinted                    Total minted - total burnt
    /// @param isActive                     Shows if a locker is active (has not requested for removal and
    ///                                     has enough collateral to accept more minting requests)
    struct locker {
        bytes lockerLockingScript;
        uint TDTLockedAmount;
        uint nativeTokenLockedAmount;
        uint netMinted;
        bool isLocker;
        bool isCandidate;
        bool isScriptHash;
        bool isActive;
    }

    // Public variables
    address public lockersLogic;

    uint public lockerPercentageFee;
    address public TeleportDAOToken;
    address public teleBTC;
    address public ccBurnRouter;
    address public exchangeConnector;
    uint public minRequiredTDTLockedAmount;
    uint public minRequiredTNTLockedAmount;
    address public NATIVE_TOKEN = address(1);

    // 10000 means 100%
    uint public collateralRatio;
    uint public liquidationRatio;
    // ^ this is because of price volitility and making minted coins for some collateral secure
    address public priceOracle;

    mapping(address => locker) public lockersMapping; // lockerTargetAddress -> locker structure

    uint public totalNumberOfCandidates;
    uint public totalNumberOfLockers;
    
    mapping(address => bool) public lockerLeavingRequests;
    mapping(address => bool) public lockerLeavingAcceptance;

    mapping(bytes => address) public lockerTargetAddress;

    mapping(address => bool) minters;
    mapping(address => bool) burners;
}
