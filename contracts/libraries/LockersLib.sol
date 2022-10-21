// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;


import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../types/ScriptTypesEnum.sol";
import "../types/DataTypes.sol";

library LockersLib {

    using SafeERC20 for IERC20;

    function requestToBecomeLockerValidation(
        mapping(address => DataTypes.locker) storage lockersMapping,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        address theLockerTargetAddress,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount
    ) external {

        require(
            !lockersMapping[msg.sender].isCandidate,
            "Lockers: is candidate"
        );

        require(
            !lockersMapping[msg.sender].isLocker,
            "Lockers: is locker"
        );

        require(
            _lockedTDTAmount >= libParams.minRequiredTDTLockedAmount,
            "Lockers: low TDT"
        );

        require(
            _lockedNativeTokenAmount >= libParams.minRequiredTNTLockedAmount && msg.value == _lockedNativeTokenAmount,
            "Lockers: low TNT"
        );

        require(
            theLockerTargetAddress == address(0),
            "Lockers: used locking script"
        );

    }

    function requestToBecomeLocker(
        mapping(address => DataTypes.locker) storage lockersMapping,
        bytes calldata _candidateLockingScript,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount,
        ScriptTypes _lockerRescueType,
        bytes calldata _lockerRescueScript
    ) external {

        DataTypes.locker memory locker_;
        locker_.lockerLockingScript = _candidateLockingScript;
        locker_.TDTLockedAmount = _lockedTDTAmount;
        locker_.nativeTokenLockedAmount = _lockedNativeTokenAmount;
        locker_.isCandidate = true;
        locker_.lockerRescueType = _lockerRescueType;
        locker_.lockerRescueScript = _lockerRescueScript;

        lockersMapping[msg.sender] = locker_;

    }

    function maximumBuyableCollateral(
        DataTypes.locker memory theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _priceOfOneUnitOfCollateral
    ) external view returns (uint) {

        // maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio/10000 - nativeTokenLockedAmount*nativeTokenPrice)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice)
        //  => maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio * 10^18  - nativeTokenLockedAmount*nativeTokenPrice * 10^8)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice * 10^8)

        uint teleBTCDecimal = ERC20(libParams.teleBTC).decimals();

        uint antecedent = (libConstants.UpperHealthFactor * theLocker.netMinted * libParams.liquidationRatio * (10 ** libConstants.NativeTokenDecimal)) -
        (theLocker.nativeTokenLockedAmount * _priceOfOneUnitOfCollateral * (10 ** teleBTCDecimal));

        uint consequent = ((libConstants.UpperHealthFactor * libParams.liquidationRatio * _priceOfOneUnitOfCollateral * libParams.priceWithDiscountRatio)/libConstants.OneHundredPercent) -
        (_priceOfOneUnitOfCollateral * (10 ** teleBTCDecimal));

        return antecedent/consequent;
    }

    function calculateHealthFactor(
        DataTypes.locker memory theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _priceOfOneUnitOfCollateral
    ) external view returns (uint) {
        return (_priceOfOneUnitOfCollateral * theLocker.nativeTokenLockedAmount * 
            (10 ** (1 + ERC20(libParams.teleBTC).decimals())))/
                (theLocker.netMinted * libParams.liquidationRatio * (10 ** (1 + libConstants.NativeTokenDecimal)));
    }

    function neededTeleBTCToBuyCollateral(
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _collateralAmount,
        uint _priceOfCollateral
    ) external pure returns (uint) {
        return (_collateralAmount * _priceOfCollateral * libParams.priceWithDiscountRatio)/
            (libConstants.OneHundredPercent*(10 ** libConstants.NativeTokenDecimal));
    }

    function addToCollateral(
        DataTypes.locker storage theLocker,
        uint _addingNativeTokenAmount
    ) external {

        require(
            theLocker.isLocker,
            "Lockers: account is not a locker"
        );

        theLocker.nativeTokenLockedAmount =
        theLocker.nativeTokenLockedAmount + _addingNativeTokenAmount;
    }

    function removeFromCollateral(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _priceOfOneUnitOfCollateral,
        uint _removingNativeTokenAmount
    ) internal {

        require(
            theLocker.isLocker,
            "Lockers: account is not a locker"
        );

        // Capacity of locker = (locker's collateral value in TeleBTC) * (collateral ratio) - (minted TeleBTC) 
        uint lockerCapacity = (theLocker.nativeTokenLockedAmount * _priceOfOneUnitOfCollateral * 
            libConstants.OneHundredPercent)/
                (libParams.collateralRatio * (10 ** libConstants.NativeTokenDecimal)) - theLocker.netMinted;

        uint maxRemovableCollateral = (lockerCapacity * (10 ** libConstants.NativeTokenDecimal))/_priceOfOneUnitOfCollateral;

        require(
            _removingNativeTokenAmount <= maxRemovableCollateral,
            "Lockers: more than max removable collateral"
        );

        theLocker.nativeTokenLockedAmount =
        theLocker.nativeTokenLockedAmount - _removingNativeTokenAmount;
    }


    function slashTheifLocker(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _equivalentNativeToken,
        uint _rewardAmount,
        uint _amount
    ) external returns (uint, uint) {
        uint rewardInNativeToken = _equivalentNativeToken*_rewardAmount/_amount;
        uint neededNativeTokenForSlash = _equivalentNativeToken*libParams.liquidationRatio/libConstants.OneHundredPercent;

        if ((rewardInNativeToken + neededNativeTokenForSlash) > theLocker.nativeTokenLockedAmount) {
            // Divides total locker's collateral proportional to reward amount and slash amount
            rewardInNativeToken = rewardInNativeToken*theLocker.nativeTokenLockedAmount/
                (rewardInNativeToken + neededNativeTokenForSlash);
            neededNativeTokenForSlash = theLocker.nativeTokenLockedAmount - rewardInNativeToken;
        }

        // Updates locker's bond (in TNT)
        theLocker.nativeTokenLockedAmount
            = theLocker.nativeTokenLockedAmount - (rewardInNativeToken + neededNativeTokenForSlash);

        theLocker.netMinted
            = theLocker.netMinted - _amount;

        theLocker.slashingTeleBTCAmount
            = theLocker.slashingTeleBTCAmount + _amount;

        theLocker.reservedNativeTokenForSlash
            = theLocker.reservedNativeTokenForSlash + neededNativeTokenForSlash;

        return (rewardInNativeToken, neededNativeTokenForSlash);
    }

}




