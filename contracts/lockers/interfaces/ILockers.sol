// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./ILockersStorage.sol";

interface ILockers is ILockersStorage {

     // Events

    event RequestAddLocker(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount
    );

    event RevokeAddLockerRequest(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount
    );

    event RequestInactivateLocker(
        address indexed lockerTargetAddress,
        uint indexed inactivationTimestamp,
        bytes lockerLockingScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        uint netMinted
    );

    event ActivateLocker(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        uint netMinted
    );

    event LockerAdded(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        uint addingTime
    );

    event LockerRemoved(
        address indexed lockerTargetAddress,
        bytes lockerLockingScript,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount
    );

    event LockerSlashed(
        address indexed lockerTargetAddress,
        uint rewardAmount,
        address indexed rewardRecipient,
        uint amount,
        address indexed recipient,
        uint slashedCollateralAmount,
        uint slashTime,
        bool isForCCBurn
    );

    event LockerLiquidated(
        address indexed lockerTargetAddress,
        address indexed liquidatorAddress,
        uint collateralAmount,
        uint teleBTCAmount,
        uint liquidateTime
    );

    event LockerSlashedCollateralSold(
        address indexed lockerTargetAddress,
        address indexed buyerAddress,
        uint slashingAmount,
        uint teleBTCAmount,
        uint slashingTime
    );

    event CollateralAdded(
        address indexed lockerTargetAddress,
        uint addedCollateral,
        uint totalCollateral,
        uint addingTime
    );

    event CollateralRemoved(
        address indexed lockerTargetAddress,
        uint removedCollateral,
        uint totalCollateral,
        uint removingTime
    );

    event MintByLocker(
        address indexed lockerTargetAddress,
        address indexed receiver,
        uint mintedAmount,
        uint lockerFee,
        uint mintingTime
    );

    event BurnByLocker(
        address indexed lockerTargetAddress,
        uint burntAmount,
        uint lockerFee,
        uint burningTime
    );

    event MinterAdded(
        address indexed account
    );

    event MinterRemoved(
        address indexed account
    );

    event BurnerAdded(
        address indexed account
    );
    
    event BurnerRemoved(
        address indexed account
    );

    event NewLockerPercentageFee(
        uint oldLockerPercentageFee,
        uint newLockerPercentageFee
    );

    event NewPriceWithDiscountRatio(
        uint oldPriceWithDiscountRatio,
        uint newPriceWithDiscountRatio
    );

    event NewMinRequiredTDTLockedAmount(
        uint oldMinRequiredTDTLockedAmount,
        uint newMinRequiredTDTLockedAmount
    );

    event NewMinRequiredTNTLockedAmount(
        uint oldMinRequiredTNTLockedAmount,
        uint newMinRequiredTNTLockedAmount
    );

    event NewPriceOracle(
        address oldPriceOracle,
        address newPriceOracle
    );

    event NewCCBurnRouter(
        address oldCCBurnRouter,
        address newCCBurnRouter
    );

    event NewExchangeConnector(
        address oldExchangeConnector,
        address newExchangeConnector
    );

    event NewTeleportDAOToken(
        address oldTDTToken,
        address newTDTToken
    ); 

    event NewTeleBTC(
        address oldTeleBTC,
        address newTeleBTC
    );   

    event NewCollateralRatio(
        uint oldCollateralRatio,
        uint newCollateralRatio
    );  

    event NewLiquidationRatio(
        uint oldLiquidationRatio,
        uint newLiquidationRatio
    );   

    event NewInactivationDelay(
        uint oldInactivationDelay,
        uint newInactivationDelay
    );   


    // Read-only functions
    
    function getLockerTargetAddress(bytes calldata _lockerLockingScript) external view returns (address);

    function isLocker(bytes calldata _lockerLockingScript) external view returns (bool);

    function getNumberOfLockers() external view returns (uint);

    function getLockerLockingScript(address _lockerTargetAddress) external view returns (bytes memory);

    function isLockerActive(address _lockerTargetAddress) external view returns (bool);

    function getLockerCapacity(address _lockerTargetAddress) external view returns (uint);

    function priceOfOneUnitOfCollateralInBTC() external view returns (uint);

    function isMinter(address account) external view returns(bool);

    function isBurner(address account) external view returns(bool);

    // State-changing functions

    function pauseLocker() external;

    function unPauseLocker() external;

    function addMinter(address _account) external;

    function removeMinter(address _account) external;

    function addBurner(address _account) external;

    function removeBurner(address _account) external;

    function mint(bytes calldata _lockerLockingScript, address _receiver, uint _amount) external returns(uint);

    function burn(bytes calldata _lockerLockingScript, uint256 _amount) external returns(uint);

    function setTeleportDAOToken(address _tdtTokenAddress) external;

    function setLockerPercentageFee(uint _lockerPercentageFee) external;

    function setPriceWithDiscountRatio(uint _priceWithDiscountRatio) external;

    function setMinRequiredTDTLockedAmount(uint _minRequiredTDTLockedAmount) external;

    function setMinRequiredTNTLockedAmount(uint _minRequiredTNTLockedAmount) external;

    function setPriceOracle(address _priceOracle) external;

    function setCCBurnRouter(address _ccBurnRouter) external;

    function setExchangeConnector(address _exchangeConnector) external;

    function setTeleBTC(address _teleBTC) external;

    function setCollateralRatio(uint _collateralRatio) external;

    function setLiquidationRatio(uint _liquidationRatio) external;

    function setInactivationDelay(uint _inactivationDelay) external;

    function liquidateLocker(
        address _lockerTargetAddress,
        uint _btcAmount
    ) external returns (bool);

    function addCollateral(
        address _lockerTargetAddress,
        uint _addingNativeTokenAmount
    ) external payable returns (bool);

    function removeCollateral(
        uint _removingNativeTokenAmount
    ) external payable returns (bool);

    function requestToBecomeLocker(
        bytes calldata _lockerLockingScript,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount,
        ScriptTypes _lockerRescueType,
        bytes calldata _lockerRescueScript
    ) external payable returns (bool);

    function revokeRequest() external returns (bool);

    function addLocker(address _lockerTargetAddress) external returns (bool);

    function requestInactivation() external returns (bool);

    function requestActivation() external returns (bool);

    function ownerRemoveLocker(address _lockerTargetAddress) external returns(bool);

    function selfRemoveLocker() external returns (bool);

    function slashIdleLocker(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount,
        address _recipient
    ) external returns(bool);

    function slashThiefLocker(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount
    ) external returns(bool);

    function buySlashedCollateralOfLocker(
        address _lockerTargetAddress,
        uint _collateralAmount
    ) external returns (bool);

}