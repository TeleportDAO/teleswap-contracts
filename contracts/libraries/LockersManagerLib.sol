// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "hardhat/console.sol";

library LockersManagerLib {
    function requestToBecomeLocker(
        mapping(address => ILockersManager.locker) storage lockersMapping,
        ILockersManager.becomeLockerArguments memory args
    ) external {
        require(
            !lockersMapping[msg.sender].isCandidate,
            "Lockers: is candidate"
        );

        require(!lockersMapping[msg.sender].isLocker, "Lockers: is locker");

        require(
            args._lockedTDTAmount >= args.libParams.minRequiredTDTLockedAmount,
            "Lockers: low TDT"
        );

        if (args.collateralToken != args.libConstants.NativeToken) {
            require(msg.value == 0, "Lockers: wrong msg value");
        } else {
            require(msg.value == args._lockedNativeTokenAmount, "Lockers: wrong msg value");
        }

        require(
            args.theLockerTargetAddress == address(0),
            "Lockers: used locking script"
        );

        ILockersManager.locker memory locker_;
        locker_.lockerLockingScript = args._candidateLockingScript;
        locker_.TDTLockedAmount = args._lockedTDTAmount;
        locker_.nativeTokenLockedAmount = args._lockedNativeTokenAmount;
        locker_.isCandidate = true;
        locker_.lockerRescueType = args._lockerRescueType;
        locker_.lockerRescueScript = args._lockerRescueScript;

        lockersMapping[msg.sender] = locker_;
    }

    function buySlashedCollateralOfLocker(
        ILockersManager.locker storage theLocker,
        uint256 _collateralAmount
    ) external returns (uint256 neededTeleBTC) {
        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        require(
            _collateralAmount <= theLocker.reservedNativeTokenForSlash,
            "Lockers: not enough slashed collateral to buy"
        );

        neededTeleBTC =
            (theLocker.slashingTeleBTCAmount * _collateralAmount) /
            theLocker.reservedNativeTokenForSlash;

        if (neededTeleBTC < theLocker.slashingTeleBTCAmount) {
            // to avoid precision loss (so buyer cannot profit of it)
            neededTeleBTC = neededTeleBTC + 1;
        }

        // Updates locker's slashing info
        theLocker.slashingTeleBTCAmount =
            theLocker.slashingTeleBTCAmount -
            neededTeleBTC;

        theLocker.reservedNativeTokenForSlash =
            theLocker.reservedNativeTokenForSlash -
            _collateralAmount;
    }

    function liquidateLocker(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        address _collateralToken,
        uint _collateralDecimal,
        uint256 _collateralAmount
    ) external view returns (uint256 neededTeleBTC) {
        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        // ILockersManager.locker memory theLiquidatingLocker = lockersMapping[_lockerTargetAddress];
        uint256 priceOfCollateral = priceOfOneUnitOfCollateralInBTC(
            _collateralToken,
            _collateralDecimal,
            libParams
        );

        // Checks that the collateral has become unhealthy
        require(
            calculateHealthFactor(
                theLocker,
                libParams,
                priceOfCollateral,
                _collateralDecimal
            ) < libConstants.HealthFactor,
            "Lockers: is healthy"
        );

        uint256 _maxBuyableCollateral = maximumBuyableCollateral(
            theLocker,
            libConstants,
            libParams,
            priceOfCollateral,
            _collateralDecimal
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
            _collateralDecimal,
            priceOfCollateral
        );

        neededTeleBTC = neededTeleBTC + 1; // to prevent precision loss
    }

    function slashThiefLocker(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _rewardAmount,
        uint256 _amount
    )
        external
        returns (uint256 rewardInNativeToken, uint256 neededNativeTokenForSlash)
    {
        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        uint256 equivalentNativeToken = IPriceOracle(libParams.priceOracle)
            .equivalentOutputAmount(
                _amount, // Total amount of TeleBTC that is slashed
                ITeleBTC(libParams.teleBTC).decimals(), // Decimal of teleBTC
                _collateralDecimal, // Decimal of locked collateral
                libParams.teleBTC, // Input token
                _collateralToken // Output token
            );

        rewardInNativeToken = (equivalentNativeToken * _rewardAmount) / _amount;
        neededNativeTokenForSlash =
            (equivalentNativeToken * libParams.liquidationRatio) /
            libConstants.OneHundredPercent;

        if (
            (rewardInNativeToken + neededNativeTokenForSlash) >
            theLocker.nativeTokenLockedAmount
        ) {
            // Divides total locker's collateral proportional to reward amount and slash amount
            //TODO check by Mahdi
            rewardInNativeToken =
                (rewardInNativeToken * theLocker.nativeTokenLockedAmount) /
                (rewardInNativeToken + neededNativeTokenForSlash);
            neededNativeTokenForSlash =
                theLocker.nativeTokenLockedAmount -
                rewardInNativeToken;
        }

        // Updates locker's bond (in TNT)
        theLocker.nativeTokenLockedAmount =
            theLocker.nativeTokenLockedAmount -
            (rewardInNativeToken + neededNativeTokenForSlash);

        if (_amount > theLocker.netMinted) {
            _amount = theLocker.netMinted;
        }

        theLocker.netMinted = theLocker.netMinted - _amount;

        theLocker.slashingTeleBTCAmount =
            theLocker.slashingTeleBTCAmount +
            _amount;

        theLocker.reservedNativeTokenForSlash =
            theLocker.reservedNativeTokenForSlash +
            neededNativeTokenForSlash;
    }

    function slashIdleLocker(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibParam memory libParams,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _rewardAmount,
        uint256 _amount
    ) external returns (uint256 equivalentNativeToken) {
        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        equivalentNativeToken = IPriceOracle(libParams.priceOracle)
            .equivalentOutputAmount(
                _rewardAmount + _amount, // Total amount of TeleBTC that is slashed
                ITeleBTC(libParams.teleBTC).decimals(), // Decimal of teleBTC
                _collateralDecimal, // Decimal of locked collateral
                libParams.teleBTC, // Input token
                _collateralToken // Output token
            );

        if (equivalentNativeToken > theLocker.nativeTokenLockedAmount) {
            equivalentNativeToken = theLocker.nativeTokenLockedAmount;
        }

        // Updates locker's bond (in TNT)
        theLocker.nativeTokenLockedAmount =
            theLocker.nativeTokenLockedAmount -
            equivalentNativeToken;
    }

    function maximumBuyableCollateral(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _priceOfOneUnitOfCollateral,
        uint256 _collateralDecimal
    ) public view returns (uint256) {
        //TODO check by Mahdi
        // maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio/10000 - nativeTokenLockedAmount*nativeTokenPrice)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice)
        //  => maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio * 10^18  - nativeTokenLockedAmount*nativeTokenPrice * 10^8)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice * 10^8)

        uint256 teleBTCDecimal = ERC20(libParams.teleBTC).decimals();

        uint256 antecedent = (libConstants.UpperHealthFactor *
            theLocker.netMinted *
            libParams.liquidationRatio *
            (10**_collateralDecimal)) -
            (theLocker.nativeTokenLockedAmount *
                _priceOfOneUnitOfCollateral *
                (10**teleBTCDecimal));

        uint256 consequent = ((libConstants.UpperHealthFactor *
            libParams.liquidationRatio *
            _priceOfOneUnitOfCollateral *
            libParams.priceWithDiscountRatio) /
            libConstants.OneHundredPercent) -
            (_priceOfOneUnitOfCollateral * (10**teleBTCDecimal));

        return antecedent / consequent;
    }

    function calculateHealthFactor(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _priceOfOneUnitOfCollateral,
        uint256 _collateralDecimal
    ) public view returns (uint256) {
        return
            (_priceOfOneUnitOfCollateral *
                theLocker.nativeTokenLockedAmount *
                (10**(1 + ERC20(libParams.teleBTC).decimals()))) /
            (theLocker.netMinted *
                libParams.liquidationRatio *
                (10**(1 + _collateralDecimal)));
    }

    function neededTeleBTCToBuyCollateral(
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _collateralAmount,
        uint256 _collateralDecimal,
        uint256 _priceOfCollateral
    ) public pure returns (uint256) {
        return
            (_collateralAmount *
                _priceOfCollateral *
                libParams.priceWithDiscountRatio) /
            (libConstants.OneHundredPercent *
                (10**_collateralDecimal));
    }

    function addToCollateral(
        ILockersManager.locker storage theLocker,
        uint256 _addingNativeTokenAmount
    ) external {
        require(theLocker.isLocker, "Lockers: no locker");

        theLocker.nativeTokenLockedAmount =
            theLocker.nativeTokenLockedAmount +
            _addingNativeTokenAmount;
    }

    function removeFromCollateral(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _lockerReliabilityFactor,
        uint256 _collateralDecimal,
        uint256 _priceOfOneUnitOfCollateral,
        uint256 _removingNativeTokenAmount
    ) internal {
        require(theLocker.isLocker, "Lockers: no locker");

        // Capacity of locker = (locker's collateral value in TeleBTC) * (collateral ratio) - (minted TeleBTC)
        uint256 lockerCapacity = (theLocker.nativeTokenLockedAmount *
            _priceOfOneUnitOfCollateral *
            libConstants.OneHundredPercent *
            libConstants.OneHundredPercent) /
            (
                libParams.collateralRatio * 
                _lockerReliabilityFactor * 
                (10**_collateralDecimal)
            ) - theLocker.netMinted;

        uint256 maxRemovableCollateral = (lockerCapacity *
            (10**_collateralDecimal)) /
            _priceOfOneUnitOfCollateral;

        require(
            _removingNativeTokenAmount <= maxRemovableCollateral,
            "Lockers: more than max removable collateral"
        );

        theLocker.nativeTokenLockedAmount =
            theLocker.nativeTokenLockedAmount -
            _removingNativeTokenAmount;
    }

    function priceOfOneUnitOfCollateralInBTC(
        address _collateralToken,
        uint _collateralDecimal,
        ILockersManager.lockersLibParam memory libParams
    ) public view returns (uint256) {
        return
            IPriceOracle(libParams.priceOracle).equivalentOutputAmount(
                (10**_collateralDecimal), // 1 unit of collateral
                _collateralDecimal,
                ITeleBTC(libParams.teleBTC).decimals(),
                _collateralToken,
                libParams.teleBTC
            );
    }

    /// @notice                             Get how much the locker can mint
    /// @dev                                Net minted amount is total minted minus total burnt for the locker
    /// @return theLockerCapacity           The net minted of the locker
    function getLockerCapacity(
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _nativeTokenLockedAmount,
        uint256 _lockerReliabilityFactor,
        uint256 netMinted,
        uint256 amount
    ) public view returns (uint256 theLockerCapacity) {
        uint256 _lockerCollateralInTeleBTC = 
            priceOfOneUnitOfCollateralInBTC(_collateralToken, _collateralDecimal, libParams) 
             * _nativeTokenLockedAmount  * libConstants.OneHundredPercent * libConstants.OneHundredPercent / 
             (libParams.collateralRatio * _lockerReliabilityFactor * (10**_collateralDecimal));

        if (_lockerCollateralInTeleBTC > netMinted) {
            theLockerCapacity = _lockerCollateralInTeleBTC - netMinted;
        } else {
            theLockerCapacity = 0;
        }

        // console.log(theLockerCapacity, amount);

        require(theLockerCapacity >= amount, "Lockers: insufficient capacity");
    }
}
