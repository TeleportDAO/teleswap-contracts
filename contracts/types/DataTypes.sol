// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./ScriptTypesEnum.sol";

library DataTypes {

    /// @notice                             Structure for registering lockers
    /// @dev
    /// @param lockerLockingScript          Locker redeem script
    /// @param lockerRescueType             Locker script type in case of getting BTCs back
    /// @param lockerRescueScript           Locker script in case of getting BTCs back
    /// @param TDTLockedAmount              Bond amount of locker in TDT
    /// @param nativeTokenLockedAmount      Bond amount of locker in native token of the target chain
    /// @param netMinted                    Total minted - total burnt
    /// @param slashingTeleBTCAmount        Total amount of teleBTC a locker must be slashed
    /// @param reservedNativeTokenForSlash  Total native token reserved to support slashing teleBTC
    /// @param isLocker                     Indicates that is already a locker or not
    /// @param isCandidate                  Indicates that is a candidate or not
    /// @param isScriptHash
    /// @param isActive                     Shows if a locker is active (has not requested for removal and
    ///                                     has enough collateral to accept more minting requests)
    struct locker {
        bytes lockerLockingScript;
        ScriptTypes lockerRescueType;
        bytes lockerRescueScript;
        uint TDTLockedAmount;
        uint nativeTokenLockedAmount;
        uint netMinted;
        uint slashingTeleBTCAmount;
        uint reservedNativeTokenForSlash;
        bool isLocker;
        bool isCandidate;
        bool isScriptHash;
        bool isActive;
    }

    struct lockersLibConstants {
        uint OneHundredPercent;
        uint HealthFactor;
        uint UpperHealthFactor;
        uint MaxLockerFee;
        uint NativeTokenDecimal;
        address NativeToken;
    }

    struct lockersLibParam {
        address teleportDAOToken;
        address teleBTC;
        address ccBurnRouter;
        address exchangeConnector;
        address priceOracle;

        uint minRequiredTDTLockedAmount;
        uint minRequiredTNTLockedAmount;
        uint lockerPercentageFee;
        uint collateralRatio;
        uint liquidationRatio;
        uint priceWithDiscountRatio;
        uint minLeavingIntervalTime;
    }
}