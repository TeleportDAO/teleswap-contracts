// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "../oracle/interfaces/IPriceOracle.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../routers/interfaces/ICCBurnRouter.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILockers.sol";
import "../libraries/LockersLib.sol";
import "./LockersStorageStructure.sol";
import "hardhat/console.sol";

contract LockersLogic is LockersStorageStructure, ILockers, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    using LockersLib for *;
    using SafeERC20 for IERC20;

   
    function initialize(
        address _teleBTC,
        address _TeleportDAOToken,
        address _exchangeConnector,
        address _priceOracle,
        address _ccBurnRouter,
        uint _minRequiredTDTLockedAmount,
        uint _minRequiredTNTLockedAmount,
        uint _collateralRatio,
        uint _liquidationRatio,
        uint _lockerPercentageFee,
        uint _priceWithDiscountRatio
    ) public initializer {

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        // TODO not checked in setter function
        require(
            _minRequiredTDTLockedAmount != 0 || _minRequiredTNTLockedAmount != 0,
            "Lockers: amount is zero"
        );

        _setTeleportDAOToken(_TeleportDAOToken);
        _setTeleBTC(_teleBTC);
        _setCCBurnRouter(_ccBurnRouter);
        _setExchangeConnector(_exchangeConnector);
        _setPriceOracle(_priceOracle);
        _setMinRequiredTDTLockedAmount(_minRequiredTDTLockedAmount);
        _setMinRequiredTNTLockedAmount(_minRequiredTNTLockedAmount);
        _setLiquidationRatio(_liquidationRatio);
        _setCollateralRatio(_collateralRatio);
        _setLockerPercentageFee(_lockerPercentageFee);
        _setPriceWithDiscountRatio(_priceWithDiscountRatio);

        libConstants.OneHundredPercent = ONE_HUNDRED_PERCENT;
        libConstants.HealthFactor = HEALTH_FACTOR;
        libConstants.UpperHealthFactor = UPPER_HEALTH_FACTOR;
        libConstants.MaxLockerFee = MAX_LOCKER_FEE;
        libConstants.NativeTokenDecimal = NATIVE_TOKEN_DECIMAL;
        libConstants.NativeToken = NATIVE_TOKEN;

    }

    function renounceOwnership() public virtual override onlyOwner {}

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "Lockers: address is zero");
        _;
    }

    modifier nonZeroValue(uint _value) {
        require(_value > 0, "Lockers: value is zero");
        _;
    }

    modifier onlyMinter() {
        require(_isMinter(_msgSender()), "Lockers: only minters can mint");
        _;
    }

    /**
     * @dev Give an account access to mint.
     */
    function addMinter(address _account) external override nonZeroAddress(_account) onlyOwner {
        require(!_isMinter(_account), "Lockers: account already has role");
        minters[_account] = true;
        emit MinterAdded(_account);
    }

    /**
     * @dev Remove an account's access to mint.
     */
    function removeMinter(address _account) external override nonZeroAddress(_account) onlyOwner {
        require(_isMinter(_account), "Lockers: account does not have role");
        minters[_account] = false;
        emit MinterRemoved(_account);
    }

    modifier onlyBurner() {
        require(_isBurner(_msgSender()), "Lockers: only burners can burn");
        _;
    }

    /**
     * @dev Give an account access to burn.
     */
    function addBurner(address _account) external override nonZeroAddress(_account) onlyOwner {
        require(!_isBurner(_account), "Lockers: account already has role");
        burners[_account] = true;
        emit BurnerAdded(_account);
    }

    /**
     * @dev Remove an account's access to burn.
     */
    function removeBurner(address _account) external override nonZeroAddress(_account) onlyOwner {
        require(_isBurner(_account), "Lockers: account does not have role");
        burners[_account] = false;
        emit BurnerRemoved(_account);
    }

    /// @notice                 Pause the locker, so only the functions can be called which are whenPaused
    /// @dev
    /// @param
    function pauseLocker() external override onlyOwner {
        _pause();
    }

    /// @notice                 Un-pause the locker, so only the functions can be called which are whenNotPaused
    /// @dev
    /// @param
    function unPauseLocker() external override onlyOwner {
        _unpause();
    }

    function getLockerTargetAddress(bytes calldata  _lockerLockingScript) external view override returns (address) {
        return lockerTargetAddress[_lockerLockingScript];
    }

    /// @notice                           Checks whether an address is locker
    /// @dev
    /// @param _lockerTargetAddress       Address of locker on the target chain
    /// @return                           True if user is locker
    function isLocker(bytes calldata _lockerLockingScript) external override view returns(bool) {
        return lockersMapping[lockerTargetAddress[_lockerLockingScript]].isLocker;
    }

    /// @notice                           Give number of lockers
    /// @dev
    /// @return                           Number of lockers
    function getNumberOfLockers() external override view returns (uint) {
        return totalNumberOfLockers;
    }

    /// @notice                             Give Bitcoin public key of locker
    /// @dev
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             Bitcoin public key of locker
    function getLockerLockingScript(
        address _lockerTargetAddress
    ) external override view nonZeroAddress(_lockerTargetAddress) returns (bytes memory) {
        return lockersMapping[_lockerTargetAddress].lockerLockingScript;
    }

    /// @notice                             Tells if a locker is active or not
    /// @dev                                An active locker is not in the process of being removed and has enough
    /// capacity to mint more tokens (minted - burnt << their collateral)
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             True if the locker is active and accepts mint requests
    function isActive(
        address _lockerTargetAddress
    ) external override view nonZeroAddress(_lockerTargetAddress) returns (bool) {
        return lockersMapping[_lockerTargetAddress].isActive;
    }

    /// @notice                             Get how much net this locker has minted
    /// @dev                                Net minted amount is total minted minus total burnt for the locker
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             The net minted of the locker
    function getLockerCapacity(
        address _lockerTargetAddress
    ) public override view nonZeroAddress(_lockerTargetAddress) returns (uint) {
        
        return ((
            LockersLib.lockerCollateralInTeleBTC(
                lockersMapping[_lockerTargetAddress],
                libConstants,
                libParams
            )*ONE_HUNDRED_PERCENT/collateralRatio) - 
            lockersMapping[_lockerTargetAddress].netMinted
        );
    }

    /// @notice                       Changes teleportDAO token in lockers 
    /// @dev                          Only current owner can call this
    /// @param _tdtTokenAddress       The new teleportDAO token address
    function setTeleportDAOToken(address _tdtTokenAddress) external override onlyOwner {
        _setTeleportDAOToken(_tdtTokenAddress);
    }


    /// @notice                       Changes percentage fee of locker
    /// @dev                          Only current owner can call this
    /// @param _lockerPercentageFee   The new locker percentage fee
    function setLockerPercentageFee(uint _lockerPercentageFee) external override onlyOwner {
        _setLockerPercentageFee(_lockerPercentageFee);
    }

    /// @notice                          Changes price with discount ratio
    /// @dev                             Only current owner can call this
    /// @param _priceWithDiscountRatio   The new price with discount ratioo
    function setPriceWithDiscountRatio(uint _priceWithDiscountRatio) external override onlyOwner {
        _setPriceWithDiscountRatio(_priceWithDiscountRatio);
    }

    /// @notice         Changes the required bond amount to become locker
    /// @dev            Only current owner can call this
    /// @param _minRequiredTDTLockedAmount   The new required bond amount
    function setMinRequiredTDTLockedAmount(uint _minRequiredTDTLockedAmount) external override onlyOwner {
        _setMinRequiredTDTLockedAmount(_minRequiredTDTLockedAmount);
    }

    /// @notice         Changes the required bond amount to become locker
    /// @dev            Only current owner can call this
    /// @param _minRequiredTNTLockedAmount   The new required bond amount
    function setMinRequiredTNTLockedAmount(uint _minRequiredTNTLockedAmount) external override onlyOwner {
        _setMinRequiredTNTLockedAmount(_minRequiredTNTLockedAmount);
    }

    /// @notice                 Changes the price oracle
    /// @dev                    Only current owner can call this
    /// @param _priceOracle     The new price oracle
    function setPriceOracle(address _priceOracle) external override nonZeroAddress(_priceOracle) onlyOwner {
        _setPriceOracle(_priceOracle);
    }

    /// @notice                Changes cc burn router contract
    /// @dev                   Only current owner can call this
    /// @param _ccBurnRouter   The new cc burn router contract address
    function setCCBurnRouter(address _ccBurnRouter) external override nonZeroAddress(_ccBurnRouter) onlyOwner {
        _setCCBurnRouter(_ccBurnRouter);
    }

    /// @notice                 Changes exchange router contract address and updates wrapped avax addresses
    /// @dev                    Only owner can call this
    /// @param _exchangeConnector  The new exchange router contract address
    function setExchangeConnector(address _exchangeConnector) external override nonZeroAddress(_exchangeConnector) onlyOwner {
        _setExchangeConnector(_exchangeConnector);
    }

    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external override nonZeroAddress(_teleBTC) onlyOwner {
        _setTeleBTC(_teleBTC);
    }

    /// @notice                     Changes collateral ratio
    /// @dev                        Only owner can call this
    /// @param _collateralRatio     The new collateral ratio
    function setCollateralRatio(uint _collateralRatio) external override onlyOwner {
        _setCollateralRatio(_collateralRatio);
    }

    /// @notice                     Changes liquidation ratio
    /// @dev                        Only owner can call this
    /// @param _liquidationRatio    The new liquidation ratio
    function setLiquidationRatio(uint _liquidationRatio) external override onlyOwner { 
        _setLiquidationRatio(_liquidationRatio);
    }

    /// @notice                     Internal setter for teleportDAO token of lockers
    /// @param _tdtTokenAddress     The new teleportDAO token address
    function _setTeleportDAOToken(address _tdtTokenAddress) private nonZeroAddress(_tdtTokenAddress) {
        emit NewTeleportDAOToken(TeleportDAOToken, _tdtTokenAddress);
        TeleportDAOToken = _tdtTokenAddress;
        libParams.teleportDAOToken = TeleportDAOToken;
    }

    /// @notice                       Internal setter for percentage fee of locker
    /// @param _lockerPercentageFee   The new locker percentage fee
    function _setLockerPercentageFee(uint _lockerPercentageFee) private {
        require(_lockerPercentageFee <= MAX_LOCKER_FEE, "Lockers: invalid locker fee");
        emit NewLockerPercentageFee(lockerPercentageFee, _lockerPercentageFee);
        lockerPercentageFee = _lockerPercentageFee;
        libParams.lockerPercentageFee = lockerPercentageFee;
    }

    function _setPriceWithDiscountRatio(uint _priceWithDiscountRatio) private {
        require(
            _priceWithDiscountRatio <= ONE_HUNDRED_PERCENT,
            "Lockers: less than 100%"
        );
        emit NewPriceWithDiscountRatio(priceWithDiscountRatio, priceWithDiscountRatio);
        
        priceWithDiscountRatio= _priceWithDiscountRatio;
        libParams.priceWithDiscountRatio = priceWithDiscountRatio;
    }

    /// @notice         Internal setter for the required bond amount to become locker
    /// @param _minRequiredTDTLockedAmount   The new required bond amount
    function _setMinRequiredTDTLockedAmount(uint _minRequiredTDTLockedAmount) private {
        emit NewMinRequiredTDTLockedAmount(minRequiredTDTLockedAmount, _minRequiredTDTLockedAmount);
        minRequiredTDTLockedAmount = _minRequiredTDTLockedAmount;
        libParams.minRequiredTDTLockedAmount = minRequiredTDTLockedAmount;
    }

    /// @notice         Internal setter for the required bond amount to become locker
    /// @param _minRequiredTNTLockedAmount   The new required bond amount
    function _setMinRequiredTNTLockedAmount(uint _minRequiredTNTLockedAmount) private {
        emit NewMinRequiredTNTLockedAmount(minRequiredTNTLockedAmount, _minRequiredTNTLockedAmount);
        minRequiredTNTLockedAmount = _minRequiredTNTLockedAmount;
        libParams.minRequiredTNTLockedAmount = minRequiredTNTLockedAmount;
    }

    /// @notice                 Internal setter for the price oracle
    /// @param _priceOracle     The new price oracle
    function _setPriceOracle(address _priceOracle) private nonZeroAddress(_priceOracle) {
        emit NewPriceOracle(priceOracle, _priceOracle);
        priceOracle = _priceOracle;
        libParams.priceOracle = priceOracle;
    }

    /// @notice                Internal setter for cc burn router contract
    /// @param _ccBurnRouter   The new cc burn router contract address
    function _setCCBurnRouter(address _ccBurnRouter) private nonZeroAddress(_ccBurnRouter) {
        emit NewCCBurnRouter(ccBurnRouter, _ccBurnRouter);
        // TODO: what will happen in subgraph for first (zero address)? (remove)
        emit BurnerRemoved(ccBurnRouter);
        burners[ccBurnRouter] = false;
        ccBurnRouter = _ccBurnRouter;
        libParams.ccBurnRouter = ccBurnRouter;
        emit BurnerAdded(ccBurnRouter);
        burners[ccBurnRouter] = true;
    }

    /// @notice                 Internal setter for exchange router contract address and updates wrapped avax addresses
    /// @param _exchangeConnector  The new exchange router contract address
    function _setExchangeConnector(address _exchangeConnector) private nonZeroAddress(_exchangeConnector) {
        emit NewExchangeConnector(exchangeConnector, _exchangeConnector);
        exchangeConnector = _exchangeConnector;
        libParams.exchangeConnector = exchangeConnector;
    }

    /// @notice                 Internal setter for wrapped token contract address
    /// @param _teleBTC         The new wrapped token contract address
    function _setTeleBTC(address _teleBTC) private nonZeroAddress(_teleBTC) {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
        libParams.teleBTC = teleBTC;
    }

    /// @notice                     Internal setter for collateral ratio
    /// @param _collateralRatio     The new collateral ratio
    function _setCollateralRatio(uint _collateralRatio) private {
        require(_collateralRatio >= liquidationRatio, "Lockers: CR must be greater than LR");
        emit NewCollateralRatio(collateralRatio, _collateralRatio);
        collateralRatio = _collateralRatio;
        libParams.collateralRatio = collateralRatio;
    }

    /// @notice                     Internal setter for liquidation ratio
    /// @param _liquidationRatio    The new liquidation ratio
    function _setLiquidationRatio(uint _liquidationRatio) private {
        require(
            _liquidationRatio >= ONE_HUNDRED_PERCENT,
            "Lockers: problem in CR and LR"
        );
        emit NewLiquidationRatio(liquidationRatio, _liquidationRatio);
        liquidationRatio = _liquidationRatio;
        libParams.liquidationRatio = liquidationRatio;
    }

    /// @notice                                 Adds user to candidates list
    /// @dev                                    Users mint TeleBTC by sending BTC to locker's locking script
    ///                                         In case of liqudation of locker's bond, the burn TeleBTC is sent to
    ///                                         locker's rescue script
    ///                                         A user should lock enough TDT and TNT to become candidate
    /// @param _candidateLockingScript          Locking script of the candidate
    /// @param _lockedTDTAmount                 Bond amount of locker in TDT
    /// @param _lockedNativeTokenAmount         Bond amount of locker in native token of the target chain
    /// @param _lockerRescueType                Type of locker's rescue script (e.g. P2SH)
    /// @param _lockerRescueScript              Rescue script of the locker
    /// @return                                 True if candidate is added successfully
    function requestToBecomeLocker(
        bytes calldata _candidateLockingScript,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount,
        ScriptTypes _lockerRescueType,
        bytes calldata _lockerRescueScript
    ) external override payable nonReentrant returns (bool) {

        LockersLib.requestToBecomeLockerValidation(
                lockersMapping,
                libConstants,
                libParams,
                lockerTargetAddress[_candidateLockingScript],
                _lockedTDTAmount,
                _lockedNativeTokenAmount
            );

        
        IERC20(libParams.teleportDAOToken).safeTransferFrom(msg.sender, address(this), _lockedTDTAmount);

        LockersLib.requestToBecomeLocker(
                lockersMapping,
                _candidateLockingScript,
                _lockedTDTAmount,
                _lockedNativeTokenAmount,
                _lockerRescueType,
                _lockerRescueScript
            );

        totalNumberOfCandidates = totalNumberOfCandidates + 1;

        emit RequestAddLocker(
            _msgSender(),
            _candidateLockingScript,
            _lockedTDTAmount,
            _lockedNativeTokenAmount
        );

        return true;
    }

    /// @notice                       Removes a candidate from candidates list
    /// @dev                          A user who is still a candidate can revoke his/her request
    /// @return                       True if candidate is removed successfully
    function revokeRequest() external override nonReentrant returns (bool) {

        require(
            lockersMapping[_msgSender()].isCandidate,
            "Lockers: no req"
        );

        // Loads locker's information
        DataTypes.locker memory lockerRequest = lockersMapping[_msgSender()];

        // Removes candidate from lockersMapping
        delete lockersMapping[_msgSender()];
        totalNumberOfCandidates = totalNumberOfCandidates -1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).safeTransfer(_msgSender(), lockerRequest.TDTLockedAmount);
        Address.sendValue(payable(_msgSender()), lockerRequest.nativeTokenLockedAmount);

        emit RevokeAddLockerRequest(
            _msgSender(),
            lockersMapping[_msgSender()].lockerLockingScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount
        );

        return true;
    }

    /// @notice                               Approves a candidate request to become locker
    /// @dev                                  Only owner can call this
    ///                                       When a candidate becomes locker, isCandidate is set to false
    /// @param _lockerTargetAddress           Locker's target chain address
    /// @return                               True if candidate is added successfully
    function addLocker(
        address _lockerTargetAddress
    ) external override nonZeroAddress(_lockerTargetAddress) nonReentrant onlyOwner returns (bool) {

        require(
            lockersMapping[_lockerTargetAddress].isCandidate,
            "Lockers: no request"
        );

        // Updates locker's status
        lockersMapping[_lockerTargetAddress].isCandidate = false;
        lockersMapping[_lockerTargetAddress].isLocker = true;
        lockersMapping[_lockerTargetAddress].isActive = true;

        // Updates number of candidates and lockers
        totalNumberOfCandidates = totalNumberOfCandidates -1;
        totalNumberOfLockers = totalNumberOfLockers + 1;

        lockerTargetAddress[lockersMapping[_lockerTargetAddress].lockerLockingScript] = _lockerTargetAddress;

        emit LockerAdded(
            _lockerTargetAddress,
            lockersMapping[_lockerTargetAddress].lockerLockingScript,
            lockersMapping[_lockerTargetAddress].TDTLockedAmount,
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
            block.timestamp
        );
        return true;
    }

    /// @notice                Requests to remove a locker from lockers list
    /// @dev                   Deactivates the status of the locker so that no
    ///                        one is allowed to send mint requests to this locker.
    ///                        It gives time to the locker to burn the required amount
    ///                        of teleBTC to make itself eligible to be removed.
    ///                        Sets isActive of locker to false
    /// @return                True if deactivated successfully
    function requestToRemoveLocker() external override nonReentrant returns (bool) {
        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: input address is not a valid locker"
        );

        lockersMapping[_msgSender()].isActive = false;

        lockerLeavingRequests[_msgSender()] = true;

        emit RequestRemoveLocker(
            _msgSender(),
            lockersMapping[_msgSender()].lockerLockingScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount,
            lockersMapping[_msgSender()].netMinted
        // TODO: adding more fields to this event
        );

        return true;
    }

    /// @notice                       Removes a locker from lockers list
    /// @dev                          Only owner can call this function
    ///                               Removing conditions should be satisfied
    /// @param _lockerTargetAddress   Target address of locker to be removed
    /// @return                       True if locker is removed successfully
    function ownerRemoveLocker(
        address _lockerTargetAddress
    ) external override nonZeroAddress(_lockerTargetAddress) nonReentrant onlyOwner returns (bool) {
        _removeLocker(_lockerTargetAddress);
        return true;
    }

    /// @notice                       Removes a locker from lockers list
    /// @dev                          Only locker can call this function
    ///                               Removing conditions should be satisfied
    /// @return                       True if locker is removed successfully
    function selfRemoveLocker() external override nonReentrant whenNotPaused returns (bool) {
        _removeLocker(_msgSender());
        return true;
    }

    /// @notice                           Slashes lockers for not executing a cc burn req
    /// @dev                              Only cc burn router can call this
    ///                                   Locker is slashed since doesn't provide burn proof
    ///                                   before a cc burn request deadline.
    ///                                   User who made the cc burn request will receive the slashed bond
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _rewardAmount              Amount of TeleBTC that slasher receives
    /// @param _rewardAmount              Address of slasher who receives reward
    /// @param _amount                    Amount of TeleBTC that is slashed from lockers
    /// @param _recipient                 Address of user who receives the slashed amount
    /// @return                           True if the locker is slashed successfully
    function slashIdleLocker(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount,
        address _recipient
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(
            _msgSender() == ccBurnRouter,
            "Lockers: message sender is not ccBurn"
        );

        uint equivalentNativeToken = LockersLib.slashIdleLocker(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            _rewardAmount,
            _rewardRecipient,
            _amount,
            _recipient
        );

        // Transfers TNT to user
        payable(_recipient).transfer(equivalentNativeToken*_amount/(_amount + _rewardAmount));
        // Transfers TNT to slasher
        uint rewardAmountInNativeToken = equivalentNativeToken - (equivalentNativeToken*_amount/(_amount + _rewardAmount));
        payable(_rewardRecipient).transfer(rewardAmountInNativeToken);

        emit LockerSlashed(
            _lockerTargetAddress,
            rewardAmountInNativeToken,
            _rewardRecipient,
            _amount,
            _recipient,
            equivalentNativeToken,
            block.timestamp,
            true
        );

        return true;
    }


    /// @notice                           Slashes lockers for moving BTC without a good reason
    /// @dev                              Only cc burn router can call this
    ///                                   Locker is slashed because he/she moved BTC from 
    ///                                   locker's Bitcoin address without any corresponding burn req
    ///                                   The slashed bond will be sold with discount
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _rewardAmount              Value of slashed reward (in TeleBTC)
    /// @param _rewardRecipient           Address of slasher who receives reward
    /// @param _amount                    Value of slashed collateral (in TeleBTC)
    /// @return                           True if the locker is slashed successfully
    function slashTheifLocker(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(
            _msgSender() == ccBurnRouter,
            "Lockers: message sender is not ccBurn"
        );

        (uint rewardInNativeToken, uint neededNativeTokenForSlash) = LockersLib.slashTheifLocker(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            _rewardAmount,
            _rewardRecipient,
            _amount
        );

        payable(_rewardRecipient).transfer(rewardInNativeToken);

        emit LockerSlashed(
            _lockerTargetAddress,
            rewardInNativeToken,
            _rewardRecipient,
            _amount,
            address(this),
            neededNativeTokenForSlash + rewardInNativeToken,
            block.timestamp,
            false
        );

        return true;
    }


    /// @notice                           Liquidates the locker whose collateral is unhealthy
    /// @dev                              Anyone can liquidate a locker which its health factor
    ///                                   is less than 10000 (100%) by providing a sufficient amount of teleBTC
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _collateralAmount          Amount of collateral (TNT) that someone is intend to buy with discount
    /// @return                           True is liquidation was successful
    function liquidateLocker(
        address _lockerTargetAddress,
        uint _collateralAmount
    ) external override nonZeroAddress(_lockerTargetAddress) nonZeroValue(_collateralAmount)
    nonReentrant whenNotPaused returns (bool) {

        uint neededTeleBTC = LockersLib.liquidateLocker(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            _collateralAmount
        );


        DataTypes.locker memory theLiquidatingLocker = lockersMapping[_lockerTargetAddress];


        // Burns TeleBTC for locker rescue script
        // note: user should give allowance for TeleBTC to cc burn router
        ICCBurnRouter(ccBurnRouter).ccBurn(
            neededTeleBTC,
            theLiquidatingLocker.lockerRescueScript,
            theLiquidatingLocker.lockerRescueType,
            theLiquidatingLocker.lockerLockingScript
        );

        // Updates net minted and TNT bond of locker
        lockersMapping[_lockerTargetAddress].netMinted = lockersMapping[_lockerTargetAddress].netMinted - neededTeleBTC;
        lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount = lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount - _collateralAmount;

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
    /// @param _collateralAmount          Amount of collateral (TNT) that someone is intend to buy with discount
    /// @return                           True is buying was successful
    function buySlashedCollateralOfLocker(
        address _lockerTargetAddress,
        uint _collateralAmount
    ) external nonZeroAddress(_lockerTargetAddress) nonZeroValue(_collateralAmount)
        nonReentrant whenNotPaused override returns (bool) {

        uint neededTeleBTC = LockersLib.buySlashedCollateralOfLocker(
            lockersMapping[_lockerTargetAddress],
            libConstants,
            libParams,
            _collateralAmount
        );

        // Burns user's TeleBTC
        ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), neededTeleBTC);
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
        uint _addingNativeTokenAmount
    ) external override payable nonReentrant returns (bool) {

        require(
            msg.value == _addingNativeTokenAmount,
            "Lockers: msg value"
        );

        LockersLib.addToCollateral(
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
    function removeCollateral(
        uint _removingNativeTokenAmount
    ) external override payable nonReentrant returns (bool) {

        uint priceOfOnUnitOfCollateral = LockersLib.priceOfOneUnitOfCollateralInBTC(
            libConstants,
            libParams
        );

        LockersLib.removeFromCollateral(
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

    /**
     * @dev Returns the price of one native token (1*10^18) in teleBTC
     * @return uint
     */
    function priceOfOneUnitOfCollateralInBTC() public override view returns (uint) {

        return LockersLib.priceOfOneUnitOfCollateralInBTC(
            libConstants,
            libParams
        );

    }

    /// @notice                       Mint teleBTC for an account
    /// @dev                          Mint teleBTC for an account and got the locker fee as well
    /// @param _lockerLockingScript   Locking script of a locker
    /// @param _receiver              Address of the receiver of the minted teleBTCs
    /// @param _amount                Amount of the teleBTC which is minted, including the locker's fee
    /// @return uint                  The amount of teleBTC minted for the receiver
    function mint(
        bytes calldata _lockerLockingScript,
        address _receiver,
        uint _amount
    ) external override nonZeroAddress(_receiver)
    nonZeroValue(_amount) nonReentrant whenNotPaused onlyMinter returns (uint) {

        address _lockerTargetAddress = lockerTargetAddress[_lockerLockingScript];

        uint theLockerCapacity = getLockerCapacity(_lockerTargetAddress);

        require(
            theLockerCapacity >= _amount,
            "Lockers: insufficient capacity"
        );

        lockersMapping[_lockerTargetAddress].netMinted =
        lockersMapping[_lockerTargetAddress].netMinted + _amount;

        // Mints locker fee
        uint lockerFee = _amount*lockerPercentageFee/MAX_LOCKER_FEE;
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
    /// @return uint                  The amount of teleBTC burned the
    function burn(
        bytes calldata _lockerLockingScript,
        uint _amount
    ) external override nonZeroValue(_amount)
    nonReentrant whenNotPaused onlyBurner returns (uint) {

        address _lockerTargetAddress = lockerTargetAddress[_lockerLockingScript];

        // Transfers teleBTC from user
        ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), _amount);

        uint lockerFee = _amount*lockerPercentageFee/MAX_LOCKER_FEE;
        uint remainedAmount = _amount - lockerFee;
        uint netMinted = lockersMapping[_lockerTargetAddress].netMinted;

        require(
            netMinted >= remainedAmount,
            "Lockers: insufficient funds"
        );

        lockersMapping[_lockerTargetAddress].netMinted = netMinted - remainedAmount;

        // Burns teleBTC and sends rest of it to locker
        ITeleBTC(teleBTC).burn(remainedAmount);
        ITeleBTC(teleBTC).transfer(_lockerTargetAddress, lockerFee);

        emit BurnByLocker(
            _lockerTargetAddress,
            _amount,
            lockerFee,
            block.timestamp
        );

        return remainedAmount;
    }

    /**
     * @dev Check if an account is minter.
     * @return bool
     */
    function _isMinter(address account) private view nonZeroAddress(account) returns (bool) {
        return minters[account];
    }

    /**
     * @dev Check if an account is burner.
     * @return bool
     */
    function _isBurner(address account) private view nonZeroAddress(account) returns (bool) {
        return burners[account];
    }


    /// @notice                       Removes a locker from lockers list
    /// @dev                          Checks that net minted TeleBTC of locker is zero
    ///                               Sends back available bond of locker (in TDT and TNT)
    /// @param _lockerTargetAddress   Target address of locker to be removed
    function _removeLocker(address _lockerTargetAddress) private {

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: no locker"
        );

        require(
            lockerLeavingRequests[_lockerTargetAddress],
            "Lockers: no remove req"
        );

        require(
            lockersMapping[_lockerTargetAddress].netMinted == 0,
            "Lockers: 0 net minted"
        );

        DataTypes.locker memory _removingLokcer = lockersMapping[_lockerTargetAddress];

        // Removes locker from lockersMapping
        delete lockersMapping[_lockerTargetAddress];
        totalNumberOfLockers = totalNumberOfLockers - 1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).safeTransfer(_lockerTargetAddress, _removingLokcer.TDTLockedAmount);
        Address.sendValue(payable(_lockerTargetAddress), _removingLokcer.nativeTokenLockedAmount);

        emit LockerRemoved(
            _lockerTargetAddress,
            _removingLokcer.lockerLockingScript,
            _removingLokcer.TDTLockedAmount,
            _removingLokcer.nativeTokenLockedAmount
        );

    }
}
