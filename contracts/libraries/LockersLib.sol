// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../types/DataTypes.sol";
import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";

library LockersLib {

    function requestToBecomeLockerValidation(
        mapping(address => DataTypes.locker) storage lockersMapping,
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

    function buySlashedCollateralOfLocker(
        DataTypes.locker storage theLocker,
        uint _collateralAmount
    ) external returns (uint neededTeleBTC) {

        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        require(
            _collateralAmount <= theLocker.reservedNativeTokenForSlash,
            "Lockers: not enough slashed collateral to buy"
        );

        neededTeleBTC = theLocker.slashingTeleBTCAmount * _collateralAmount / theLocker.reservedNativeTokenForSlash;

        if (neededTeleBTC < theLocker.slashingTeleBTCAmount) {
            // to avoid precision loss (so buyer cannot profit of it)
            neededTeleBTC = neededTeleBTC + 1;
        }

        // Updates locker's slashing info 
        theLocker.slashingTeleBTCAmount =
            theLocker.slashingTeleBTCAmount - neededTeleBTC;

        theLocker.reservedNativeTokenForSlash =
            theLocker.reservedNativeTokenForSlash - _collateralAmount;

    }

    function liquidateLocker(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _collateralAmount
    ) external view returns (uint neededTeleBTC) {

        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        // DataTypes.locker memory theLiquidatingLocker = lockersMapping[_lockerTargetAddress];
        uint priceOfCollateral = priceOfOneUnitOfCollateralInBTC(
            libConstants,
            libParams
        );

        // Checks that the collateral has become unhealthy
        require(
            calculateHealthFactor(
                theLocker,
                libConstants,
                libParams,
                priceOfCollateral
            ) < libConstants.HealthFactor,
            "Lockers: is healthy"
        );

        uint _maxBuyableCollateral = maximumBuyableCollateral(
            theLocker,
            libConstants,
            libParams,
            priceOfCollateral
        );

        if (_maxBuyableCollateral > theLocker.nativeTokenLockedAmount) {
            _maxBuyableCollateral = theLocker.nativeTokenLockedAmount;
        }

        require(
            _collateralAmount <= _maxBuyableCollateral,
            "Lockers: not enough collateral to buy"
        );

        // Needed amount of TeleBTC to buy collateralAmount
        neededTeleBTC = neededTeleBTCToBuyCollateral(
            libConstants,
            libParams,
            _collateralAmount,
            priceOfCollateral
        );

        neededTeleBTC = neededTeleBTC + 1; // to prevent precision loss

    }

    function slashThiefLocker(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _rewardAmount,
        uint _amount
    ) external returns (uint rewardInNativeToken, uint neededNativeTokenForSlash) {

        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        uint equivalentNativeToken = IPriceOracle(libParams.priceOracle).equivalentOutputAmount(
            _amount, // Total amount of TeleBTC that is slashed
            ITeleBTC(libParams.teleBTC).decimals(), // Decimal of teleBTC
            libConstants.NativeTokenDecimal, // Decimal of TNT
            libParams.teleBTC, // Input token
            libConstants.NativeToken // Output token
        );

        rewardInNativeToken = equivalentNativeToken*_rewardAmount/_amount;
        neededNativeTokenForSlash = equivalentNativeToken*libParams.liquidationRatio/libConstants.OneHundredPercent;

        if ((rewardInNativeToken + neededNativeTokenForSlash) > theLocker.nativeTokenLockedAmount) {
            // Divides total locker's collateral proportional to reward amount and slash amount
            rewardInNativeToken = rewardInNativeToken*theLocker.nativeTokenLockedAmount/
                (rewardInNativeToken + neededNativeTokenForSlash);
            neededNativeTokenForSlash = theLocker.nativeTokenLockedAmount - rewardInNativeToken;
        }

        // Updates locker's bond (in TNT)
        theLocker.nativeTokenLockedAmount
            = theLocker.nativeTokenLockedAmount - (rewardInNativeToken + neededNativeTokenForSlash);

        if (_amount > theLocker.netMinted) {
            _amount = theLocker.netMinted;
        }
        
        theLocker.netMinted
            = theLocker.netMinted - _amount;

        theLocker.slashingTeleBTCAmount
            = theLocker.slashingTeleBTCAmount + _amount; 

        theLocker.reservedNativeTokenForSlash
            = theLocker.reservedNativeTokenForSlash + neededNativeTokenForSlash;
    }

    function slashIdleLocker(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _rewardAmount,
        uint _amount
    ) external returns (uint equivalentNativeToken) {

        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        equivalentNativeToken = IPriceOracle(libParams.priceOracle).equivalentOutputAmount(
            _rewardAmount + _amount, // Total amount of TeleBTC that is slashed
            ITeleBTC(libParams.teleBTC).decimals(), // Decimal of teleBTC
            libConstants.NativeTokenDecimal, // Decimal of TNT
            libParams.teleBTC, // Input token
            libConstants.NativeToken // Output token
        );

        if (equivalentNativeToken > theLocker.nativeTokenLockedAmount) {
            equivalentNativeToken = theLocker.nativeTokenLockedAmount;
        }

        // Updates locker's bond (in TNT)
        theLocker.nativeTokenLockedAmount
        = theLocker.nativeTokenLockedAmount - equivalentNativeToken;
    }

    function maximumBuyableCollateral(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _priceOfOneUnitOfCollateral
    ) public view returns (uint) {

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
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _priceOfOneUnitOfCollateral
    ) public view returns (uint) {
        return (_priceOfOneUnitOfCollateral * theLocker.nativeTokenLockedAmount * 
            (10 ** (1 + ERC20(libParams.teleBTC).decimals())))/
                (theLocker.netMinted * libParams.liquidationRatio * (10 ** (1 + libConstants.NativeTokenDecimal)));
    }

    function neededTeleBTCToBuyCollateral(
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams,
        uint _collateralAmount,
        uint _priceOfCollateral
    ) public pure returns (uint) {
        return (_collateralAmount * _priceOfCollateral * libParams.priceWithDiscountRatio)/
            (libConstants.OneHundredPercent*(10 ** libConstants.NativeTokenDecimal));
    }

    function addToCollateral(
        DataTypes.locker storage theLocker,
        uint _addingNativeTokenAmount
    ) external {

        require(
            theLocker.isLocker,
            "Lockers: no locker"
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

        require(
            theLocker.nativeTokenLockedAmount - _removingNativeTokenAmount >= libParams.minRequiredTNTLockedAmount,
            "Lockers: less than min collateral"
        );

        theLocker.nativeTokenLockedAmount =
        theLocker.nativeTokenLockedAmount - _removingNativeTokenAmount;
    }

    function priceOfOneUnitOfCollateralInBTC(
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams
    ) public view returns (uint) {

        return IPriceOracle(libParams.priceOracle).equivalentOutputAmount(
            (10**libConstants.NativeTokenDecimal), // 1 Ether is 10^18 wei
            libConstants.NativeTokenDecimal,
            ITeleBTC(libParams.teleBTC).decimals(),
            libConstants.NativeToken,
            libParams.teleBTC
        );

    }


    function lockerCollateralInTeleBTC(
        DataTypes.locker storage theLocker,
        DataTypes.lockersLibConstants memory libConstants,
        DataTypes.lockersLibParam memory libParams
    ) public view returns (uint) {

        return IPriceOracle(libParams.priceOracle).equivalentOutputAmount(
            theLocker.nativeTokenLockedAmount,
            libConstants.NativeTokenDecimal,
            ITeleBTC(libParams.teleBTC).decimals(),
            libConstants.NativeToken,
            libParams.teleBTC
        );
    }

}