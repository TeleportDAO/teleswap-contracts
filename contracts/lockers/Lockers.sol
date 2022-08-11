// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../oracle/interfaces/IPriceOracle.sol";
import "./interfaces/ILockers.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/IERC20.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "hardhat/console.sol";

contract Lockers is ILockers, Ownable, ReentrancyGuard, Pausable {

    uint public override lockerPercentageFee;
    address public override TeleportDAOToken;
    address public override teleBTC;
    address public override ccBurnRouter;
    address public override exchangeConnector;
    // TODO: these are minimum amounts, so change their names
    uint public override minRequiredTDTLockedAmount;
    uint public override minRequiredTNTLockedAmount;
    address public constant NATIVE_TOKEN = address(1);

    // 10000 means 100%
    uint public override collateralRatio;
    uint public override liquidationRatio;
    // ^ this is because of price volitility and making minted coins for some collateral secure
    address public override priceOracle;

    uint public override totalNumberOfLockers;
    // lockerTargetAddress -> locker structure
    mapping(address => locker) public lockersMapping;

    uint public override totalNumberOfCandidates;
    // remember to remove from candidates when becomes locker
    mapping(address => locker) public candidatesMapping;

    // TODO: Combining the 2 mapping into 1 mapping to a struct
    mapping(address => bool) public lockerLeavingRequests;
    mapping(address => bool) public lockerLeavingAcceptance;

    mapping(address => address) public override lockerTargetAddress;

    mapping(address => bool) minters;
    mapping(address => bool) burners;

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "Lockers: only minters can mint");
        _;
    }

    /**
     * @dev Give an account access to mint.
     */
    function addMinter(address account) external override onlyOwner {
        require(!isMinter(account), "Lockers: account already has role");
        minters[account] = true;
    }

    /**
     * @dev Remove an account's access to mint.
     */
    function removeMinter(address account) external override onlyOwner {
        require(isMinter(account), "Lockers: account does not have role");
        minters[account] = false;
    }

    /**
     * @dev Check if an account is minter.
     * @return bool
     */
    function isMinter(address account)
    internal
    view
    returns (bool)
    {
        require(account != address(0), "Lockers: account is the zero address");
        return minters[account];
    }

    modifier onlyBurner() {
        require(isBurner(_msgSender()), "Lockers: only burners can burn");
        _;
    }

    /**
     * @dev Give an account access to burn.
     */
    function addBurner(address account) external override onlyOwner {
        require(!isBurner(account), "Lockers: account already has role");
        burners[account] = true;
    }

    /**
     * @dev Remove an account's access to burn.
     */
    function removeBurner(address account) external override onlyOwner {
        require(isBurner(account), "Lockers: account does not have role");
        burners[account] = false;
    }

    /**
     * @dev Check if an account is burner.
     * @return bool
     */
    function isBurner(address account)
    internal
    view
    returns (bool)
    {
        require(account != address(0), "Lockers: account is the zero address");
        return burners[account];
    }


    constructor(
        address _TeleportDAOToken,
        address _exchangeConnector,
        address _priceOracle,
        uint _minRequiredTDTLockedAmount,
        uint _minRequiredTNTLockedAmount,
        uint _collateralRatio,
        uint _liquidationRatio,
        uint _lockerPercentageFee
    ) public {
        // TODO: add some requires for the amounts of _collateralRatio and _liquidationRatio
        TeleportDAOToken = _TeleportDAOToken;
        exchangeConnector = _exchangeConnector;
        priceOracle = _priceOracle;
        minRequiredTDTLockedAmount = _minRequiredTDTLockedAmount;
        minRequiredTNTLockedAmount = _minRequiredTNTLockedAmount;
        collateralRatio = _collateralRatio;
        liquidationRatio = _liquidationRatio;
        lockerPercentageFee = _lockerPercentageFee;
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

    /// @notice                           Checks whether an address is locker
    /// @dev
    /// @param _lockerTargetAddress       Address of locker on the target chain
    /// @return                           True if user is locker
    function isLocker(address _lockerScriptHash) external override view returns(bool) {
        // TODO: use the bitcoin decoed address or target address
        return lockersMapping[lockerTargetAddress[_lockerScriptHash]].isLocker;
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
    function getLockerRedeemScript(address _lockerTargetAddress) external view override returns (bytes memory) {
        return lockersMapping[_lockerTargetAddress].lockerRedeemScript;
    }

    /// @notice                             Tells if a locker is active or not
    /// @dev                                An active locker is not in the process of being removed and has enough
    /// capacity to mint more tokens (minted - burnt << their collateral)
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             True if the locker is active and accepts mint requests
    function isActive(address _lockerTargetAddress) external view override returns (bool) {
        return lockersMapping[_lockerTargetAddress].isActive;
    }

    /// @notice                             Get how much net this locker has minted
    /// @dev                                Net minted amount is total minted minus total burnt for the locker
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             The net minted of the locker
    function getLockerCapacity(address _lockerTargetAddress) public view override returns (uint) {
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
    function setPriceOracle(address _priceOracle) external override onlyOwner {
        priceOracle = _priceOracle;
    }

    /// @notice                Changes cc burn router contract
    /// @dev                   Only current owner can call this
    /// @param _ccBurnRouter   The new cc burn router contract address
    function setCCBurnRouter(address _ccBurnRouter) external override onlyOwner {
        ccBurnRouter = _ccBurnRouter;
    }

    /// @notice                 Changes exchange router contract address and updates wrapped avax addresses
    /// @dev                    Only owner can call this
    /// @param _exchangeConnector  The new exchange router contract address
    function setExchangeConnector(address _exchangeConnector) external override onlyOwner {
        exchangeConnector = _exchangeConnector;
    }

    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
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
    /// @param _candidateRedeemScript         Bitcoin address of the candidate
    /// @param _lockedTDTAmount                 Bond amount of locker in TDT
    /// @param _lockedNativeTokenAmount         Bond amount of locker in native token of the target chain
    /// @return                                 True if candidate is added successfully
    function requestToBecomeLocker(
        bytes memory _candidateRedeemScript,
        address _candidateScriptHash,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount
    ) external payable nonReentrant override returns (bool) {
        // TODO: interface has changed, change the inside to comply with it

        require(
            _doubleHash(_candidateRedeemScript) == _candidateScriptHash,
            "Lockers: redeem script hash is not correct"
        );

        require(
            !candidatesMapping[msg.sender].isLocker,
            "Lockers: already requested"
        );

        require(
            !lockersMapping[msg.sender].isLocker,
            "Lockers: already is locker"
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
            lockerTargetAddress[_candidateScriptHash] == address(0),
            "Lockers: bitcoin decoded address is used before"
        );

        require(IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), _lockedTDTAmount));
        locker memory locker_;
        locker_.lockerRedeemScript = _candidateRedeemScript;
        locker_.lockerScriptHash = _candidateScriptHash;
        locker_.TDTLockedAmount = _lockedTDTAmount;
        locker_.nativeTokenLockedAmount = _lockedNativeTokenAmount;
        locker_.isLocker = true;

        candidatesMapping[msg.sender] = locker_;

        totalNumberOfCandidates = totalNumberOfCandidates + 1;

        emit RequestAddLocker(
            msg.sender,
            _candidateRedeemScript,
            _lockedTDTAmount,
            0,
            false
        );

        return true;
    }

    /// @notice                       Removes a candidate from candidates list
    /// @return                       True if candidate is removed successfully
    function revokeRequest() external nonReentrant override returns (bool) {

        require(
            candidatesMapping[_msgSender()].isLocker,
            "Lockers: request doesn't exit or already accepted"
        );

        locker memory theLockerRequest = candidatesMapping[_msgSender()];

        IERC20(TeleportDAOToken).transfer(_msgSender(), theLockerRequest.TDTLockedAmount);

        // TODO: consider all possible attacks
        address payable targetLockerAddress = payable(_msgSender());
        targetLockerAddress.transfer(theLockerRequest.nativeTokenLockedAmount);

        // Removes candidate from candidate list
        _removeElementFromCandidatesMapping(_msgSender());

        totalNumberOfCandidates = totalNumberOfCandidates -1;
        return true;
    }

    /// @notice                               Approves a candidate request to become locker
    /// @dev                                  Only owner can call this
    /// @param _lockerTargetAddress           Locker's target chain address
    /// @return                               True if candidate is added successfully
    function addLocker(address _lockerTargetAddress) external nonReentrant onlyOwner override returns (bool) {

        require(
            candidatesMapping[_lockerTargetAddress].isLocker,
            "Lockers: no request with this address"
        );

        // TODO
        lockersMapping[_lockerTargetAddress] = candidatesMapping[_lockerTargetAddress];
        lockersMapping[_lockerTargetAddress].isActive = true;

        _removeElementFromCandidatesMapping(_lockerTargetAddress);

        totalNumberOfLockers = totalNumberOfLockers + 1;
        totalNumberOfCandidates = totalNumberOfCandidates -1;

        lockerTargetAddress[lockersMapping[_lockerTargetAddress].lockerScriptHash] = _lockerTargetAddress;

        emit LockerAdded(
            _lockerTargetAddress,
            lockersMapping[_lockerTargetAddress].lockerRedeemScript,
            lockersMapping[_lockerTargetAddress].TDTLockedAmount,
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
            lockersMapping[_lockerTargetAddress].isScriptHash
        );
        return true;
    }

    /// @notice                             Requests to remove a locker from lockers list
    /// @dev                                Deactivates the status of the locker so that no
    /// one is allowed to send mint requests to this locker. It gives time to the locker to burn the required amount
    /// of teleBTC to make itself eligible to be removed.
    /// @return                             True if deactivated successfully
    function requestToRemoveLocker() external nonReentrant override returns (bool) {
        require(
            lockersMapping[_msgSender()].isLocker,
            "Lockers: Msg sender is not locker"
        );

        lockersMapping[_msgSender()].isActive = false;

        lockerLeavingRequests[_msgSender()] = true;

        emit RequestRemoveLocker(
            msg.sender,
            lockersMapping[_msgSender()].lockerRedeemScript,
            lockersMapping[_msgSender()].TDTLockedAmount,
            lockersMapping[_msgSender()].nativeTokenLockedAmount,
            lockersMapping[_msgSender()].netMinted
        );

        return true;
    }

    /// @notice                           Removes a locker from lockers pool
    /// @return                           True if locker is removed successfully
    function removeLocker(address _lockerTargetAddress) external nonReentrant onlyOwner override returns (bool) {
        // TODO
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

        locker memory theRemovingLokcer = lockersMapping[_lockerTargetAddress];

        IERC20(TeleportDAOToken).transfer(_lockerTargetAddress, theRemovingLokcer.TDTLockedAmount);

        // TODO: consider all possible attacks
        address payable targetLockerAddress = payable(_lockerTargetAddress);
        targetLockerAddress.transfer(theRemovingLokcer.nativeTokenLockedAmount);

        _removeElementFromLockersMapping(_lockerTargetAddress);

        totalNumberOfLockers = totalNumberOfLockers - 1;

        emit LockerRemoved(
            _lockerTargetAddress,
            theRemovingLokcer.lockerRedeemScript,
            theRemovingLokcer.TDTLockedAmount,
            theRemovingLokcer.nativeTokenLockedAmount
        );

        return true;
    }


    /// @notice                           Removes a locker from lockers pool
    /// @return                           True if locker is removed successfully
    function selfRemoveLocker() external nonReentrant whenNotPaused override returns (bool) {
        // TODO
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

        locker memory theRemovingLokcer = lockersMapping[_msgSender()];

        IERC20(TeleportDAOToken).transfer(_msgSender(), theRemovingLokcer.TDTLockedAmount);


        // TODO: consider all possible attacks
        address payable targetLockerAddress = payable(_msgSender());
        targetLockerAddress.transfer(theRemovingLokcer.nativeTokenLockedAmount);

        _removeElementFromLockersMapping(_msgSender());

        totalNumberOfLockers = totalNumberOfLockers - 1;

        emit LockerRemoved(
            _msgSender(),
            theRemovingLokcer.lockerRedeemScript,
            theRemovingLokcer.TDTLockedAmount,
            theRemovingLokcer.nativeTokenLockedAmount
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
    // TODO: change the name to btcAmount
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

    /// @notice                      Removes an element of array of candidates
    /// @dev                         Deletes and shifts the array
    /// @param _candidateAddress       Index of the element that will be deleted
    function _removeElementFromCandidatesMapping(address _candidateAddress) internal {
        require(candidatesMapping[_candidateAddress].isLocker, "Lockers: this candidate doesn't exist");

        delete candidatesMapping[_candidateAddress];

    }

    /// @notice                      Removes an element of lockers list
    /// @dev                         Deletes and shifts the array
    /// @param _lockerAddress      Index of the element that will be deleted
    function _removeElementFromLockersMapping(address _lockerAddress) internal {
        require(lockersMapping[_lockerAddress].isLocker, "Lockers: this locker doesn't exist");

        delete lockersMapping[_lockerAddress];
    }

    /// @notice                             Get the locker collateral in terms of TeleBTC
    /// @dev
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             The locker collateral in TeleBTC
    function _lockerCollateralInTeleBTC(address _lockerTargetAddress) internal view returns (uint) {

        // TODO: shall we get the equivalent amount of tdt token and native token and adding up them?
        return IPriceOracle(priceOracle).equivalentOutputAmount(
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
        // FIXME: get decimals from token contracts
            18,
            8,
            NATIVE_TOKEN,
            teleBTC
        );
        // return lockersMapping[_lockerTargetAddress].TDTLockedAmount;
    }


    function luquidateLocker(
        address _lockerTargetAddress,
        uint _btcAmount
    ) external nonReentrant whenNotPaused override returns (bool result) {

        require(
            lockersMapping[_lockerTargetAddress].isLocker,
            "Lockers: target address is not locker"
        );

        locker memory theLuquidatingLokcer = lockersMapping[_lockerTargetAddress];
        uint theLockerCollateralBTCequivalent = _lockerCollateralInTeleBTC(_lockerTargetAddress);

        require(
            (theLuquidatingLokcer.netMinted*liquidationRatio/10000) > theLockerCollateralBTCequivalent,
            "Lockers: this locker is above luquidation ratio"
        );

        // Maximum buyable amount of collateral comes from ((BtcWorthOfCollateral - x)/(netMinted -x ) = collateralRatio/10000)

        uint maxBuyable = ((theLuquidatingLokcer.netMinted*collateralRatio/10000) - theLockerCollateralBTCequivalent)/((collateralRatio-10000)/10000);

        if (maxBuyable > theLuquidatingLokcer.netMinted) {
            maxBuyable = theLuquidatingLokcer.netMinted;
        }

        require(
            _btcAmount <= maxBuyable,
            "Lockers: above the locker's luquidation penalty"
        );

        IERC20(teleBTC).transferFrom(_msgSender(), address(this), _btcAmount);

        uint equivalentNativeToken = IPriceOracle(priceOracle).equivalentOutputAmount(
            _btcAmount,
        // FIXME: get decimals from token contracts
            8,
            18,
            teleBTC,
            NATIVE_TOKEN
        );

        lockersMapping[_lockerTargetAddress].netMinted = lockersMapping[_lockerTargetAddress].netMinted - _btcAmount;

        payable(_msgSender()).transfer(equivalentNativeToken);

        result = true;

    }


    function mint(
        address _lockerScriptHash,
        address _receiver,
        uint _amount
    ) external nonReentrant whenNotPaused onlyMinter override returns (uint) {

        // TODO: move the followoing lines of code to an internal function
        address theLockerTargetAddress = lockerTargetAddress[_lockerScriptHash];

        uint theLockerCapacity = getLockerCapacity(theLockerTargetAddress);

        require(
            theLockerCapacity >= _amount,
            "Lockers: this locker hasn't sufficient capacity"
        );

        lockersMapping[theLockerTargetAddress].netMinted = lockersMapping[theLockerTargetAddress].netMinted + _amount;

        // Mints locker fee
        uint lockerFee = _amount*lockerPercentageFee/10000;
        if (lockerFee > 0) {
            ITeleBTC(teleBTC).mint(theLockerTargetAddress, lockerFee);
        }

        // Mints tokens for receiver
        ITeleBTC(teleBTC).mint(_receiver, _amount - lockerFee);

        return (_amount - lockerFee);
    }

    function burn(
        address _lockerScriptHash,
        uint _amount
    ) external nonReentrant whenNotPaused onlyBurner override returns (uint) {

        // TODO: move the followoing lines of code to an internal function
        address theLockerTargetAddress = lockerTargetAddress[_lockerScriptHash];

        // Transfers teleBTC from user
        ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), _amount);

        uint lockerFee = _amount*lockerPercentageFee/10000;
        uint remainedAmount = _amount - lockerFee;
        uint netMinted = lockersMapping[theLockerTargetAddress].netMinted;

        require(
            netMinted >= remainedAmount,
            "Lockers: locker doesn't have sufficient funds"
        );

        lockersMapping[theLockerTargetAddress].netMinted = netMinted - remainedAmount;

        // Burns teleBTC and sends rest of it to locker
        ITeleBTC(teleBTC).burn(remainedAmount);
        ITeleBTC(teleBTC).transfer(theLockerTargetAddress, lockerFee);

        return remainedAmount;
    }

    // bitcoin double hash function
    function _doubleHash (bytes memory input) internal pure returns(address) {
        bytes32 inputHash1 = sha256(input);
        bytes20 inputHash2 = ripemd160(abi.encodePacked(inputHash1));
        return address(inputHash2);
    }
}
