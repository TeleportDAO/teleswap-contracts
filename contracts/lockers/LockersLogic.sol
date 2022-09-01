// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../oracle/interfaces/IPriceOracle.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/IERC20.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../routers/interfaces/ICCBurnRouter.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interfaces/ILockers.sol";
import "hardhat/console.sol";

contract LockersLogic is ILockers, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    // Structures

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

    // Constants
    uint public constant ONE_HUNDRED_PERCENT = 10000;
    uint public constant HEALTH_FACTOR = 10000;
    uint public constant UPPER_HEALTH_FACTOR = 12000;
    uint public constant MAX_LOCKER_FEE = 10000;
    uint public constant NATIVE_TOKEN_DECIMAL = 18;
    address public constant NATIVE_TOKEN = address(1);

    // Public variables
    address public override TeleportDAOToken;
    address public override teleBTC;
    address public override ccBurnRouter;
    address public override exchangeConnector;
    address public override priceOracle;

    uint public override minRequiredTDTLockedAmount;
    uint public override minRequiredTNTLockedAmount;
    uint public override lockerPercentageFee;
    uint public override collateralRatio;
    uint public override liquidationRatio;
    uint public override priceWithDiscountRatio;
    uint public override totalNumberOfCandidates;
    uint public override totalNumberOfLockers;

    mapping(address => locker) public lockersMapping; // locker's target address -> locker structure
    mapping(address => bool) public lockerLeavingRequests;
    mapping(address => bool) public lockerLeavingAcceptance;
    mapping(bytes => address) public lockerTargetAddress; // locker's locking script -> locker's target address
    mapping(address => bool) minters;
    mapping(address => bool) burners;

    function initialize(
        address _TeleportDAOToken,
        address _exchangeConnector,
        address _priceOracle,
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

        require(
            _TeleportDAOToken != address(0) && _exchangeConnector != address(0) && _priceOracle != address(0),
            "Lockers: address is zero"
        );

        require(
            _minRequiredTDTLockedAmount != 0 || _minRequiredTNTLockedAmount != 0,
            "Lockers: amount is zero"
        );

        require(
            _collateralRatio >= _liquidationRatio && _liquidationRatio >= ONE_HUNDRED_PERCENT,
            "Lockers: problem in CR and LR"
        );

        require(
            _priceWithDiscountRatio <= ONE_HUNDRED_PERCENT,
            "Lockers: price discount ratio must be less than 100%"
        );

        TeleportDAOToken = _TeleportDAOToken;
        exchangeConnector = _exchangeConnector;
        priceOracle = _priceOracle;
        minRequiredTDTLockedAmount = _minRequiredTDTLockedAmount;
        minRequiredTNTLockedAmount = _minRequiredTNTLockedAmount;
        collateralRatio = _collateralRatio;
        liquidationRatio = _liquidationRatio;
        lockerPercentageFee = _lockerPercentageFee;
        priceWithDiscountRatio= _priceWithDiscountRatio;
    }

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
    }

    /**
     * @dev Remove an account's access to mint.
     */
    function removeMinter(address _account) external override nonZeroAddress(_account) onlyOwner {
        require(_isMinter(_account), "Lockers: account does not have role");
        minters[_account] = false;
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
    }

    /**
     * @dev Remove an account's access to burn.
     */
    function removeBurner(address _account) external override nonZeroAddress(_account) onlyOwner {
        require(_isBurner(_account), "Lockers: account does not have role");
        burners[_account] = false;
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
        return (_lockerCollateralInTeleBTC(_lockerTargetAddress)*ONE_HUNDRED_PERCENT/collateralRatio) - lockersMapping[_lockerTargetAddress].netMinted;
    }

    /// @notice                       Changes percentage fee of locker
    /// @dev                          Only current owner can call this
    /// @param _lockerPercentageFee   The new locker percentage fee
    function setLockerPercentageFee(uint _lockerPercentageFee) external override onlyOwner {
        require(_lockerPercentageFee <= MAX_LOCKER_FEE, "Lockers: invalid locker fee");
        lockerPercentageFee = _lockerPercentageFee;
    }

    /// @notice         Changes the required bond amount to become locker
    /// @dev            Only current owner can call this
    /// @param _minRequiredTDTLockedAmount   The new required bond amount
    function setMinRequiredTDTLockedAmount(uint _minRequiredTDTLockedAmount) external override onlyOwner {
        minRequiredTDTLockedAmount = _minRequiredTDTLockedAmount;
    }

    /// @notice         Changes the required bond amount to become locker
    /// @dev            Only current owner can call this
    /// @param _minRequiredTNTLockedAmount   The new required bond amount
    function setMinRequiredTNTLockedAmount(uint _minRequiredTNTLockedAmount) external override onlyOwner {
        minRequiredTNTLockedAmount = _minRequiredTNTLockedAmount;
    }

    /// @notice                 Changes the price oracle
    /// @dev                    Only current owner can call this
    /// @param _priceOracle     The new price oracle
    function setPriceOracle(address _priceOracle) external override nonZeroAddress(_priceOracle) onlyOwner {
        priceOracle = _priceOracle;
    }

    /// @notice                Changes cc burn router contract
    /// @dev                   Only current owner can call this
    /// @param _ccBurnRouter   The new cc burn router contract address
    function setCCBurnRouter(address _ccBurnRouter) external override nonZeroAddress(_ccBurnRouter) onlyOwner {
        ccBurnRouter = _ccBurnRouter;
    }

    /// @notice                 Changes exchange router contract address and updates wrapped avax addresses
    /// @dev                    Only owner can call this
    /// @param _exchangeConnector  The new exchange router contract address
    function setExchangeConnector(address _exchangeConnector) external override nonZeroAddress(_exchangeConnector) onlyOwner {
        exchangeConnector = _exchangeConnector;
    }

    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external override nonZeroAddress(_teleBTC) onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                     Changes collateral ratio
    /// @dev                        Only owner can call this
    /// @param _collateralRatio     The new collateral ratio
    function setCollateralRatio(uint _collateralRatio) external override onlyOwner {
        require(_collateralRatio >= liquidationRatio, "Lockers: CR must be greater than LR");
        collateralRatio = _collateralRatio;
    }

    /// @notice                     Changes liquidation ratio
    /// @dev                        Only owner can call this
    /// @param _liquidationRatio    The new liquidation ratio
    function setLiquidationRatio(uint _liquidationRatio) external override onlyOwner {
        liquidationRatio = _liquidationRatio;
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

        require(
            !lockersMapping[_msgSender()].isCandidate,
            "Lockers: user is already a candidate"
        );

        require(
            !lockersMapping[_msgSender()].isLocker,
            "Lockers: user is already a locker"
        );

        require(
            _lockedTDTAmount >= minRequiredTDTLockedAmount,
            "Lockers: low locking TDT amount"
        );

        require(
            _lockedNativeTokenAmount >= minRequiredTNTLockedAmount && msg.value == _lockedNativeTokenAmount,
            "Lockers: low locking TNT amount"
        );

        require(
            lockerTargetAddress[_candidateLockingScript] == address(0),
            "Lockers: locking script is used before"
        );

        require(IERC20(TeleportDAOToken).transferFrom(_msgSender(), address(this), _lockedTDTAmount));
        locker memory locker_;
        locker_.lockerLockingScript = _candidateLockingScript;
        locker_.TDTLockedAmount = _lockedTDTAmount;
        locker_.nativeTokenLockedAmount = _lockedNativeTokenAmount;
        locker_.isCandidate = true;
        locker_.lockerRescueType = _lockerRescueType;
        locker_.lockerRescueScript = _lockerRescueScript;

        lockersMapping[_msgSender()] = locker_;

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
            "Lockers: request doesn't exist or already accepted"
        );

        // Loads locker's information
        locker memory lockerRequest = lockersMapping[_msgSender()];

        // Removes candidate from lockersMapping
        delete lockersMapping[_msgSender()];
        totalNumberOfCandidates = totalNumberOfCandidates -1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).transfer(_msgSender(), lockerRequest.TDTLockedAmount);
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
            "Lockers: no request with this address"
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
            "Lockers: msg sender is not locker"
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

    /// @notice                           Slashes lockers
    /// @dev                              Only cc burn router can call this
    ///                                   Locker is slashed in two cases:
    ///                                   1. Not providing a burn proof before a cc burn request deadline
    ///                                   2. Moving BTC from locker's address without a good reason
    ///                                   In the first scenario, user who made the cc burn request will receive the slashed bond
    ///                                   In the second scenario, the slashed bond will be held by the lockers contract
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _rewardAmount              Amount of TeleBTC that slasher receives
    /// @param _rewardAmount              Address of slasher who receives reward
    /// @param _amount                    Amount of TeleBTC that is slashed from lockers
    /// @param _recipient                 Address of user who receives the slashed amount
    /// @return                           True if the locker is slashed successfully
    function slashLockerForCCBurn(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount,
        address _recipient
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(
            _msgSender() == ccBurnRouter,
            "Lockers: caller can't slash"
        );

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        uint equivalentNativeToken = IPriceOracle(priceOracle).equivalentOutputAmount(
            _rewardAmount + _amount, // Total amount of TeleBTC that is slashed
            IERC20(teleBTC).decimals(), // Decimal of teleBTC
            NATIVE_TOKEN_DECIMAL, // Decimal of TNT
            teleBTC, // Input token
            NATIVE_TOKEN // Output token
        );

        require(
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount >= equivalentNativeToken,
            "Lockers: insufficient native token collateral"
        );

        // Updates locker's bond (in TNT)
        lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount
        = lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount - equivalentNativeToken;

        // Transfers slashed collateral to user
        if (_recipient != address(this)) {
            // Transfers TNT to user
            payable(_recipient).transfer(equivalentNativeToken*_amount/(_amount + _rewardAmount));
            // Transfers TNT to slasher
            payable(_rewardRecipient).transfer(equivalentNativeToken*_rewardAmount/(_amount + _rewardAmount));
        } else {
            // Slasher can't be address(this)
            // Transfers TNT to slasher
            payable(_rewardRecipient).transfer(equivalentNativeToken*_rewardAmount/(_amount + _rewardAmount));
        }

        // TODO: adding a cc burn for the locker itself
        // Burns TeleBTC for locker rescue script
        // note: user should give allowance for TeleBTC to cc burn router
        // ICCBurnRouter(ccBurnRouter).ccBurn(
        //     _amount,
        //     lockersMapping[_lockerTargetAddress].lockerRescueScript,
        //     lockersMapping[_lockerTargetAddress].lockerRescueType,
        //     lockersMapping[_lockerTargetAddress].lockerLockingScript
        // );

        emit LockerSlashed(
            _lockerTargetAddress,
            _rewardAmount,
            _rewardRecipient,
            _amount,
            _recipient,
            equivalentNativeToken,
            block.timestamp,
            true
        );

        return true;
    }


    /// @notice                           Slashes lockers
    /// @dev                              Only cc burn router can call this
    ///                                   Locker is slashed in two cases:
    ///                                   1. Not providing a burn proof before a cc burn request deadline
    ///                                   2. Moving BTC from locker's address without a good reason
    ///                                   In the first scenario, user who made the cc burn request will receive the slashed bond
    ///                                   In the second scenario, the slashed bond will be held by the lockers contract
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _rewardAmount              Amount of TeleBTC that slasher receives
    /// @param _rewardAmount              Address of slasher who receives reward
    /// @param _amount                    Amount of TeleBTC that is slashed from lockers
    /// @return                           True if the locker is slashed successfully
    function slashLockerForDispute(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount
    ) external override nonReentrant whenNotPaused returns (bool) {
        require(
            _msgSender() == ccBurnRouter,
            "Lockers: caller can't slash"
        );

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        uint equivalentNativeToken = IPriceOracle(priceOracle).equivalentOutputAmount(
            _amount, // Total amount of TeleBTC that is slashed
            IERC20(teleBTC).decimals(), // Decimal of teleBTC
            NATIVE_TOKEN_DECIMAL, // Decimal of TNT
            teleBTC, // Input token
            NATIVE_TOKEN // Output token
        );

        uint rewardInNativeToken = equivalentNativeToken*_rewardAmount/_amount;
        uint neededNativeTokenForSlash = equivalentNativeToken*liquidationRatio/ONE_HUNDRED_PERCENT;

        require(
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount >= (rewardInNativeToken + neededNativeTokenForSlash),
            "Lockers: insufficient native token collateral"
        );

        // Updates locker's bond (in TNT)
        lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount
        = lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount - (rewardInNativeToken + neededNativeTokenForSlash);

        lockersMapping[_lockerTargetAddress].netMinted
        = lockersMapping[_lockerTargetAddress].netMinted - _amount;

        lockersMapping[_lockerTargetAddress].slashingTeleBTCAmount
        = lockersMapping[_lockerTargetAddress].slashingTeleBTCAmount + _amount;

        lockersMapping[_lockerTargetAddress].reservedNativeTokenForSlash
        = lockersMapping[_lockerTargetAddress].reservedNativeTokenForSlash + neededNativeTokenForSlash;


        payable(_rewardRecipient).transfer(rewardInNativeToken);

        emit LockerSlashed(
            _lockerTargetAddress,
            _rewardAmount,
            _rewardRecipient,
            _amount,
            address(this),
            equivalentNativeToken,
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

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        locker memory theLiquidatingLocker = lockersMapping[_lockerTargetAddress];
        uint priceOfCollateral = priceOfOneUnitOfCollateralInBTC();

        // Checks that the collateral has become unhealthy
        require(
            calculateHealthFactor(_lockerTargetAddress, priceOfCollateral) < HEALTH_FACTOR,
            "Lockers: locker's collateral is healthy"
        );

        uint _maxBuyableCollateral = maxBuyableCollateral(_lockerTargetAddress, priceOfCollateral);

        if (_maxBuyableCollateral > theLiquidatingLocker.nativeTokenLockedAmount) {
            _maxBuyableCollateral = theLiquidatingLocker.nativeTokenLockedAmount;
        }

        require(
            _collateralAmount <= _maxBuyableCollateral,
            "Lockers: more than maximum buyable"
        );

        // Needed amount of TeleBTC to buy collateralAmount
        uint neededTeleBTC = neededTeleBTCToBuyCollateral(_collateralAmount, priceOfCollateral);
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


    /// @notice                           Liquidates the locker whose collateral is unhealthy
    /// @dev                              Anyone can liquidate a locker which its health factor
    ///                                   is less than 10000 (100%) by providing a sufficient amount of teleBTC
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _slashingAmount          Amount of collateral (TNT) that someone is intend to buy with discount
    /// @return                           True is liquidation was successful
    function buySlashingAmountOfLocker(
        address _lockerTargetAddress,
        uint _slashingAmount
    ) external nonZeroAddress(_lockerTargetAddress) nonZeroValue(_slashingAmount)
    nonReentrant whenNotPaused returns (bool) {

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        locker memory theSlashingLocker = lockersMapping[_lockerTargetAddress];

        // Checks that the collateral has become unhealthy
        require(
            theSlashingLocker.slashingTeleBTCAmount > 0,
            "Lockers: locker cant be slashed"
        );

        uint priceOfCollateral = priceOfOneUnitOfCollateralInBTC();

        require(
            _slashingAmount <= theSlashingLocker.reservedNativeTokenForSlash,
            "Lockers: more than maximum buyable"
        );

        // Needed amount of TeleBTC to buy collateralAmount
        uint neededTeleBTC = neededTeleBTCToBuyCollateral(_slashingAmount, priceOfCollateral);


        // Updates net minted and TNT bond of locker
        lockersMapping[_lockerTargetAddress].slashingTeleBTCAmount =
        lockersMapping[_lockerTargetAddress].slashingTeleBTCAmount - neededTeleBTC;

        lockersMapping[_lockerTargetAddress].reservedNativeTokenForSlash =
        lockersMapping[_lockerTargetAddress].reservedNativeTokenForSlash - _slashingAmount;

        Address.sendValue(payable(_msgSender()), _slashingAmount);

        ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), neededTeleBTC);
        ITeleBTC(teleBTC).burn(neededTeleBTC);

        emit LockerSlashingAmountSold(
            _lockerTargetAddress,
            _msgSender(),
            _slashingAmount,
            neededTeleBTC,
            block.timestamp
        );

        return true;
    }


    function neededTeleBTCToBuyCollateral(uint _collateralAmount, uint _priceOfCollateral) public view returns (uint){
        return (_collateralAmount * _priceOfCollateral * priceWithDiscountRatio)/
        (ONE_HUNDRED_PERCENT*(10 ** NATIVE_TOKEN_DECIMAL));
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
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: account is not a locker"
        );

        require(
            msg.value == _addingNativeTokenAmount,
            "Lockers: incompatible msg value"
        );

        lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount =
        lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount + _addingNativeTokenAmount;

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

        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: account is not a locker"
        );

        locker memory theLocker = lockersMapping[_msgSender()];

        uint priceOfOnUnitOfCollateral = priceOfOneUnitOfCollateralInBTC();

        // lockerCapacity = valueOfNativeTokenLockedAmountInBTC - netMinted

        uint lockerCapacity = (theLocker.nativeTokenLockedAmount * priceOfOnUnitOfCollateral * ONE_HUNDRED_PERCENT)/
        (collateralRatio * (10 ** NATIVE_TOKEN_DECIMAL)) - theLocker.netMinted;

        uint maxRemovableCollateral = (lockerCapacity * (10 ** NATIVE_TOKEN_DECIMAL))/priceOfOnUnitOfCollateral;

        require(
            _removingNativeTokenAmount <= maxRemovableCollateral,
            "Lockers: more than max removable collateral"
        );

        lockersMapping[_msgSender()].nativeTokenLockedAmount =
        lockersMapping[_msgSender()].nativeTokenLockedAmount - _removingNativeTokenAmount;

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

        return IPriceOracle(priceOracle).equivalentOutputAmount(
            (10**NATIVE_TOKEN_DECIMAL), // 1 Ether is 10^18 wei
            NATIVE_TOKEN_DECIMAL,
            IERC20(teleBTC).decimals(),
            NATIVE_TOKEN,
            teleBTC
        );

    }

    /**
     * @dev                                 Calculate the health factor of a specific locker
     *                                      Health factor = (value of collateral)/(value of minted TeleBTC * liquidation ratio)
     * @param _lockerTargetAddress          The locker's target address
     * @param _priceOfOneUnitOfCollateral   The price of one native token (1*10^18) in teleBTC
     * @return uint
     */
    function calculateHealthFactor(
        address _lockerTargetAddress,
        uint _priceOfOneUnitOfCollateral
    ) public override view nonZeroAddress(_lockerTargetAddress) returns (uint) {
        locker memory theLocker = lockersMapping[_lockerTargetAddress];
        return (_priceOfOneUnitOfCollateral * theLocker.nativeTokenLockedAmount * (10 ** (1 + IERC20(teleBTC).decimals())))/
        (theLocker.netMinted * liquidationRatio * (10 ** (1 + NATIVE_TOKEN_DECIMAL)));
    }

    /**
     * @dev                                 Calculate the maximum buyable amount of collateral
     * @param _lockerTargetAddress          The locker's target address
     * @param _priceOfOneUnitOfCollateral   The price of one native token (1*10^18) in teleBTC
     * @return uint
     */
    function maxBuyableCollateral(
        address _lockerTargetAddress,
        uint _priceOfOneUnitOfCollateral
    ) public override view nonZeroAddress(_lockerTargetAddress) returns (uint) {
        locker memory theLocker = lockersMapping[_lockerTargetAddress];

        // maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio/10000 - nativeTokenLockedAmount*nativeTokenPrice)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice)
        //  => maxBuyable <= (upperHealthFactor*netMinted*liquidationRatio * 10^18  - nativeTokenLockedAmount*nativeTokenPrice * 10^8)/(upperHealthFactor*liquidationRatio*discountedPrice - nativeTokenPrice * 10^8)

        uint teleBTCDecimal = IERC20(teleBTC).decimals();

        uint antecedent = (UPPER_HEALTH_FACTOR * theLocker.netMinted * liquidationRatio * (10 ** NATIVE_TOKEN_DECIMAL)) -
        (theLocker.nativeTokenLockedAmount * _priceOfOneUnitOfCollateral * (10 ** teleBTCDecimal));

        uint consequent = ((UPPER_HEALTH_FACTOR * liquidationRatio * _priceOfOneUnitOfCollateral * priceWithDiscountRatio)/ONE_HUNDRED_PERCENT) -
        (_priceOfOneUnitOfCollateral * (10 ** teleBTCDecimal));

        return antecedent/consequent;
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
            "Lockers: this locker hasn't sufficient capacity"
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
            "Lockers: locker doesn't have sufficient funds"
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

    /// @notice                             Get the locker collateral in terms of TeleBTC
    /// @dev
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             The locker collateral in TeleBTC
    function _lockerCollateralInTeleBTC(address _lockerTargetAddress) private view returns (uint) {

        return IPriceOracle(priceOracle).equivalentOutputAmount(
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
            NATIVE_TOKEN_DECIMAL,
            IERC20(teleBTC).decimals(),
            NATIVE_TOKEN,
            teleBTC
        );
    }

    /// @notice                       Removes a locker from lockers list
    /// @dev                          Checks that net minted TeleBTC of locker is zero
    ///                               Sends back available bond of locker (in TDT and TNT)
    /// @param _lockerTargetAddress   Target address of locker to be removed
    function _removeLocker(address _lockerTargetAddress) private {

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: no locker with this address"
        );

        require(
            lockerLeavingRequests[_lockerTargetAddress],
            "Lockers: locker didn't request to be removed"
        );

        require(
            lockersMapping[_lockerTargetAddress].netMinted == 0,
            "Lockers: net minted is not zero"
        );

        locker memory _removingLokcer = lockersMapping[_lockerTargetAddress];

        // Removes locker from lockersMapping
        delete lockersMapping[_lockerTargetAddress];
        totalNumberOfLockers = totalNumberOfLockers - 1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).transfer(_lockerTargetAddress, _removingLokcer.TDTLockedAmount);
        Address.sendValue(payable(_lockerTargetAddress), _removingLokcer.nativeTokenLockedAmount);

        emit LockerRemoved(
            _lockerTargetAddress,
            _removingLokcer.lockerLockingScript,
            _removingLokcer.TDTLockedAmount,
            _removingLokcer.nativeTokenLockedAmount
        );

    }
}
