// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./LockersManagerStorage.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../routers/interfaces/IBurnRouter.sol";
import "../libraries/LockersManagerLib.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

contract LockersManagerLogic is
    LockersManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    error ZeroAddress();
    error ZeroValue();

    using LockersManagerLib for *;
    using SafeERC20 for IERC20;

    function initialize(
        address _teleBTC,
        address _priceOracle,
        address _ccBurnRouter,
        uint256 _minRequiredTDTLockedAmount,
        uint256 _minRequiredTNTLockedAmount,
        uint256 _collateralRatio,
        uint256 _liquidationRatio,
        uint256 _lockerPercentageFee,
        uint256 _priceWithDiscountRatio
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        setTeleBTC(_teleBTC);
        setCCBurnRouter(_ccBurnRouter);
        setPriceOracle(_priceOracle);
        setMinRequiredTDTLockedAmount(_minRequiredTDTLockedAmount);
        setMinRequiredTNTLockedAmount(_minRequiredTNTLockedAmount);
        setCollateralRatio(_collateralRatio);
        setLiquidationRatio(_liquidationRatio);
        setLockerPercentageFee(_lockerPercentageFee);
        setPriceWithDiscountRatio(_priceWithDiscountRatio);

        libConstants.OneHundredPercent = ONE_HUNDRED_PERCENT;
        libConstants.HealthFactor = HEALTH_FACTOR;
        libConstants.UpperHealthFactor = UPPER_HEALTH_FACTOR;
        libConstants.MaxLockerFee = MAX_LOCKER_FEE;
        libConstants.NativeTokenDecimal = NATIVE_TOKEN_DECIMAL;
        libConstants.NativeToken = NATIVE_TOKEN;
    }

    // *************** Modifiers ***************

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    modifier nonZeroValue(uint256 _value) {
        if (_value == 0) revert ZeroValue();
        _;
    }

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "Lockers: only minters can mint");
        _;
    }

    modifier onlyBurner() {
        require(isBurner(_msgSender()), "Lockers: only burners can burn");
        _;
    }

    // *************** External functions ***************

    /// @notice Give an account access to mint
    function addMinter(address _account)
        external
        override
        nonZeroAddress(_account)
        onlyOwner
    {
        require(!isMinter(_account), "Lockers: account already has role");
        minters[_account] = true;
        emit MinterAdded(_account);
    }

    /// @notice Remove an account's access to mint
    function removeMinter(address _account)
        external
        override
        nonZeroAddress(_account)
        onlyOwner
    {
        require(isMinter(_account), "Lockers: account does not have role");
        minters[_account] = false;
        emit MinterRemoved(_account);
    }

    /// @notice Give an account access to burn
    function addBurner(address _account)
        external
        override
        nonZeroAddress(_account)
        onlyOwner
    {
        require(!isBurner(_account), "Lockers: account already has role");
        burners[_account] = true;
        emit BurnerAdded(_account);
    }

    /// @notice Remove an account's access to burn
    function removeBurner(address _account)
        external
        override
        nonZeroAddress(_account)
        onlyOwner
    {
        require(isBurner(_account), "Lockers: account does not have role");
        burners[_account] = false;
        emit BurnerRemoved(_account);
    }

    /// @notice Pause the contract
    /// @dev Only functions with whenPaused modifier can be called
    function pauseLocker() external override onlyOwner {
        _pause();
    }

    /// @notice Un-pause the contract
    /// @dev Only functions with whenNotPaused modifier can be called
    function unPauseLocker() external override onlyOwner {
        _unpause();
    }

    /// @notice Return EVM address of _lockerLockingScript Locker
    function getLockerTargetAddress(bytes calldata _lockerLockingScript)
        external
        view
        override
        returns (address)
    {
        return lockerTargetAddress[_lockerLockingScript];
    }

    /// @notice Return true if _lockerLockingScript is Locker
    function isLocker(bytes calldata _lockerLockingScript)
        external
        view
        override
        returns (bool)
    {
        return
            lockersMapping[lockerTargetAddress[_lockerLockingScript]].isLocker;
    }

    /// @notice Return total number of Lockers
    function getNumberOfLockers() external view override returns (uint256) {
        return totalNumberOfLockers;
    }

    /// @notice Return locking script of _lockerTargetAddress Locker
    function getLockerLockingScript(address _lockerTargetAddress)
        external
        view
        override
        nonZeroAddress(_lockerTargetAddress)
        returns (bytes memory)
    {
        return lockersMapping[_lockerTargetAddress].lockerLockingScript;
    }

    /// @notice Update TST contract address
    function setTST(address _TST)
        public
        override
        onlyOwner
        nonZeroAddress(_TST)
    {
        emit NewTST(TeleportDAOToken, _TST);
        TeleportDAOToken = _TST;
        libParams.teleportDAOToken = TeleportDAOToken;
    }

    /// @notice Update locker percentage fee
    /// @dev This fee is taken by Locker for every minting or burning
    function setLockerPercentageFee(uint256 _lockerPercentageFee)
        public
        override
        onlyOwner
    {
        require(
            _lockerPercentageFee <= MAX_LOCKER_FEE,
            "Lockers: invalid locker fee"
        );
        emit NewLockerPercentageFee(lockerPercentageFee, _lockerPercentageFee);
        lockerPercentageFee = _lockerPercentageFee;
        libParams.lockerPercentageFee = lockerPercentageFee;
    }

    /// @notice Update price with discount ratio
    /// @dev This ratio gives discount to users who participate in Locker liquidation
    function setPriceWithDiscountRatio(uint256 _priceWithDiscountRatio)
        public
        override
        onlyOwner
    {
        require(
            _priceWithDiscountRatio <= ONE_HUNDRED_PERCENT,
            "Lockers: less than 100%"
        );
        emit NewPriceWithDiscountRatio(
            priceWithDiscountRatio,
            _priceWithDiscountRatio
        );

        priceWithDiscountRatio = _priceWithDiscountRatio;
        libParams.priceWithDiscountRatio = priceWithDiscountRatio;
    }

    /// @notice Update the required TST bond to become Locker
    function setMinRequiredTDTLockedAmount(uint256 _minRequiredTDTLockedAmount)
        public
        override
        onlyOwner
    {
        emit NewMinRequiredTDTLockedAmount(
            minRequiredTDTLockedAmount,
            _minRequiredTDTLockedAmount
        );
        minRequiredTDTLockedAmount = _minRequiredTDTLockedAmount;
        libParams.minRequiredTDTLockedAmount = minRequiredTDTLockedAmount;
    }

    /// @notice Update the required native token bond to become Locker
    function setMinRequiredTNTLockedAmount(uint256 _minRequiredTNTLockedAmount)
        public
        override
        nonZeroValue(_minRequiredTNTLockedAmount)
        onlyOwner
    {
        emit NewMinRequiredTNTLockedAmount(
            minRequiredTNTLockedAmount,
            _minRequiredTNTLockedAmount
        );
        minRequiredTNTLockedAmount = _minRequiredTNTLockedAmount;
        libParams.minRequiredTNTLockedAmount = minRequiredTNTLockedAmount;
    }

    /// @notice Update the price oracle
    /// @dev This oracle is used to get the price of native token in BTC
    function setPriceOracle(address _priceOracle)
        public
        override
        nonZeroAddress(_priceOracle)
        onlyOwner
    {
        emit NewPriceOracle(priceOracle, _priceOracle);
        priceOracle = _priceOracle;
        libParams.priceOracle = priceOracle;
    }

    /// @notice Update burn router address
    function setCCBurnRouter(address _ccBurnRouter)
        public
        override
        nonZeroAddress(_ccBurnRouter)
        onlyOwner
    {
        emit NewCCBurnRouter(ccBurnRouter, _ccBurnRouter);
        emit BurnerRemoved(ccBurnRouter);
        burners[ccBurnRouter] = false;
        ccBurnRouter = _ccBurnRouter;
        libParams.ccBurnRouter = ccBurnRouter;
        emit BurnerAdded(ccBurnRouter);
        burners[ccBurnRouter] = true;
    }

    /// @notice Update wrapped BTC address
    function setTeleBTC(address _teleBTC)
        public
        override
        nonZeroAddress(_teleBTC)
        onlyOwner
    {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
        libParams.teleBTC = teleBTC;
    }

    /// @notice Update collateral ratio
    /// @dev This ratio is used to calculate the maximum mintable TeleBTC by a Locker
    function setCollateralRatio(uint256 _collateralRatio)
        public
        override
        onlyOwner
    {
        require(_collateralRatio > liquidationRatio, "Lockers: must CR > LR");
        emit NewCollateralRatio(collateralRatio, _collateralRatio);
        collateralRatio = _collateralRatio;
        libParams.collateralRatio = collateralRatio;
    }

    /// @notice Update liquidation ratio
    function setLiquidationRatio(uint256 _liquidationRatio)
        public
        override
        onlyOwner
    {
        require(collateralRatio > _liquidationRatio, "Lockers: must CR > LR");
        emit NewLiquidationRatio(liquidationRatio, _liquidationRatio);
        liquidationRatio = _liquidationRatio;
        libParams.liquidationRatio = liquidationRatio;
    }

    /// @notice Submit request to become Locker
    /// @dev This request may be approved by the owner
    /// @param _candidateLockingScript Locking script of the Locker. Users can use this script to lock BTC.
    /// @param _lockedTSTAmount TST bond amount
    /// @param _lockedNativeTokenAmount TNT (target native token) bond amount
    /// @param _lockerRescueType Type of Locker's rescue script (e.g. P2SH)
    /// @param _lockerRescueScript Rescue script of Locker. In the case of liqudation, BTC is sent to this script.
    /// @return True if candidate added successfully
    function requestToBecomeLocker(
        bytes calldata _candidateLockingScript,
        uint256 _lockedTSTAmount,
        uint256 _lockedNativeTokenAmount,
        ScriptTypes _lockerRescueType,
        bytes calldata _lockerRescueScript
    ) external payable override nonReentrant returns (bool) {
        LockersManagerLib.requestToBecomeLocker(
            lockersMapping,
            libParams,
            lockerTargetAddress[_candidateLockingScript],
            _lockedTSTAmount,
            _lockedNativeTokenAmount,
            _candidateLockingScript,
            _lockerRescueType,
            _lockerRescueScript
        );

        // TODO if or require?
        if (libParams.teleportDAOToken != address(0)) {
            IERC20(libParams.teleportDAOToken).safeTransferFrom(
                _msgSender(),
                address(this),
                _lockedTSTAmount
            );
        }

        totalNumberOfCandidates = totalNumberOfCandidates + 1;

        emit RequestAddLocker(
            _msgSender(),
            _candidateLockingScript,
            _lockedTSTAmount,
            _lockedNativeTokenAmount
        );

        return true;
    }

    /// @notice Revoke request to become Locker
    /// @dev Send back TST and TNT collateral to the candidate
    /// @return True if the candidate is removed successfully
    function revokeRequest() external override nonReentrant returns (bool) {
        require(lockersMapping[_msgSender()].isCandidate, "Lockers: no req");

        // Loads locker's information
        locker memory lockerRequest = lockersMapping[_msgSender()];

        // Removes candidate from lockersMapping
        delete lockersMapping[_msgSender()];
        totalNumberOfCandidates = totalNumberOfCandidates - 1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).safeTransfer(
            _msgSender(),
            lockerRequest.TDTLockedAmount
        );
        Address.sendValue(
            payable(_msgSender()),
            lockerRequest.nativeTokenLockedAmount
        );

        emit RevokeAddLockerRequest(
            _msgSender(),
            lockersMapping[_msgSender()].lockerLockingScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount
        );

        return true;
    }

    /// @notice Approve the candidate request to become Locker
    /// @dev Only owner can call this. The isCandidate is also set to false.
    /// @param _lockerTargetAddress Locker's target chain address
    /// @return True if the candidate is added successfully
    function addLocker(address _lockerTargetAddress)
        external
        override
        nonZeroAddress(_lockerTargetAddress)
        nonReentrant
        onlyOwner
        returns (bool)
    {
        require(
            lockersMapping[_lockerTargetAddress].isCandidate,
            "Lockers: no request"
        );

        // Updates locker's status
        lockersMapping[_lockerTargetAddress].isCandidate = false;
        lockersMapping[_lockerTargetAddress].isLocker = true;

        // Updates number of candidates and lockers
        totalNumberOfCandidates = totalNumberOfCandidates - 1;
        totalNumberOfLockers = totalNumberOfLockers + 1;

        lockerTargetAddress[
            lockersMapping[_lockerTargetAddress].lockerLockingScript
        ] = _lockerTargetAddress;

        emit LockerAdded(
            _lockerTargetAddress,
            lockersMapping[_lockerTargetAddress].lockerLockingScript,
            lockersMapping[_lockerTargetAddress].TDTLockedAmount,
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
            block.timestamp
        );
        return true;
    }

    /// @notice Request to inactivate Locker
    /// @dev This would inactivate Locker after INACTIVATION_DELAY. The impact of inactivation is:
    ///      1. No one can mint TeleBTC by the Locker
    ///      2. Locker can be removed
    ///      3. Locker can withdraw unused collateral
    /// @return True if deactivated successfully
    function requestInactivation()
        external
        override
        nonReentrant
        returns (bool)
    {
        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: input address is not a valid locker"
        );

        require(
            lockerInactivationTimestamp[_msgSender()] == 0,
            "Lockers: locker has already requested"
        );

        lockerInactivationTimestamp[_msgSender()] =
            block.timestamp +
            INACTIVATION_DELAY;

        emit RequestInactivateLocker(
            _msgSender(),
            lockerInactivationTimestamp[_msgSender()],
            lockersMapping[_msgSender()].lockerLockingScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount,
            lockersMapping[_msgSender()].netMinted
        );

        return true;
    }

    /// @notice Activate Locker
    /// @dev Users can only mint TeleBTC by active locker
    ///      Note: lockerInactivationTimestamp = 0 means that the Locker is active
    /// @return True if activated successfully
    function requestActivation() external override nonReentrant returns (bool) {
        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: input address is not a valid locker"
        );

        lockerInactivationTimestamp[_msgSender()] = 0;

        emit ActivateLocker(
            _msgSender(),
            lockersMapping[_msgSender()].lockerLockingScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount,
            lockersMapping[_msgSender()].netMinted
        );

        return true;
    }

    /// @notice Removes Locker from system and send back Locker TST and TNT collateral.
    /// @dev Only Locker can call this. The conditions for successful remove is:
    ///      1. Locker has been inactivated
    ///      2. Locker net minted TeleBTC is 0
    ///      3. Locker is not being slashed
    /// @return True if locker is removed successfully
    function selfRemoveLocker() external override nonReentrant returns (bool) {
        locker memory _removingLocker = lockersMapping[_msgSender()];

        require(_removingLocker.isLocker, "Lockers: no locker");

        require(!isLockerActive(_msgSender()), "Lockers: still active");

        require(_removingLocker.netMinted == 0, "Lockers: 0 net minted");

        // TODO doesn't exists?
        require(
            _removingLocker.slashingTeleBTCAmount == 0,
            "Lockers: 0 slashing TBTC"
        );

        // Removes locker from lockersMapping

        delete lockerTargetAddress[
            lockersMapping[_msgSender()].lockerLockingScript
        ];
        delete lockersMapping[_msgSender()];
        totalNumberOfLockers = totalNumberOfLockers - 1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).safeTransfer(
            _msgSender(),
            _removingLocker.TDTLockedAmount
        );
        Address.sendValue(
            payable(_msgSender()),
            _removingLocker.nativeTokenLockedAmount
        );

        emit LockerRemoved(
            _msgSender(),
            _removingLocker.lockerLockingScript,
            _removingLocker.TDTLockedAmount,
            _removingLocker.nativeTokenLockedAmount
        );
        return true;
    }

    /// @notice Slash Locker for unprocessed unwrap request
    /// @dev Only burn router can call this. Locker is slashed since he doesn't provide burn proof
    ///      before the request deadline. User who made the burn request will receive the slashed bond.
    /// @param _lockerTargetAddress Locker's target chain address
    /// @param _rewardAmount Amount of TeleBTC that slasher receives
    /// @param _slasher Address of slasher who receives reward
    /// @param _amount Amount of TeleBTC that is slashed from Locker
    /// @param _recipient Address of user who receives the slashed collateral
    /// @return True if the locker is slashed successfully
    function slashIdleLocker(
        address _lockerTargetAddress,
        uint256 _rewardAmount,
        address _slasher,
        uint256 _amount,
        address _recipient
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(
            _msgSender() == ccBurnRouter,
            "Lockers: message sender is not ccBurn"
        );

        uint256 equivalentNativeToken = LockersManagerLib.slashIdleLocker(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            _rewardAmount,
            _amount
        );

        // Transfers TNT to user
        payable(_recipient).transfer(
            (equivalentNativeToken * _amount) / (_amount + _rewardAmount)
        );
        // Transfers TNT to slasher
        uint256 rewardAmountInNativeToken = equivalentNativeToken -
            ((equivalentNativeToken * _amount) / (_amount + _rewardAmount));
        payable(_slasher).transfer(rewardAmountInNativeToken);

        emit LockerSlashed(
            _lockerTargetAddress,
            rewardAmountInNativeToken,
            _slasher,
            _amount,
            _recipient,
            equivalentNativeToken,
            block.timestamp,
            true
        );

        return true;
    }

    /// @notice Slash Locker for stealing users BTC
    /// @dev Only burn router can call. Locker is slashed because he moved BTC from
    ///      Locker's Bitcoin address without any corresponding burn req.
    ///      The slashed bond will be sold with discount.
    /// @param _lockerTargetAddress Locker's target chain address
    /// @param _rewardAmount Value of slashed reward (in TeleBTC)
    /// @param _slasher Address of slasher who receives reward
    /// @param _amount Value of slashed collateral (in TeleBTC)
    /// @return True if the locker is slashed successfully
    function slashThiefLocker(
        address _lockerTargetAddress,
        uint256 _rewardAmount,
        address _slasher,
        uint256 _amount
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(
            _msgSender() == ccBurnRouter,
            "Lockers: message sender is not ccBurn"
        );

        (
            uint256 rewardInNativeToken,
            uint256 neededNativeTokenForSlash
        ) = LockersManagerLib.slashThiefLocker(
                lockersMapping[_lockerTargetAddress],
                libConstants,
                libParams,
                _rewardAmount,
                _amount
            );

        payable(_slasher).transfer(rewardInNativeToken);

        emit LockerSlashed(
            _lockerTargetAddress,
            rewardInNativeToken,
            _slasher,
            _amount,
            address(this),
            neededNativeTokenForSlash + rewardInNativeToken,
            block.timestamp,
            false
        );

        return true;
    }

    /// @notice Liquidate Locker with unhealthy collateral
    /// @dev Anyone can liquidate Locker with health factor under
    ///      100% by providing a sufficient amount of TeleBTC.
    /// @param _lockerTargetAddress Locker's target chain address
    /// @param _collateralAmount Amount of TNT collateral that someone wants to buy with discount
    /// @return True if liquidation was successful
    function liquidateLocker(
        address _lockerTargetAddress,
        uint256 _collateralAmount
    )
        external
        override
        nonZeroAddress(_lockerTargetAddress)
        nonZeroValue(_collateralAmount)
        nonReentrant
        whenNotPaused
        returns (bool)
    {
        uint256 neededTeleBTC = LockersManagerLib.liquidateLocker(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            _collateralAmount
        );

        locker memory theLiquidatingLocker = lockersMapping[
            _lockerTargetAddress
        ];

        // Updates TNT bond of locker
        lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount =
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount -
            _collateralAmount;

        // transfer teleBTC from user
        IERC20(teleBTC).safeTransferFrom(
            msg.sender,
            address(this),
            neededTeleBTC
        );

        // Burns TeleBTC for locker rescue script
        IERC20(teleBTC).approve(ccBurnRouter, neededTeleBTC);
        IBurnRouter(ccBurnRouter).unwrap(
            neededTeleBTC,
            theLiquidatingLocker.lockerRescueScript,
            theLiquidatingLocker.lockerRescueType,
            theLiquidatingLocker.lockerLockingScript,
            0
        );

        Address.sendValue(payable(_msgSender()), _collateralAmount);

        emit LockerLiquidated(
            _lockerTargetAddress,
            _msgSender(),
            _collateralAmount,
            neededTeleBTC,
            block.timestamp
        );

        return true;
    }

    /// @notice                           Sells lockers slashed collateral
    /// @dev                              Users buy the slashed collateral using TeleBTC with discount
    ///                                   The paid TeleBTC will be burnt to keep the system safe
    ///                                   If all the needed TeleBTC is collected and burnt,
    ///                                   the rest of slashed collateral is sent back to locker
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _collateralAmount          Amount of collateral (TNT) that someone intends to buy with discount
    /// @return                           True if buying was successful
    function buySlashedCollateralOfLocker(
        address _lockerTargetAddress,
        uint256 _collateralAmount
    )
        external
        override
        nonZeroAddress(_lockerTargetAddress)
        nonReentrant
        whenNotPaused
        returns (bool)
    {
        uint256 neededTeleBTC = LockersManagerLib.buySlashedCollateralOfLocker(
            lockersMapping[_lockerTargetAddress],
            _collateralAmount
        );

        // Burns user's TeleBTC
        ITeleBTC(teleBTC).transferFrom(
            _msgSender(),
            address(this),
            neededTeleBTC
        );
        ITeleBTC(teleBTC).burn(neededTeleBTC);

        // Sends bought collateral to user
        Address.sendValue(payable(_msgSender()), _collateralAmount);

        emit LockerSlashedCollateralSold(
            _lockerTargetAddress,
            _msgSender(),
            _collateralAmount,
            neededTeleBTC,
            block.timestamp
        );

        return true;
    }

    /// @notice                                 Increases TNT collateral of the locker
    /// @param _lockerTargetAddress             Locker's target chain address
    /// @param _addingNativeTokenAmount         Amount of added collateral
    /// @return                                 True if collateral is added successfully
    function addCollateral(
        address _lockerTargetAddress,
        uint256 _addingNativeTokenAmount
    ) external payable override nonReentrant returns (bool) {
        LockersManagerLib.addToCollateral(
            msg.value,
            lockersMapping[_lockerTargetAddress],
            _addingNativeTokenAmount
        );

        emit CollateralAdded(
            _lockerTargetAddress,
            _addingNativeTokenAmount,
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
            block.timestamp
        );

        return true;
    }

    /// @notice                                 Decreases TNT collateral of the locker
    /// @param _removingNativeTokenAmount       Amount of removed collateral
    /// @return                                 True if collateral is removed successfully
    function removeCollateral(uint256 _removingNativeTokenAmount)
        external
        payable
        override
        nonReentrant
        returns (bool)
    {
        require(lockersMapping[_msgSender()].isLocker, "Lockers: no locker");

        require(!isLockerActive(_msgSender()), "Lockers: still active");

        uint256 priceOfOnUnitOfCollateral = LockersManagerLib
            .priceOfOneUnitOfCollateralInBTC(libConstants, libParams);

        LockersManagerLib.removeFromCollateral(
            lockersMapping[_msgSender()],
            libConstants,
            libParams,
            priceOfOnUnitOfCollateral,
            _removingNativeTokenAmount
        );

        Address.sendValue(payable(_msgSender()), _removingNativeTokenAmount);

        emit CollateralRemoved(
            _msgSender(),
            _removingNativeTokenAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount,
            block.timestamp
        );

        return true;
    }

    /// @notice                       Mint teleBTC for an account
    /// @dev                          Mint teleBTC for an account and the locker fee as well
    /// @param _lockerLockingScript   Locking script of a locker
    /// @param _receiver              Address of the receiver of the minted teleBTCs
    /// @param _amount                Amount of the teleBTC which is minted, including the locker's fee
    /// @return uint                  The amount of teleBTC minted for the receiver
    function mint(
        bytes calldata _lockerLockingScript,
        address _receiver,
        uint256 _amount
    )
        external
        override
        nonZeroAddress(_receiver)
        nonZeroValue(_amount)
        nonReentrant
        whenNotPaused
        onlyMinter
        returns (uint256)
    {
        address _lockerTargetAddress = lockerTargetAddress[
            _lockerLockingScript
        ];

        require(_lockerTargetAddress != address(0), "Lockers: address is zero");

        LockersManagerLib.getLockerCapacity(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            lockersMapping[_lockerTargetAddress].netMinted,
            _amount
        );

        require(isLockerActive(_lockerTargetAddress), "Lockers: not active");

        lockersMapping[_lockerTargetAddress].netMinted =
            lockersMapping[_lockerTargetAddress].netMinted +
            _amount;

        // Mints locker fee
        uint256 lockerFee = (_amount * lockerPercentageFee) / MAX_LOCKER_FEE;
        if (lockerFee > 0) {
            ITeleBTC(teleBTC).mint(_lockerTargetAddress, lockerFee);
        }

        // Mints tokens for receiver
        ITeleBTC(teleBTC).mint(_receiver, _amount - lockerFee);

        emit MintByLocker(
            _lockerTargetAddress,
            _receiver,
            _amount,
            lockerFee,
            block.timestamp
        );

        return _amount - lockerFee;
    }

    /// @notice                       Burn teleBTC of an account
    /// @dev                          Burn teleBTC and also get the locker's fee
    /// @param _lockerLockingScript   Locking script of a locker
    /// @param _amount                Amount of the teleBTC which is minted, including the locker's fee
    /// @return uint                  The amount of teleBTC burnt
    function burn(bytes calldata _lockerLockingScript, uint256 _amount)
        external
        override
        nonZeroValue(_amount)
        nonReentrant
        whenNotPaused
        onlyBurner
        returns (uint256)
    {
        address _lockerTargetAddress = lockerTargetAddress[
            _lockerLockingScript
        ];

        // Transfers teleBTC from user
        require(
            ITeleBTC(teleBTC).transferFrom(
                _msgSender(),
                address(this),
                _amount
            ),
            "Lockers: transferFrom failed"
        );

        uint256 lockerFee = (_amount * lockerPercentageFee) / MAX_LOCKER_FEE;
        uint256 remainedAmount = _amount - lockerFee;
        uint256 netMinted = lockersMapping[_lockerTargetAddress].netMinted;

        require(netMinted >= remainedAmount, "Lockers: insufficient funds");

        lockersMapping[_lockerTargetAddress].netMinted =
            netMinted -
            remainedAmount;

        // Burns teleBTC and sends rest of it to locker
        require(ITeleBTC(teleBTC).burn(remainedAmount), "Lockers: burn failed");
        require(
            ITeleBTC(teleBTC).transfer(_lockerTargetAddress, lockerFee),
            "Lockers: lockerFee failed"
        );

        emit BurnByLocker(
            _lockerTargetAddress,
            _amount,
            lockerFee,
            block.timestamp
        );

        return remainedAmount;
    }

    // *************** Public functions ***************

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice                             Returns the Locker status
    /// @dev                                We check a locker status in below cases:
    ///                                     1. Minting TeleBTC
    ///                                     2. Removing locker's collateral
    ///                                     3. Removing locker
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             True if the locker is active
    function isLockerActive(address _lockerTargetAddress)
        public
        view
        override
        nonZeroAddress(_lockerTargetAddress)
        returns (bool)
    {
        if (lockerInactivationTimestamp[_lockerTargetAddress] == 0) {
            return true;
        } else if (
            lockerInactivationTimestamp[_lockerTargetAddress] > block.timestamp
        ) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev         Returns the price of one native token (1*10^18) in teleBTC
     * @return uint The price of one unit of collateral token (native token in teleBTC)
     */
    function priceOfOneUnitOfCollateralInBTC()
        public
        view
        override
        returns (uint256)
    {
        return
            LockersManagerLib.priceOfOneUnitOfCollateralInBTC(
                libConstants,
                libParams
            );
    }

    /// @notice                Check if an account is minter
    /// @param  account        The account which intended to be checked
    /// @return bool
    function isMinter(address account)
        public
        view
        override
        nonZeroAddress(account)
        returns (bool)
    {
        return minters[account];
    }

    /// @notice                Check if an account is burner
    /// @param  account        The account which intended to be checked
    /// @return bool
    function isBurner(address account)
        public
        view
        override
        nonZeroAddress(account)
        returns (bool)
    {
        return burners[account];
    }
}
