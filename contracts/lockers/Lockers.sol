pragma solidity 0.8.0;

import "../oracle/interfaces/IPriceOracle.sol";
import "./interfaces/ILockers.sol";
import "../routers/interfaces/IExchangeRouter.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/IERC20.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract Lockers is ILockers, Ownable, ReentrancyGuard {

    uint public override lockerPercentageFee;
    address public override TeleportDAOToken;
    address public override teleBTC;
    address public override ccBurnRouter;
    address public override exchangeConnector;
    // uint public override requiredLockedAmount;
    uint public override requiredTDTLockedAmount;
    uint public override requiredTNTLockedAmount;

    // 10000 means 100%
    uint public override collateralRatio;
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

    // address public override redeemScriptHash;

    // bytes constant ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

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
        uint _requiredTDTLockedAmount,
        uint _requiredTNTLockedAmount,
        uint _collateralRatio,
        uint _lockerPercentageFee
    ) public {
        TeleportDAOToken = _TeleportDAOToken;
        exchangeConnector = _exchangeConnector;
        priceOracle = _priceOracle;
        requiredTDTLockedAmount = _requiredTDTLockedAmount;
        // requiredNativeTokenLockedAmount = _requiredNativeTokenLockedAmount;
        requiredTNTLockedAmount = _requiredTNTLockedAmount;
        collateralRatio = _collateralRatio;
        lockerPercentageFee = _lockerPercentageFee;
    }

    /// @notice                           Checks whether an address is locker
    /// @dev
    /// @param _lockerTargetAddress       Address of locker on the target chain
    /// @return                           True if user is locker
    function isLocker(address _lockerBitcoinDecodedAddress) external override view returns(bool) {
        // TODO: use the bitcoin decoed address or target address
        return lockersMapping[lockerTargetAddress[_lockerBitcoinDecodedAddress]].isExisted;
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
    function getLockerBitcoinAddress(address _lockerTargetAddress) external view override returns (bytes memory) {
        return lockersMapping[_lockerTargetAddress].lockerBitcoinAddress;
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
    function getLockerCapacity(address _lockerTargetAddress) external view override returns (uint) {
        return (_lockerCollateralInTeleBTC(_lockerTargetAddress)*10000/collateralRatio) - lockersMapping[_lockerTargetAddress].netMinted;
    }

    /// @notice         Changes the required bond amount to become locker
    /// @dev            Only current owner can call this
    /// @param _requiredTDTLockedAmount   The new required bond amount
    function setRequiredTDTLockedAmount(uint _requiredTDTLockedAmount) external override onlyOwner {
        requiredTDTLockedAmount = _requiredTDTLockedAmount;
    }

    /// @notice         Changes the required bond amount to become locker
    /// @dev            Only current owner can call this
    /// @param _requiredTNTLockedAmount   The new required bond amount
    function setRequiredTNTLockedAmount(uint _requiredTNTLockedAmount) external override onlyOwner {
        requiredTNTLockedAmount = _requiredTNTLockedAmount;
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

    /// @notice                                Updates status of isActive for a locker
    /// @dev                                   If someone mints or burns, the locker it uses might change status according
    /// to the condition: minted - burnt should be << locked collateral. Might revert if the amount is too high and
    /// status cannot be updated. -> very important for security
    /// @param _lockerBitcoinDecodedAddress    Locker address on the target chain
    /// @param _amount                         Amount of the burn or mint that has been done
    /// @param _isMint                         True if the request is mint, false if it is burn
    function updateIsActive(
        address _lockerBitcoinDecodedAddress, 
        uint _amount, 
        bool _isMint
    ) external override onlyOwner returns (bool) {
        // FIXME: this function signature is not working for its reason and must get the ethereum address of the locker
        // TODO: require after the transaction is done, the locker still has enough collateral (not necessarily active)
        return true;
    }

    /// @notice                                 Adds user to candidates list
    /// @dev
    /// @param _candidateBitcoinAddress         Bitcoin address of the candidate
    /// @param _lockedTDTAmount                 Bond amount of locker in TDT
    /// @param _lockedNativeTokenAmount         Bond amount of locker in native token of the target chain
    /// @return                                 True if candidate is added successfully
    function requestToBecomeLocker(
        bytes memory _candidateBitcoinAddress,
        address _candidateBitcoinDecodedAddress,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount
    ) external nonReentrant override returns (bool) {
        // TODO: interface has changed, change the inside to comply with it
        // Locks user bond

        require(
            !candidatesMapping[msg.sender].isExisted,
            "Locker: already reuested"
        );

        require(
            !lockersMapping[msg.sender].isExisted,
            "Locker: already is locker"
        );

        require(
            _lockedTDTAmount >= requiredTDTLockedAmount,
            "Locker: low locking TDT amount"
        );

        require(IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), _lockedTDTAmount));
        locker memory locker_;
        locker_.lockerBitcoinAddress = _candidateBitcoinAddress;
        locker_.lockerBitcoinDecodedAddress = _candidateBitcoinDecodedAddress;
        locker_.TDTLockedAmount = _lockedTDTAmount;
        // TODO: what exactly should I do with _lockedNativeTokenAmount?
        locker_.nativeTokenLockedAmount = 0;
        locker_.isExisted = true;

        candidatesMapping[msg.sender] = locker_;

        totalNumberOfCandidates = totalNumberOfCandidates + 1;

        emit RequestAddLocker(
            msg.sender,
            _candidateBitcoinAddress,
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
            candidatesMapping[msg.sender].isExisted,
            "Locker: request doesn't exit or already accepted"
        );

        // TODO: implement it
        // TODO: msg.sender is the target chain address of the candidate (require)
        // Sends back the candidate bond
        IERC20(TeleportDAOToken).transfer(msg.sender, candidatesMapping[msg.sender].TDTLockedAmount);

        // Removes candidate from candidate list
        _removeElementFromCandidatesMapping(msg.sender);

        totalNumberOfCandidates = totalNumberOfCandidates -1;
        return true;
    }

    /// @notice                               Approves a candidate request to become locker
    /// @dev                                  Only owner can call this
    /// @param _lockerTargetAddress           Locker's target chain address
    /// @return                               True if candidate is added successfully
    function addLocker(address _lockerTargetAddress) external nonReentrant onlyOwner override returns (bool) {

        require(
            candidatesMapping[_lockerTargetAddress].isExisted,
            "Locker: no request with this address"
        );

        // TODO
        lockersMapping[_lockerTargetAddress] = candidatesMapping[_lockerTargetAddress];
        lockersMapping[_lockerTargetAddress].isActive = true;

        // bytes memory lockerBitcoinPubKey = candidatesList[_candidateIndex].lockerBitcoinPubKey;
        // address lockerAddress = candidatesList[_candidateIndex].lockerAddress;
        // uint lockedAmount = candidatesList[_candidateIndex].lockedAmount;
        _removeElementFromCandidatesMapping(_lockerTargetAddress);
        // require(_updateRedeemScriptHash(), "locker address is not correct");
        // require(_updateMultisigAddress(), "locker address is not correct");

        totalNumberOfLockers = totalNumberOfLockers + 1;
        totalNumberOfCandidates = totalNumberOfCandidates -1;

        lockerTargetAddress[lockersMapping[_lockerTargetAddress].lockerBitcoinDecodedAddress] = _lockerTargetAddress;

        emit LockerAdded(
            _lockerTargetAddress,
            lockersMapping[_lockerTargetAddress].lockerBitcoinAddress,
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
            lockersMapping[msg.sender].isExisted,
            "Locker: Msg sender is not locker"
        );

        lockersMapping[msg.sender].isActive = false;

        lockerLeavingRequests[msg.sender] = true;

        emit RequestRemoveLocker(
            msg.sender,
            lockersMapping[msg.sender].lockerBitcoinAddress,
            lockersMapping[msg.sender].TDTLockedAmount,
            lockersMapping[msg.sender].nativeTokenLockedAmount,
            lockersMapping[msg.sender].netMinted
        );

        return true;
    }

    /// @notice                           Removes a locker from lockers pool
    /// @return                           True if locker is removed successfully
    // FIXME: removeLocker must be changed and got the lockerAddress and only admin must be able to call it
    function removeLocker(address _lockerTargetAddress) external nonReentrant onlyOwner override returns (bool) {
        // TODO
        require(
            lockersMapping[_lockerTargetAddress].isExisted,
            "Locker: no locker with this address"
        );

        require(
            lockerLeavingRequests[_lockerTargetAddress],
            "Locker: locker didn't request to be removed"
        );

        require(
            lockersMapping[_lockerTargetAddress].netMinted == 0,
            "Locker: net minted is not zero"
        );

        // require(block.number.add(unlockPeriod) >= lastLockerRemove, "Cannot remove locker at this time");
        // bytes memory lockerBitcoinPubKey = lockersList[_lockerIndex].lockerBitcoinPubKey;
        // address lockerAddress = lockersList[_lockerIndex].lockerAddress;
        // uint lockedAmount = lockersList[_lockerIndex].lockedAmount;
        // Amount of unlocked token after reducing the unlocking fee
        // uint unlockedAmount = lockedAmount.mul(100.sub(unlockFee)).div(100);

        locker memory theRemovingLokcer = lockersMapping[_lockerTargetAddress];

        // require(_updateRedeemScriptHash(), "Locker address is not correct");
        // require(_updateMultisigAddress(), "Locker address is not correct");
        // Sends back part of the locker's bond
        IERC20(TeleportDAOToken).transfer(_lockerTargetAddress, theRemovingLokcer.TDTLockedAmount);

        _removeElementFromLockersMapping(_lockerTargetAddress);

        totalNumberOfLockers = totalNumberOfLockers - 1;

        emit LockerRemoved(
            _lockerTargetAddress,
            theRemovingLokcer.lockerBitcoinAddress,
            theRemovingLokcer.TDTLockedAmount,
            theRemovingLokcer.nativeTokenLockedAmount
        );

        return true;
    }


    /// @notice                           Removes a locker from lockers pool
    /// @return                           True if locker is removed successfully
    // FIXME: removeLocker must be changed and got the lockerAddress and only admin must be able to call it
    function selfRemoveLocker() external nonReentrant override returns (bool) {
        // TODO
        require(
            lockersMapping[msg.sender].isExisted,
            "Locker: no locker with this address"
        );

        require(
            lockerLeavingRequests[msg.sender],
            "Locker: locker didn't request to be removed"
        );

        require(
            lockersMapping[msg.sender].netMinted == 0,
            "Locker: net minted is not zero"
        );

        // require(block.number.add(unlockPeriod) >= lastLockerRemove, "Cannot remove locker at this time");
        // bytes memory lockerBitcoinPubKey = lockersList[_lockerIndex].lockerBitcoinPubKey;
        // address lockerAddress = lockersList[_lockerIndex].lockerAddress;
        // uint lockedAmount = lockersList[_lockerIndex].lockedAmount;
        // Amount of unlocked token after reducing the unlocking fee
        // uint unlockedAmount = lockedAmount.mul(100.sub(unlockFee)).div(100);

        locker memory theRemovingLokcer = lockersMapping[msg.sender];

        // require(_updateRedeemScriptHash(), "Locker address is not correct");
        // require(_updateMultisigAddress(), "Locker address is not correct");
        // Sends back part of the locker's bond
        IERC20(TeleportDAOToken).transfer(msg.sender, theRemovingLokcer.TDTLockedAmount);

        _removeElementFromLockersMapping(msg.sender);

        emit LockerRemoved(
            msg.sender,
            theRemovingLokcer.lockerBitcoinAddress,
            theRemovingLokcer.TDTLockedAmount,
            theRemovingLokcer.nativeTokenLockedAmount
        );

        return true;
    }

    /// @notice                           Slashes lockers
    /// @dev                              Only cc burn router can call this
    /// @param _lockerTargetAddress       Locker's target chain address
    /// @param _amount                    Amount that is slashed from lockers
    /// @param _recipient                 Address of user who receives the slashed amount
    /// @return                           True if lockers are slashed successfully
    function slashLocker(address _lockerTargetAddress, uint _amount, address _recipient) external nonReentrant override returns (bool) {
        require(
            msg.sender == ccBurnRouter,
            "Locker: Caller can't slash"
        );

        require(
            lockersMapping[_lockerTargetAddress].isExisted,
            "Locker: target is not locker"
        );

        // TODO: slash only the determined locker
        address[] memory path = new address[](2);
        path[0] = TeleportDAOToken;
        path[1] = teleBTC;
        // Finds the needed input amount to buy _amount of output token
        (bool theResult, uint neededTDT) = IExchangeConnector(exchangeConnector).getInputAmount(_amount, TeleportDAOToken, teleBTC);

        if (!theResult) {
            return false;
        }
        // Updates locked amount of lockers
        // uint lockersListLenght = lockersList.lenght;
        // for (uint i = 0; i < lockersListLenght; i++) {
        //     lockersList[i].lockedAmount = lockersList[i].lockedAmount.sub(
        //         neededTDT.div(lockersListLenght)
        //     );
        // }
        // Transfers slashed tokens to recipient
        // IERC20(TeleportDAOToken).transfer(_recipient, neededTDT[0]);

        // TODO: use native token instead of teleport dao token
        lockersMapping[_lockerTargetAddress].TDTLockedAmount = lockersMapping[_lockerTargetAddress].TDTLockedAmount - neededTDT;

        IERC20(TeleportDAOToken).approve(exchangeConnector, neededTDT);
        uint deadline = block.timestamp + 1000;

        IExchangeConnector(exchangeConnector).swap(
            _amount, // amount out
            neededTDT, // amount in
            path,
            _recipient,
            deadline,
        // TODO: how to set the isFIxedToken
            true
        );

        return true;
    }

    /// @notice                      Removes an element of array of candidates
    /// @dev                         Deletes and shifts the array
    /// @param _candidateAddress       Index of the element that will be deleted
    function _removeElementFromCandidatesMapping(address _candidateAddress) internal {
        require(candidatesMapping[_candidateAddress].isExisted, "Locker: this candidate doesn't exist");

        delete candidatesMapping[_candidateAddress];

    }

    /// @notice                      Removes an element of lockers list
    /// @dev                         Deletes and shifts the array
    /// @param _lockerAddress      Index of the element that will be deleted
    function _removeElementFromLockersMapping(address _lockerAddress) internal {
        require(lockersMapping[_lockerAddress].isExisted, "Locker: this locker doesn't exist");

        delete lockersMapping[_lockerAddress];
    }

    /// @notice                             Get the locker collateral in terms of TeleBTC
    /// @dev
    /// @param _lockerTargetAddress         Address of locker on the target chain
    /// @return                             The locker collateral in TeleBTC
    function _lockerCollateralInTeleBTC(address _lockerTargetAddress) internal view returns (uint) {

        return IPriceOracle(priceOracle).equivalentOutputAmount(
            lockersMapping[_lockerTargetAddress].TDTLockedAmount,
        // FIXME: get decimals from token contracts
            18,
            8,
            TeleportDAOToken,
            teleBTC
        );
        // return lockersMapping[_lockerTargetAddress].TDTLockedAmount;
    }


    function mint(
        address _lockerBitcoinDecodedAddress, 
        address _receiver, 
        uint _amount
    ) external nonReentrant onlyMinter override returns (uint) {

        // TODO: move the followoing lines of code to an internal function
        address theLockerTargetAddress = lockerTargetAddress[_lockerBitcoinDecodedAddress];
        locker memory theLocker = lockersMapping[theLockerTargetAddress];

        uint theLockerCollateral = _lockerCollateralInTeleBTC(theLockerTargetAddress);
        uint netMinted = lockersMapping[theLockerTargetAddress].netMinted;
        require(
            theLockerCollateral >= _amount + netMinted,
            "Lockers: this locker hasn't sufficient funds"
        );

        lockersMapping[theLockerTargetAddress].netMinted = netMinted + _amount;

        // Mints locker fee
        uint lockerFee = _amount*lockerPercentageFee/10000;
        if (lockerFee > 0) {
            ITeleBTC(teleBTC).mint(theLockerTargetAddress, lockerFee);
        }
        
        // Mints tokens for receiver
        ITeleBTC(teleBTC).mint(_receiver, _amount - lockerFee);

        return _amount - lockerFee;
    }

    function burn(
        address _lockerBitcoinDecodedAddress, 
        uint _amount
    ) external nonReentrant onlyBurner override returns (uint) {

        // TODO: move the followoing lines of code to an internal function
        address theLockerTargetAddress = lockerTargetAddress[_lockerBitcoinDecodedAddress];

        // Transfers teleBTC from user
        ITeleBTC(teleBTC).transferFrom(msg.sender, address(this), _amount);

        uint lockerFee = _amount*lockerPercentageFee/10000;
        uint remainedAmount = _amount - lockerFee;
        uint netMinted = lockersMapping[theLockerTargetAddress].netMinted;

        // TODO: check if using price oracle is needed or not
        require(
            netMinted >= remainedAmount,
            "Lockers: locker doesn't have sufficient funds"
        );

        lockersMapping[theLockerTargetAddress].netMinted = netMinted - remainedAmount;

        // Burns teleBTC and sends rest of it to locker
        ITeleBTC(teleBTC).burn(remainedAmount);
        ITeleBTC(teleBTC).transfer(theLockerTargetAddress, lockerFee);
    }
}
