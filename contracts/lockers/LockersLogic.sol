// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LockersStorageStructure.sol";
import "./interfaces/ILockers.sol";
import "hardhat/console.sol";

contract LockersLogic is LockersStorageStructure, ILockers {

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
        return (_lockerCollateralInTeleBTC(_lockerTargetAddress)*10000/collateralRatio) - lockersMapping[_lockerTargetAddress].netMinted;
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
        collateralRatio = _collateralRatio;
    }

    /// @notice                                 Adds user to candidates list
    /// @dev
    /// @param _candidateLockingScript         Bitcoin address of the candidate
    /// @param _lockedTDTAmount                 Bond amount of locker in TDT
    /// @param _lockedNativeTokenAmount         Bond amount of locker in native token of the target chain
    /// @return                                 True if candidate is added successfully
    function requestToBecomeLocker(
        bytes calldata _candidateLockingScript,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount
    ) external override payable nonReentrant returns (bool) {

        require(
            !lockersMapping[msg.sender].isCandidate,
            "Lockers: user is already a candidate"
        );

        require(
            !lockersMapping[msg.sender].isLocker,
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
            "Lockers: redeem script hash is used before"
        );

        require(IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), _lockedTDTAmount));
        locker memory locker_;
        locker_.lockerLockingScript = _candidateLockingScript;
        locker_.TDTLockedAmount = _lockedTDTAmount;
        locker_.nativeTokenLockedAmount = _lockedNativeTokenAmount;
        locker_.isCandidate = true;

        lockersMapping[msg.sender] = locker_;

        totalNumberOfCandidates = totalNumberOfCandidates + 1;

        emit RequestAddLocker(
            msg.sender,
            _candidateLockingScript,
            _lockedTDTAmount,
            0
        );

        return true;
    }

    /// @notice                       Removes a candidate from candidates list
    /// @return                       True if candidate is removed successfully
    function revokeRequest() external override nonReentrant returns (bool) {

        require(
            lockersMapping[_msgSender()].isCandidate,
            "Lockers: request doesn't exist or already accepted"
        );

        // Loads locker's information
        locker memory lockerRequest = lockersMapping[_msgSender()];

        // Removes candidate from lockersMapping
        _removeCandidateFromLockersMapping(_msgSender());
        totalNumberOfCandidates = totalNumberOfCandidates -1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).transfer(_msgSender(), lockerRequest.TDTLockedAmount);
        Address.sendValue(payable(_msgSender()), lockerRequest.nativeTokenLockedAmount);

        return true;
    }

    /// @notice                               Approves a candidate request to become locker
    /// @dev                                  Only owner can call this
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

    /// @notice                             Requests to remove a locker from lockers list
    /// @dev                                Deactivates the status of the locker so that no
    /// one is allowed to send mint requests to this locker. It gives time to the locker to burn the required amount
    /// of teleBTC to make itself eligible to be removed.
    /// @return                             True if deactivated successfully
    function requestToRemoveLocker() external override nonReentrant returns (bool) {
        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: Msg sender is not locker"
        );

        lockersMapping[_msgSender()].isActive = false;

        lockerLeavingRequests[_msgSender()] = true;

        emit RequestRemoveLocker(
            msg.sender,
            lockersMapping[_msgSender()].lockerLockingScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount,
            lockersMapping[_msgSender()].netMinted
        );

        return true;
    }

    /// @notice                           Removes a locker from lockers pool
    /// @return                           True if locker is removed successfully
    function removeLocker(
        address _lockerTargetAddress
    ) external override nonZeroAddress(_lockerTargetAddress) nonReentrant onlyOwner returns (bool) {

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

        IERC20(TeleportDAOToken).transfer(_lockerTargetAddress, _removingLokcer.TDTLockedAmount);

        Address.sendValue(payable(_lockerTargetAddress), _removingLokcer.nativeTokenLockedAmount);

        _removeLockerFromLockersMapping(_lockerTargetAddress);

        totalNumberOfLockers = totalNumberOfLockers - 1;

        emit LockerRemoved(
            _lockerTargetAddress,
            _removingLokcer.lockerLockingScript,
            _removingLokcer.TDTLockedAmount,
            _removingLokcer.nativeTokenLockedAmount
        );

        return true;
    }


    /// @notice                           Removes a locker from lockers pool
    /// @return                           True if locker is removed successfully
    function selfRemoveLocker() external override nonReentrant whenNotPaused returns (bool) {

        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: no locker with this address"
        );

        require(
            lockerLeavingRequests[_msgSender()],
            "Lockers: locker didn't request to be removed"
        );

        require(
            lockersMapping[_msgSender()].netMinted == 0,
            "Lockers: net minted is not zero"
        );

        locker memory _removingLokcer = lockersMapping[_msgSender()];

        // Removes locker from lockersMapping
        _removeLockerFromLockersMapping(_msgSender());
        totalNumberOfLockers = totalNumberOfLockers - 1;

        // Sends back TDT and TNT collateral
        IERC20(TeleportDAOToken).transfer(_msgSender(), _removingLokcer.TDTLockedAmount);
        Address.sendValue(payable(_msgSender()), _removingLokcer.nativeTokenLockedAmount);

        emit LockerRemoved(
            _msgSender(),
            _removingLokcer.lockerLockingScript,
            _removingLokcer.TDTLockedAmount,
            _removingLokcer.nativeTokenLockedAmount
        );

        return true;
    }

    /// @notice                           Slashes lockers
    /// @dev                              Only cc burn router can call this
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _amount                    Amount of teleBTC that is slashed from lockers
    /// @param _recipient                 Address of user who receives the slashed amount
    /// @return                           True if lockers are slashed successfully
    function slashLocker(
        address _lockerTargetAddress,
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount,
        address _recipient
    ) external nonReentrant whenNotPaused override returns (bool) {
        require(
            msg.sender == ccBurnRouter,
            "Lockers: Caller can't slash"
        );

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        uint equivalentNativeToken = IPriceOracle(priceOracle).equivalentOutputAmount(
            _rewardAmount + _amount,
            8, // Decimal of teleBTC
            18, // Decimal of TNT
            teleBTC,
            NATIVE_TOKEN
        );

        require(
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount >= equivalentNativeToken,
            "Lockers: insufficient native token collateral"
        );

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
            payable(_rewardRecipient).transfer(equivalentNativeToken*_rewardAmount/(_amount + _rewardAmount));
        }

        emit LockerSlashed(_lockerTargetAddress, equivalentNativeToken);

        return true;
    }

    function liquidateLocker(
        address _lockerTargetAddress,
        uint _btcAmount
    ) external override nonZeroAddress(_lockerTargetAddress) nonZeroValue(_btcAmount)
    nonReentrant whenNotPaused returns (bool result) {

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        locker memory theLiquidatingLocker = lockersMapping[_lockerTargetAddress];
        uint theLockerCollateralBTCequivalent = _lockerCollateralInTeleBTC(_lockerTargetAddress);

        require(
            (theLiquidatingLocker.netMinted*liquidationRatio/10000) > theLockerCollateralBTCequivalent,
            "Lockers: this locker is above luquidation ratio"
        );

        /*
            Maximum buyable amount of collateral comes from:
            (BtcWorthOfCollateral - x)/(netMinted -x) = collateralRatio/10000
        */

        uint maxBuyable =
        ((theLiquidatingLocker.netMinted*collateralRatio/10000) -
        theLockerCollateralBTCequivalent)/((collateralRatio-10000)/10000);

        if (maxBuyable > theLiquidatingLocker.netMinted) {
            maxBuyable = theLiquidatingLocker.netMinted;
        }

        require(
            _btcAmount <= maxBuyable,
            "Lockers: above the locker's luquidation penalty"
        );

        IERC20(teleBTC).transferFrom(_msgSender(), address(this), _btcAmount);

        uint equivalentNativeToken = IPriceOracle(priceOracle).equivalentOutputAmount(
            _btcAmount,
        // TODO: get decimals from token contracts
            8,
            18,
            teleBTC,
            NATIVE_TOKEN
        );

        lockersMapping[_lockerTargetAddress].netMinted = lockersMapping[_lockerTargetAddress].netMinted - _btcAmount;

        Address.sendValue(payable(_msgSender()), equivalentNativeToken);

        result = true;

    }

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
        uint lockerFee = _amount*lockerPercentageFee/10000;
        if (lockerFee > 0) {
            ITeleBTC(teleBTC).mint(_lockerTargetAddress, lockerFee);
        }

        // Mints tokens for receiver
        ITeleBTC(teleBTC).mint(_receiver, _amount - lockerFee);

        return _amount - lockerFee;
    }

    function burn(
        bytes calldata _lockerLockingScript,
        uint _amount
    ) external override nonZeroValue(_amount)
    nonReentrant whenNotPaused onlyBurner returns (uint) {

        address _lockerTargetAddress = lockerTargetAddress[_lockerLockingScript];

        // Transfers teleBTC from user
        ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), _amount);

        uint lockerFee = _amount*lockerPercentageFee/10000;
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

        return remainedAmount;
    }

    // bitcoin double hash function
    function _doubleHash(bytes memory input) internal pure returns(address) {
        bytes32 inputHash1 = sha256(input);
        bytes20 inputHash2 = ripemd160(abi.encodePacked(inputHash1));
        return address(inputHash2);
    }

    /**
     * @dev Check if an account is minter.
     * @return bool
     */
    function _isMinter(address account) internal view nonZeroAddress(account) returns (bool) {
        return minters[account];
    }

    /**
     * @dev Check if an account is burner.
     * @return bool
     */
    function _isBurner(address account) internal view nonZeroAddress(account) returns (bool) {
        return burners[account];
    }

    /// @notice                      Removes an element of lockers list
    /// @dev                         Deletes and shifts the array
    /// @param _lockerAddress      Index of the element that will be deleted
    function _removeLockerFromLockersMapping(address _lockerAddress) internal {
        require(
            lockersMapping[_lockerAddress].isLocker,
            "Lockers: locker doesn't exist"
        );
        delete lockersMapping[_lockerAddress];
    }

    /// @notice                      Removes an element of lockers list
    /// @dev                         Deletes and shifts the array
    /// @param _candidateAddress     Index of the element that will be deleted
    function _removeCandidateFromLockersMapping(address _candidateAddress) internal {
        require(
            lockersMapping[_candidateAddress].isCandidate,
            "Lockers: candidate doesn't exist"
        );
        delete lockersMapping[_candidateAddress];
    }

    /// @notice                             Get the locker collateral in terms of TeleBTC
    /// @dev
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             The locker collateral in TeleBTC
    function _lockerCollateralInTeleBTC(address _lockerTargetAddress) internal view returns (uint) {

        return IPriceOracle(priceOracle).equivalentOutputAmount(
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
        // TODO: get decimals from token contracts
            18,
            8,
            NATIVE_TOKEN,
            teleBTC
        );
        // return lockersMapping[_lockerTargetAddress].TDTLockedAmount;
    }
}
