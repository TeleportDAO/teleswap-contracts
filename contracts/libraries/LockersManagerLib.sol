// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "../oracle/interfaces/IPriceOracle.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "hardhat/console.sol";

library LockersManagerLib {
    error NotCCBurn();
    error ZeroValue();
    error ZeroAddress();

    function requestToBecomeLocker(
        mapping(address => ILockersManager.locker) storage lockersMapping,
        ILockersManager.becomeLockerArguments memory args
    ) external {
        require (args.collateralDecimal != 0, "Lockers: not whitelisted");

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
        uint256 _collateralDecimal,
        uint256 _collateralAmount,
        uint256 _reliabilityFactor
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
                libConstants,
                libParams,
                _collateralToken,
                _collateralDecimal,
                _reliabilityFactor
            ) < libConstants.HealthFactor,
            "Lockers: is healthy"
        );

        uint256 _maxBuyableCollateral = maximumBuyableCollateral(
            theLocker,
            libConstants,
            libParams,
            priceOfCollateral,
            _collateralDecimal,
            _reliabilityFactor
        );

        // TODO this makes health factor equal to zero
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
        uint256 _reliabilityFactor,
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
        if (msg.sender != libParams.ccBurnRouter)
            revert NotCCBurn();

        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        uint256 equivalentNativeToken = IPriceOracle(libParams.priceOracle)
            .equivalentOutputAmount(
                _amount, // Total amount of TeleBTC that is slashed
                8, // Decimal of teleBTC
                _collateralDecimal, // Decimal of locked collateral
                libParams.teleBTC, // Input token
                _collateralToken // Output token
            );
        rewardInNativeToken = (equivalentNativeToken * _rewardAmount) / _amount;
        neededNativeTokenForSlash =
            (equivalentNativeToken * libParams.liquidationRatio * _reliabilityFactor) /
            (libConstants.OneHundredPercent * libConstants.OneHundredPercent);

        if (
            (rewardInNativeToken + neededNativeTokenForSlash) >
            theLocker.nativeTokenLockedAmount
        ) {
            // Divides total locker's collateral proportional to reward amount and slash amount
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
        address _collateralToken,
        uint256 _collateralDecimal,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _rewardAmount,
        uint256 _amount
    ) external returns (uint256 equivalentNativeToken, uint256 rewardAmountInNativeToken) {
        if (msg.sender != libParams.ccBurnRouter)
            revert NotCCBurn();

        require(
            theLocker.isLocker,
            "Lockers: input address is not a valid locker"
        );

        equivalentNativeToken = IPriceOracle(libParams.priceOracle)
            .equivalentOutputAmount(
                _rewardAmount + _amount, // Total amount of TeleBTC that is slashed
                8, // Decimal of teleBTC
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

        
        rewardAmountInNativeToken = equivalentNativeToken -
            ((equivalentNativeToken * _amount) / (_amount + _rewardAmount));
    }

    function maximumBuyableCollateral(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _priceOfOneUnitOfCollateral,
        uint256 _collateralDecimal,
        uint256 _reliabilityFactor
    ) public view returns (uint256) {
        // maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio/10000 - nativeTokenLockedAmount*nativeTokenPrice)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice)
        //  => maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio * 10^18  - nativeTokenLockedAmount*nativeTokenPrice * 10^8)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice * 10^8)

        uint256 teleBTCDecimal = 8;

        uint256 antecedent = ((
                libConstants.UpperHealthFactor *
                theLocker.netMinted *
                libParams.liquidationRatio *
                _reliabilityFactor *
                (10**_collateralDecimal)
            ) / libConstants.OneHundredPercent) -
            (
                theLocker.nativeTokenLockedAmount *
                _priceOfOneUnitOfCollateral *
                (10**teleBTCDecimal)
            );

        uint256 consequent = (
            (   
                libConstants.UpperHealthFactor *
                libParams.liquidationRatio *
                _reliabilityFactor *
                _priceOfOneUnitOfCollateral *
                libParams.priceWithDiscountRatio
            ) / (libConstants.OneHundredPercent * libConstants.OneHundredPercent)) -
            (_priceOfOneUnitOfCollateral * (10**teleBTCDecimal));

        return antecedent / consequent;
    }

    function calculateHealthFactor(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _reliabilityFactor
    ) public view returns (uint256) {
        uint256 _priceOfOneUnitOfCollateral = priceOfOneUnitOfCollateralInBTC(
            _collateralToken,
            _collateralDecimal,
            libParams
        );
        return
            (_priceOfOneUnitOfCollateral *
                theLocker.nativeTokenLockedAmount *
                libConstants.OneHundredPercent *
                (10 * libConstants.OneHundredPercent * libConstants.OneHundredPercent)) /
            (theLocker.netMinted *
                libParams.liquidationRatio *
                _reliabilityFactor *
                (10**(1 + _collateralDecimal)));
        //TODO 1 + ?
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

    function addCollateralHelper(
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.locker storage theLocker,
        uint256 _addingNativeTokenAmount,
        address _collateralToken
    ) external {
        if (_addingNativeTokenAmount == 0) revert ZeroValue();

        require(theLocker.isLocker, "Lockers: no locker");


        if (_collateralToken == libConstants.NativeToken) {
            _addingNativeTokenAmount = msg.value;
        } else {
            require(msg.value == 0, "Lockers: wrong msg value");
        }


        theLocker.nativeTokenLockedAmount =
            theLocker.nativeTokenLockedAmount +
            _addingNativeTokenAmount;

        
    }

    function removeFromCollateral(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        uint256 _lockerReliabilityFactor,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _removingNativeTokenAmount
    ) internal {
        require(theLocker.isLocker, "Lockers: no locker");

        uint256 _priceOfOneUnitOfCollateral = priceOfOneUnitOfCollateralInBTC(_collateralToken, _collateralDecimal, libParams);

        // Capacity of locker = (locker's collateral value in TeleBTC) / (collateral ratio) - (minted TeleBTC)
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
        require (_collateralDecimal != 0, "Lockers: not whitelisted");

        return
            IPriceOracle(libParams.priceOracle).equivalentOutputAmount(
                (10**_collateralDecimal), // 1 unit of collateral
                _collateralDecimal,
                8,
                _collateralToken,
                libParams.teleBTC
            );
    }

    /// @notice                             Get how much the locker can mint
    /// @dev                                Net minted amount is total minted minus total burnt for the locker
    /// @return theLockerCapacity           The net minted of the locker
    function getLockerCapacity(
        ILockersManager.locker memory theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        address _lockerTargetAddress,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _lockerReliabilityFactor
    ) public view returns (uint256 theLockerCapacity) {

        if (_lockerTargetAddress == address(0))
            revert ZeroAddress();

        uint256 _lockerCollateralInTeleBTC = 
            priceOfOneUnitOfCollateralInBTC(_collateralToken, _collateralDecimal, libParams) 
             * theLocker.nativeTokenLockedAmount  * libConstants.OneHundredPercent * libConstants.OneHundredPercent / 
             (libParams.collateralRatio * _lockerReliabilityFactor * (10**_collateralDecimal));
        
        if (_lockerCollateralInTeleBTC > theLocker.netMinted) {
            theLockerCapacity = _lockerCollateralInTeleBTC - theLocker.netMinted;
        } else {
            theLockerCapacity = 0;
        }

    }

    /// @notice                             Mint Helper function
    /// @dev                                Net minted amount is total minted minus total burnt for the locker
    function mintHelper(
        ILockersManager.locker storage theLocker,
        ILockersManager.lockersLibConstants memory libConstants,
        ILockersManager.lockersLibParam memory libParams,
        address _lockerTargetAddress,
        address _collateralToken,
        uint256 _collateralDecimal,
        uint256 _lockerReliabilityFactor,
        uint256 amount
    ) public {
        uint theLockerCapacity = getLockerCapacity(
            theLocker,
            libConstants,
            libParams,
            _lockerTargetAddress,
            _collateralToken,
            _collateralDecimal,
            _lockerReliabilityFactor
        );

        require(theLockerCapacity >= amount, "Lockers: insufficient capacity");

        theLocker.netMinted =
            theLocker.netMinted +
            amount;
    }
    
}
