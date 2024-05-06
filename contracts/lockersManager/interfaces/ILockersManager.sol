// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";

interface ILockersManager {
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
    /// @param isScriptHash                 Shows if it's script hash
    ///                                     has enough collateral to accept more minting requests)
    struct locker {
        bytes lockerLockingScript;
        ScriptTypes lockerRescueType;
        bytes lockerRescueScript;
        uint256 TDTLockedAmount;
        uint256 nativeTokenLockedAmount;
        uint256 netMinted;
        uint256 slashingTeleBTCAmount;
        uint256 reservedNativeTokenForSlash;
        bool isLocker;
        bool isCandidate;
        bool isScriptHash;
    }

    struct lockersLibConstants {
        uint256 OneHundredPercent;
        uint256 HealthFactor;
        uint256 UpperHealthFactor;
        uint256 MaxLockerFee;
        uint256 NativeTokenDecimal;
        address NativeToken;
    }

    struct lockersLibParam {
        address teleportDAOToken;
        address teleBTC;
        address ccBurnRouter;
        address exchangeConnector;
        address priceOracle;
        uint256 minRequiredTDTLockedAmount;
        uint256 minRequiredTNTLockedAmount;
        uint256 lockerPercentageFee;
        uint256 collateralRatio;
        uint256 liquidationRatio;
        uint256 priceWithDiscountRatio;
        uint256 inactivationDelay;
    }

    // Events

    event RequestAddLocker(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint256 TDTLockedAmount,
        uint256 nativeTokenLockedAmount
    );

    event RevokeAddLockerRequest(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint256 TDTLockedAmount,
        uint256 nativeTokenLockedAmount
    );

    event RequestInactivateLocker(
        address indexed lockerTargetAddress,
        uint256 indexed inactivationTimestamp,
        bytes lockerLockingScript,
        uint256 TDTLockedAmount,
        uint256 nativeTokenLockedAmount,
        uint256 netMinted
    );

    event ActivateLocker(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint256 TDTLockedAmount,
        uint256 nativeTokenLockedAmount,
        uint256 netMinted
    );

    event LockerAdded(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint256 TDTLockedAmount,
        uint256 nativeTokenLockedAmount,
        uint256 addingTime
    );

    event LockerRemoved(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint256 TDTUnlockedAmount,
        uint256 nativeTokenUnlockedAmount
    );

    event LockerSlashed(
        address indexed lockerTargetAddress,
        uint256 rewardAmount,
        address indexed rewardRecipient,
        uint256 amount,
        address indexed recipient,
        uint256 slashedCollateralAmount,
        uint256 slashTime,
        bool isForCCBurn
    );

    event LockerLiquidated(
        address indexed lockerTargetAddress,
        address indexed liquidatorAddress,
        uint256 collateralAmount,
        uint256 teleBTCAmount,
        uint256 liquidateTime
    );

    event LockerSlashedCollateralSold(
        address indexed lockerTargetAddress,
        address indexed buyerAddress,
        uint256 slashingAmount,
        uint256 teleBTCAmount,
        uint256 slashingTime
    );

    event CollateralAdded(
        address indexed lockerTargetAddress,
        uint256 addedCollateral,
        uint256 totalCollateral,
        uint256 addingTime
    );

    event CollateralRemoved(
        address indexed lockerTargetAddress,
        uint256 removedCollateral,
        uint256 totalCollateral,
        uint256 removingTime
    );

    event MintByLocker(
        address indexed lockerTargetAddress,
        address indexed receiver,
        uint256 mintedAmount,
        uint256 lockerFee,
        uint256 mintingTime
    );

    event BurnByLocker(
        address indexed lockerTargetAddress,
        uint256 burntAmount,
        uint256 lockerFee,
        uint256 burningTime
    );

    event MinterAdded(address indexed account);

    event MinterRemoved(address indexed account);

    event BurnerAdded(address indexed account);

    event BurnerRemoved(address indexed account);

    event NewLockerPercentageFee(
        uint256 oldLockerPercentageFee,
        uint256 newLockerPercentageFee
    );

    event NewPriceWithDiscountRatio(
        uint256 oldPriceWithDiscountRatio,
        uint256 newPriceWithDiscountRatio
    );

    event NewMinRequiredTDTLockedAmount(
        uint256 oldMinRequiredTDTLockedAmount,
        uint256 newMinRequiredTDTLockedAmount
    );

    event NewMinRequiredTNTLockedAmount(
        uint256 oldMinRequiredTNTLockedAmount,
        uint256 newMinRequiredTNTLockedAmount
    );

    event NewPriceOracle(address oldPriceOracle, address newPriceOracle);

    event NewCCBurnRouter(address oldCCBurnRouter, address newCCBurnRouter);

    event NewTST(address oldTST, address newTST);

    event NewTeleBTC(address oldTeleBTC, address newTeleBTC);

    event NewCollateralRatio(
        uint256 oldCollateralRatio,
        uint256 newCollateralRatio
    );

    event NewLiquidationRatio(
        uint256 oldLiquidationRatio,
        uint256 newLiquidationRatio
    );

    // Read-only functions

    function TeleportDAOToken() external view returns (address);

    function teleBTC() external view returns (address);

    function ccBurnRouter() external view returns (address);

    function exchangeConnector() external view returns (address);

    function priceOracle() external view returns (address);

    function minRequiredTDTLockedAmount() external view returns (uint256);

    function minRequiredTNTLockedAmount() external view returns (uint256);

    function lockerPercentageFee() external view returns (uint256);

    function collateralRatio() external view returns (uint256);

    function liquidationRatio() external view returns (uint256);

    function priceWithDiscountRatio() external view returns (uint256);

    function totalNumberOfCandidates() external view returns (uint256);

    function totalNumberOfLockers() external view returns (uint256);

    function getLockerTargetAddress(
        bytes calldata _lockerLockingScript
    ) external view returns (address);

    function isLocker(
        bytes calldata _lockerLockingScript
    ) external view returns (bool);

    function getNumberOfLockers() external view returns (uint256);

    function getLockerLockingScript(
        address _lockerTargetAddress
    ) external view returns (bytes memory);

    function isLockerActive(
        address _lockerTargetAddress
    ) external view returns (bool);

    function priceOfOneUnitOfCollateralInBTC() external view returns (uint256);

    function getLockerCapacity(
        address _lockerTargetAddress
    ) external view returns (uint256);

    function minters(address) external view returns (bool);

    function burners(address) external view returns (bool);

    // State-changing functions

    function pauseLocker() external;

    function unPauseLocker() external;

    function addMinter(address _account) external;

    function removeMinter(address _account) external;

    function addBurner(address _account) external;

    function removeBurner(address _account) external;

    function mint(
        bytes calldata _lockerLockingScript,
        address _receiver,
        uint256 _amount
    ) external returns (uint256);

    function burn(
        bytes calldata _lockerLockingScript,
        uint256 _amount
    ) external returns (uint256);

    function setTST(address _TST) external;

    function setLockerPercentageFee(uint256 _lockerPercentageFee) external;

    function setPriceWithDiscountRatio(
        uint256 _priceWithDiscountRatio
    ) external;

    function setMinRequiredTDTLockedAmount(
        uint256 _minRequiredTDTLockedAmount
    ) external;

    function setMinRequiredTNTLockedAmount(
        uint256 _minRequiredTNTLockedAmount
    ) external;

    function setPriceOracle(address _priceOracle) external;

    function setCCBurnRouter(address _ccBurnRouter) external;

    function setTeleBTC(address _teleBTC) external;

    function setCollateralRatio(uint256 _collateralRatio) external;

    function setLiquidationRatio(uint256 _liquidationRatio) external;

    function liquidateLocker(
        address _lockerTargetAddress,
        uint256 _btcAmount
    ) external returns (bool);

    function addCollateral(
        address _lockerTargetAddress,
        uint256 _addingNativeTokenAmount
    ) external payable returns (bool);

    function removeCollateral(
        uint256 _removingNativeTokenAmount
    ) external payable returns (bool);

    function requestToBecomeLocker(
        bytes calldata _lockerLockingScript,
        uint256 _lockedTSTAmount,
        uint256 _lockedNativeTokenAmount,
        ScriptTypes _lockerRescueType,
        bytes calldata _lockerRescueScript
    ) external payable returns (bool);

    function revokeRequest() external returns (bool);

    function addLocker(address _lockerTargetAddress) external returns (bool);

    function requestInactivation() external returns (bool);

    function requestActivation() external returns (bool);

    function selfRemoveLocker() external returns (bool);

    function slashIdleLocker(
        address _lockerTargetAddress,
        uint256 _rewardAmount,
        address _slasher,
        uint256 _amount,
        address _recipient
    ) external returns (bool);

    function slashThiefLocker(
        address _lockerTargetAddress,
        uint256 _rewardAmount,
        address _slasher,
        uint256 _amount
    ) external returns (bool);

    function buySlashedCollateralOfLocker(
        address _lockerTargetAddress,
        uint256 _collateralAmount
    ) external returns (bool);
}
