pragma solidity 0.8.0;

import "../libraries/SafeMath.sol";
import "./interfaces/ILockers.sol";
import "../routers/interfaces/IExchangeRouter.sol";
import "../erc20/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract Lockers is ILockers, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address public override TeleportDAOToken;
    address public override teleBTC;
    address public override ccBurnRouter;
    address public override exchangeRouter;
    // uint public override requiredLockedAmount;
    uint public override requiredTDTLockedAmount;
    uint public override requiredTNTLockedAmount;

    uint public override collateralRatio;
    // ^ this is because of price volitility and making minted coins for some collateral secure
    address public override priceOracle;

    // TODO: add to the interface
    uint public totalNumberOfLockers;
    // lockerTargetAddress -> locker structure
    mapping(address => locker) public lockersMapping;

    // TODO: add to the interface
    uint public totalNumberOfCandidates;
    // remember to remove from candidates when becomes locker
    mapping(address => locker) public candidatesMapping;


    // TODO: Combining the 2 mapping into
    mapping(address => bool) public lockerLeavingRequests;
    mapping(address => bool) public lockerLeavingAcceptance;

    mapping(bytes => address) public override BitcoinAddressToTargetAddress;

    // below list is for sorting lockers regarding capacity and choosing locker for burn or mint
    // TODO: remove this list and add a variable to store the number of the lockers
    // address[] public lockerTargetAddressList;
    // address[] public candidateTargetAddressList;

    // uint public unlockFee; // it is a percentage
    // uint public unlockPeriod;
    // uint public lastUnlock;
    // teleporter[] public teleportersList;
    // uint public override numberOfTeleporters;
    // bytes public override redeemScript;
    address public override redeemScriptHash;
    // address public override multisigAddress;
    // bytes public override multisigAddressBeforeEncoding;
    // bytes constant ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

    // modifier onlyOwner {
    //     require(msg.sender == owner);
    //     _;
    // }

    // constructor(
    //     address _TeleportDAOToken,
    //     address _exchangeRouter,
    //     uint _unlockFee,
    //     uint _unlockPeriod,
    //     uint _requiredLockedAmount
    // ) public {
    //     TeleportDAOToken = _TeleportDAOToken;
    //     // Fixed bug
    //     exchangeRouter = _exchangeRouter;
    //     unlockFee = _unlockFee;
    //     unlockPeriod = _unlockPeriod;
    //     requiredLockedAmount = _requiredLockedAmount;
    //     owner = msg.sender;
    // }

    constructor(
        address _TeleportDAOToken,
        address _exchangeRouter,
        address _priceOracle,
        uint _requiredTDTLockedAmount,
        uint _requiredTNTLockedAmount,
        uint _collateralRatio
    ) public {
        TeleportDAOToken = _TeleportDAOToken;
        exchangeRouter = _exchangeRouter;
        priceOracle = _priceOracle;
        requiredTDTLockedAmount = _requiredTDTLockedAmount;
        // requiredNativeTokenLockedAmount = _requiredNativeTokenLockedAmount;
        requiredTNTLockedAmount = _requiredTNTLockedAmount;
        collateralRatio = _collateralRatio;
    }

    /// @notice                           Checks whether an address is locker
    /// @dev
    /// @param _lockerTargetAddress       Address of locker on the target chain
    /// @return                           True if user is locker
    function isLocker(address _lockerTargetAddress) external override view returns(bool) {
        return lockersMapping[_lockerTargetAddress].isExisted;
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
        // FIXME: fix this function too
        return _lockerCollateralInTeleBTC(_lockerTargetAddress).mul(collateralRatio).sub(lockersMapping[_lockerTargetAddress].netMinted);
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
    /// @param _exchangeRouter  The new exchange router contract address
    function setExchangeRouter(address _exchangeRouter) external override onlyOwner {
        exchangeRouter = _exchangeRouter;
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

    /// @notice                         Updates status of isActive for a locker
    /// @dev                            If someone mints or burns, the locker it uses might change status according
    /// to the condition: minted - burnt should be << locked collateral. Might revert if the amount is too high and
    /// status cannot be updated. -> very important for security
    /// @param _lockerBitcoinAddress    Locker address on the target chain
    /// @param _amount                  Amount of the burn or mint that has been done
    /// @param _isMint                  True if the request is mint, false if it is burn
    function updateIsActive(address _lockerBitcoinAddress, uint _amount, bool _isMint) external override onlyOwner returns (bool) {
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

        BitcoinAddressToTargetAddress[lockersMapping[_lockerTargetAddress].lockerBitcoinAddress] = _lockerTargetAddress;

        emit LockerAdded(
            _lockerTargetAddress,
            lockersMapping[_lockerTargetAddress].lockerBitcoinAddress,
            lockersMapping[_lockerTargetAddress].TDTLockedAmount,
            lockersMapping[_lockerTargetAddress].nativeTokenLockedAmount,
            lockersMapping[_lockerTargetAddress].isScriptHash
        );

        // emit AddLocker(
        //     lockerBitcoinPubKey,
        //     lockerAddress,
        //     lockedAmount,
        //     block.timestamp
        // );
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
        uint[] memory neededTDT = IExchangeRouter(exchangeRouter).getAmountsIn(_amount, path);
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
        lockersMapping[_lockerTargetAddress].TDTLockedAmount = lockersMapping[_lockerTargetAddress].TDTLockedAmount - neededTDT[0];

        IERC20(TeleportDAOToken).approve(exchangeRouter, neededTDT[0]);
        uint deadline = block.timestamp + 1000;
        IExchangeRouter(exchangeRouter).swapTokensForExactTokens(
            _amount, // amount out
            neededTDT[0], // amount in
            path,
            _recipient,
            deadline
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
        // TODO
        return lockersMapping[_lockerTargetAddress].TDTLockedAmount;
    }


    // function addTeleporter (bytes memory _teleporterBitcoinPubKey) external override returns(bool) {
    //     // user need to lock enough amount of TDT to become teleporter
    //     IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), requiredLockedAmount);
    //     teleporter memory _teleporter;
    //     _teleporter.teleporterBitcoinPubKey = _teleporterBitcoinPubKey;
    //     _teleporter.teleporterAddress = msg.sender;
    //     // we cannot resize the solidity array, so we store the number of teleporters in numberOfTeleporters
    //     if (teleportersList.length == numberOfTeleporters) {
    //         teleportersList.push(_teleporter);
    //     } else {
    //         teleportersList[numberOfTeleporters] = _teleporter;
    //     }
    //     numberOfTeleporters = numberOfTeleporters + 1;
    //     require(updateRedeemScriptHash(), "teleporter address is not correct");
    //     require(updateMultisigAddress(), "teleporter address is not correct");
    //     emit AddTeleporter(_teleporterBitcoinPubKey, msg.sender, requiredLockedAmount, block.timestamp);
    //     return true;
    // }

    // function removeTeleporter (uint teleporterIndex) external override returns(bool) {
    //     require(teleportersList[teleporterIndex].teleporterAddress == msg.sender, "you are not allowed to remove teleporter");
    //     // Fixed bug
    //     require(block.number >= lastUnlock + unlockPeriod, "too soon for new unlock");
    //     require(numberOfTeleporters > teleporterIndex, "the given index does not exist");
    //     // TODO: check that the caller has authority to delete the teleporter address
    //     bytes memory _teleporterBitcoinPubKey = teleportersList[teleporterIndex].teleporterBitcoinPubKey;
    //     delete teleportersList[teleporterIndex];
    //     teleportersList[teleporterIndex] = teleportersList[numberOfTeleporters - 1]; // fill the gap in the teleporter list
    //     delete teleportersList[teleportersList.length - 1];
    //     numberOfTeleporters = numberOfTeleporters - 1;
    //     require(updateRedeemScriptHash(), "teleporter address is not correct");
    //     require(updateMultisigAddress(), "teleporter address is not correct");
    //     IERC20(TeleportDAOToken).transfer(msg.sender, requiredLockedAmount*(100-unlockFee)/100);
    //     lastUnlock = block.number;
    //     emit RemoveTeleporter(_teleporterBitcoinPubKey, msg.sender, requiredLockedAmount*(100-unlockFee)/100);
    //     return true;
    // }

    // function isTeleporter (address teleporter, uint index) external override view returns(bool) {
    //     if (teleportersList[index].teleporterAddress == teleporter) {
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }

    // function updateRedeemScriptHash() internal returns(bool) { // tested
    //     bytes1 constantOPCODE = 0x21;
    //     bytes1 multisigOPCODE = 0xae;
    //     uint numberOfRequiredSignatures;
    //     if (numberOfTeleporters == 1) {
    //         numberOfRequiredSignatures = 1;
    //     } else {
    //         numberOfRequiredSignatures = 2*numberOfTeleporters/3;
    //     }
    //     bytes1 _numberOfTeleporters = findOPCODE(numberOfTeleporters);
    //     bytes1 _numberOfRequiredSignatures = findOPCODE(numberOfRequiredSignatures);
    //     redeemScript = abi.encodePacked(_numberOfRequiredSignatures);
    //     for (uint i = 0; i < numberOfTeleporters; i++) {
    //         redeemScript = abi.encodePacked(redeemScript, constantOPCODE, teleportersList[i].teleporterBitcoinPubKey);
    //     }
    //     redeemScript = abi.encodePacked(redeemScript, _numberOfTeleporters, multisigOPCODE);
    //     redeemScriptHash =  address(uint160(bytes20(doubleHash(redeemScript))));
    //     return true;
    // }

    // function updateMultisigAddress() internal returns(bool) {
    //     bytes memory desiredResult1;
    //     bytes memory desiredResult2;
    //     bytes memory desiredResult3;
    //     bytes memory desiredResult4;
    //     bytes memory result;
    //     address _result;
    //     // step 1
    //     bytes1 temp1 = 0xc4; // for btc testnet
    //     desiredResult1 = abi.encodePacked(temp1, redeemScriptHash);
    //     // step 2
    //     bytes32 temp32 = sha256(abi.encodePacked(sha256(desiredResult1)));
    //     desiredResult2 = abi.encodePacked(temp32[0], temp32[1], temp32[2], temp32[3]);
    //     // step 3
    //     desiredResult3 = abi.encodePacked(desiredResult1, desiredResult2);
    //     multisigAddressBeforeEncoding = desiredResult3;
    //     // step 4
    //     desiredResult4 = decTo58(hexToDec(desiredResult3)); // the result is not UTF-8 encoded
    //     result = revertBytes(desiredResult4);
    //     assembly {
    //         _result := mload(add(result, 20))
    //     }
    //     multisigAddress = _result;
    //     // step 5
    //     // step 6
    //     return true;
    // }

    // function slashTeleporters (uint bitcoinAmount, address recipient) external override {
    //     require(msg.sender == ccBurnRouter, "message sender is not correct");
    //     address[] memory path = new address[](2);
    //     path[0] = TeleportDAOToken;
    //     path[1] = wrappedBitcoin;
    //     uint[] memory neededTDT = IExchangeRouter(exchangeRouter).getAmountsIn(
    //         bitcoinAmount,
    //         path
    //     );
    //     IERC20(TeleportDAOToken).approve(exchangeRouter, neededTDT[0]);
    //     uint deadline = block.number + 1;
    //     IExchangeRouter(exchangeRouter).swapTokensForExactTokens(
    //         bitcoinAmount, // amount out
    //         neededTDT[0], // amount in
    //         path,
    //         recipient,
    //         deadline
    //     );
    // }

    // function hexToDec(bytes memory input) internal returns(uint) {
    //     uint len = input.length;
    //     uint result;
    //     for (uint i = 0; i < len; i++) {
    //         result = result*(256) + uint8(input[i]);
    //     }
    //     return result;
    // }

    // function decTo58 (uint input) internal returns(bytes memory) {
    //     bytes memory result;
    //     uint temp;
    //     while (input > 0) {
    //         temp = input%58;
    //         result = abi.encodePacked(result, ALPHABET[temp]);
    //         input = input/58;
    //     }
    //     return result;
    // }

    // function findOPCODE(uint input) internal returns(bytes1 data) {
    //     if (input == 1) return 0x51;
    //     if (input == 2) return 0x52;
    //     if (input == 3) return 0x53;
    //     if (input == 4) return 0x54;
    //     if (input == 5) return 0x55;
    //     if (input == 6) return 0x56;
    //     if (input == 7) return 0x57;
    //     if (input == 8) return 0x58;
    //     if (input == 9) return 0x59;
    //     if (input == 10) return 0x5a;
    //     if (input == 11) return 0x5b;
    //     if (input == 12) return 0x5c;
    //     if (input == 13) return 0x5d;
    //     if (input == 14) return 0x5e;
    //     if (input == 15) return 0x5f;
    //     if (input == 16) return 0x60;
    // }
    // // bitcoin double hash function
    // function doubleHash (bytes memory input) internal returns(bytes20) {
    //     bytes32 inputHash1 = sha256(input);
    //     bytes20 inputHash2 = ripemd160(abi.encodePacked(inputHash1));
    //     return inputHash2;
    // }

    // function revertBytes32 (bytes32 input) internal returns(bytes32) {
    //     bytes memory temp;
    //     bytes32 result;
    //     for (uint i = 0; i < 32; i++) {
    //         temp = abi.encodePacked(temp, input[31-i]);
    //     }
    //     assembly {
    //         result := mload(add(temp, 32))
    //     }
    //     return result;
    // }

    // function revertBytes (bytes memory input) internal returns(bytes memory) {
    //     bytes memory result;
    //     uint len = input.length;
    //     for (uint i = 0; i < len; i++) {
    //         result = abi.encodePacked(result, input[len-i-1]);
    //     }
    //     return result;
    // }

    // function concat(bytes memory a, bytes1 b) internal pure returns (bytes memory) {
    //     return abi.encodePacked(a, b);
    // }

}
