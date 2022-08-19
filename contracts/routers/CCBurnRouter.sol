// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/TxHelper.sol";
import "./interfaces/ICCBurnRouter.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../lockers/interfaces/ILockers.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "hardhat/console.sol";

contract CCBurnRouter is ICCBurnRouter, Ownable, ReentrancyGuard {

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CCBurnRouter: address is zero");
        _;
    }

    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override treasury;
    mapping(address => burnRequest[]) public burnRequests; // Mapping from locker target address to assigned burn requests
    mapping(bytes32 => bool) private isPaid;
    uint public override transferDeadline;
    uint public override protocolPercentageFee; // Min amount is %0.01
    uint public override slasherPercentageReward; // Min amount is %1
    uint public override bitcoinFee; // Fee of submitting a tx on Bitcoin

    /// @notice                             Handles cross-chain burn requests
    /// @dev                                Lockers use this contract for coordinating of burning wrapped tokens
    /// @param _relay                       Address of relay contract
    /// @param _lockers                     Address of lockers contract
    /// @param _treasury                    Address of the treasury of the protocol
    /// @param _transferDeadline            Dealine of sending BTC to user
    /// @param _protocolPercentageFee       Percentage of tokens that user pays to protocol for burning
    /// @param _bitcoinFee                  Transaction fee on Bitcoin that lockers pay
    constructor(
        address _relay,
        address _lockers,
        address _treasury,
        uint _transferDeadline,
        uint _protocolPercentageFee,
        uint _slasherPercentageReward,
        uint _bitcoinFee
    ) {
        relay = _relay;
        lockers = _lockers;
        treasury = _treasury;
        transferDeadline = _transferDeadline;
        protocolPercentageFee = _protocolPercentageFee;
        slasherPercentageReward = _slasherPercentageReward;
        bitcoinFee = _bitcoinFee;
    }

    /// @notice                         Shows if a burn request has been done or not
    /// @param _lockerTargetAddress		Locker's address on the target chain
    /// @param _index                   The index number of the request for the locker
    function isTransferred(
        address _lockerTargetAddress, 
        uint _index
    ) external view override returns (bool) {
        return burnRequests[_lockerTargetAddress][_index].isTransferred;
    }

    /// @notice               Changes relay contract address
    /// @dev                  Only owner can call this
    /// @param _relay         The new relay contract address
    function setRelay(address _relay) external nonZeroAddress(_relay) override onlyOwner {
        relay = _relay;
    }

    /// @notice               Changes lockers contract address
    /// @dev                  Only owner can call this
    /// @param _lockers       The new lockers contract address
    function setLockers(address _lockers) external nonZeroAddress(_lockers) override onlyOwner {
        lockers = _lockers;
    }

    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external nonZeroAddress(_teleBTC) override onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                     Changes protocol treasury address
    /// @dev                        Only owner can call this
    /// @param _treasury            The new treasury address
    function setTreasury(address _treasury) external nonZeroAddress(_treasury) override onlyOwner {
        treasury = _treasury;
    }

    /// @notice                             Changes deadline for sending tokens
    /// @dev                                Only owner can call this
    /// @param _transferDeadline            The new transfer deadline
    function setTransferDeadline(uint _transferDeadline) external override onlyOwner {
        uint _finalizationParameter = IBitcoinRelay(relay).finalizationParameter();
        // Gives lockers enough time to pay cc burn requests
        require(_transferDeadline > _finalizationParameter, "CCBurnRouter: transfer deadline is too low");
        transferDeadline = _transferDeadline;
    }

    /// @notice                             Changes protocol percentage fee for burning tokens
    /// @dev                                Only owner can call this
    /// @param _protocolPercentageFee       The new protocol percentage fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        require(10000 >= _protocolPercentageFee, "CCBurnRouter: protocol fee is out of range");
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice                            Changes slasher percentage reward for disputing lockers
    /// @dev                               Only owner can call this
    /// @param _slasherPercentageReward    The new slasher percentage reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) external override onlyOwner {
        require(100 >= _slasherPercentageReward, "CCBurnRouter: slasher fee is out of range");
        slasherPercentageReward = _slasherPercentageReward;
    }

    /// @notice                       Changes Bitcoin transaction fee
    /// @dev                          Only owner can call this
    /// @param _bitcoinFee            The new Bitcoin transaction fee
    function setBitcoinFee(uint _bitcoinFee) external override onlyOwner {
        bitcoinFee = _bitcoinFee;
    }

    /// @notice                             Burns wrapped tokens and records the burn request
    /// @dev                                After submitting the burn request, lockers have a limited time to send BTC
    /// @param _amount                      Amount of wrapped tokens that user wants to burn
    /// @param _userLockingScript           Address of user on Bitcoin
    /// @param _lockerLockingScript	        Locker's address on Bitcoin
    /// @return                             True if request is recorded successfully
    function ccBurn(
        uint _amount,
        bytes memory _userLockingScript,
        bytes calldata _lockerLockingScript
    ) external nonReentrant override returns (bool) {
        // Checks if the given locking script is locker
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        // Gets the target address of locker
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        // Transfers users's teleBTC
        ITeleBTC(teleBTC).transferFrom(msg.sender, address(this), _amount);

        uint remainedAmount = _getFees(
            _amount,
            _lockerTargetAddress
        );

        // Burns remained teleBTC
        ITeleBTC(teleBTC).approve(lockers, remainedAmount);
        uint burntAmount = ILockers(lockers).burn(_lockerLockingScript, remainedAmount);

        _saveBurnRequest(
            _amount,
            burntAmount,
            _userLockingScript,
            IBitcoinRelay(relay).lastSubmittedHeight(),
            _lockerTargetAddress
        );

        emit CCBurn(
            msg.sender,
            _userLockingScript,
            _amount,
            burntAmount,
            _lockerTargetAddress,
            burnRequests[_lockerTargetAddress].length - 1, // index
            burnRequests[_lockerTargetAddress][burnRequests[_lockerTargetAddress].length - 1].deadline
        );

        return true;
    }

    /// @notice                             Checks the correctness of burn proof
    /// @dev                                Makes isTransferred flag true for the paid requests
    /// @param _version                     Version of the transaction containing the burn transaction
    /// @param _vin                         Inputs of the transaction containing the burn transaction
    /// @param _vout                        Outputs of the transaction containing the burn transaction
    /// @param _locktime                    Lock time of the transaction containing the burn transaction
    /// @param _blockNumber                 Height of the block containing the burn transaction
    /// @param _intermediateNodes           Merkle inclusion proof for transaction containing the burn transaction
    /// @param _index                       Index of transaction containing the burn transaction in the block
    /// @param _lockerLockingScript Locker's address on Bitcoin that this burn request belongs to
    /// @param _startIndex                  Index to start searching for unpaid burn requests in the list
    /// @param _endIndex                    Index to finish searching for unpaid burn requests in the list
    /// @return
    function burnProof(
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes calldata _intermediateNodes,
        uint _index,
        bytes memory _lockerLockingScript,
        uint _startIndex,
        uint _endIndex
    ) external payable nonReentrant override returns (bool) {
        // Get the target address of the locker from its locking script
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        // Checks the correctness of input indices
        require(
            _endIndex < burnRequests[_lockerTargetAddress].length &&
            _startIndex<= _endIndex,
            'CCBurnRouter: burnProof wrong index input'
        );

        // Checks if the locker address is valid
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        // Checks inclusion of transaction
        bytes32 txId = _calculateTxId(_version, _vin, _vout, _locktime);
        require(
            _isConfirmed(
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "CCBurnRouter: transaction has not finalized yet"
        );

        // Checks the paid burn requests
        uint paidOutputCounter = _checkPaidBurnRequests(
            _lockerTargetAddress,
            _vout,
            _startIndex,
            _endIndex
        );

        // Checks if there is an output that goes back to the locker
        _updateIsPaid(paidOutputCounter, _vout, _lockerLockingScript, txId);

        return true;
    }

    /// @notice                             Slashes lockers if they did not paid burn request before its deadline
    /// @dev
    /// @param _lockerLockingScript locker's Bitcoin address that the unpaid request belongs to
    /// @param _indices                     Array of indices of the requests for that locker
    /// @return                             True if dispute is successfull
    function disputeBurn(bytes calldata _lockerLockingScript, uint[] memory _indices) external nonReentrant override returns (bool) {
        // Checks if the locker address is valid
        require(ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker");
        // Get the target address of the locker from its Bitcoin address
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);
        // Goes through provided indexes of burn requests to see if locker should be slashed
        for (uint i = 0; i < _indices.length; i++) {
            require(
                !burnRequests[_lockerTargetAddress][_indices[i]].isTransferred,
                "CCBurnRouter: request has been paid before"
            );
            require(
                burnRequests[_lockerTargetAddress][_indices[i]].deadline < IBitcoinRelay(relay).lastSubmittedHeight(),
                "CCBurnRouter: payback deadline has not passed yet"
            );

            // Slashes locker and sends the slashed amount to the user
            ILockers(lockers).slashLocker(
                _lockerTargetAddress,
                burnRequests[_lockerTargetAddress][_indices[i]].amount*slasherPercentageReward/100, // Slasher reward
                msg.sender, // Slasher address
                burnRequests[_lockerTargetAddress][_indices[i]].amount,
                burnRequests[_lockerTargetAddress][_indices[i]].sender
            );
        }
        return true;
    }

    /// @notice                                 Slashes a locker if they issue a tx that doesn't match any burn request
    /// @dev
    /// @param _lockerLockingScript             Suspicious locker's locking script
    /// @param _inputIndex                      Index of the input in vin that is from the locker
    /// @param _version                         Version of the malicious transaction
    /// @param _vin                             Inputs of the malicious transaction
    /// @param _vout                            Outputs of the malicious transaction
    /// @param _locktime                        Lock time of the malicious transaction
    /// @param _blockNumber                     The block number in which the malicious tx has happened
    /// @param _intermediateNodes               Merkle inclusion proof for the malicious transaction
    /// @param _index                           Index of transaction containing the malicious tx
    /// @return                                 True if dispute is successfull
    function disputeLocker(
        bytes memory _lockerLockingScript,
        uint _inputIndex,
        bytes4 _version,
        bytes memory _vin,
        bytes memory _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) external payable nonReentrant override returns (bool) {
        // Checks if the locker address is valid
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        // Checks if the provided transaction is valid:
        // 1. Checks inclusion of transaction
        bytes32 txId = _calculateTxId(_version, _vin, _vout, _locktime);
        require(
            _isConfirmed(
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "CCBurnRouter: transaction is not finalized"
        );

        // 2. Check if the transaction belongs to the locker
        // First get the target address of the locker from its Bitcoin address
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        require(
            _isTxFromLocker(_vin, _inputIndex, _lockerLockingScript),
            "CCBurnRouter: transaction doesn't belong to locker"
        );

        // 3. Check if transaction is not for any burn request
        // note: if the deadline for the transaction has passed and no proof has been provided
        // for it so that isPaid is still false for it, we assume the transaction was malicious
        require(
            !isPaid[txId],
            "CCBurnRouter: transaction has been paid before"
        );
        require(
            IBitcoinRelay(relay).lastSubmittedHeight() > (transferDeadline + _blockNumber),
            "CCBurnRouter: payback deadline has not passed yet"
        );

        // Finds total outputs value
        uint totalValue = TxHelper.parseTotalValue(_vout);

        // Slashes locker
        ILockers(lockers).slashLocker(
            _lockerTargetAddress,
            totalValue*slasherPercentageReward/100, // Slasher reward
            msg.sender, // Slasher address
            totalValue,
            lockers
        );

        // Emit the event
        emit LockerDispute(
            _lockerTargetAddress,
            _blockNumber,
            txId
        );

        return true;
    }

    /// @notice                             Checks the burn requests that get paid by this transaction
    /// @dev                                Counts the number of outputs that are paying a burn request
    /// @param _lockerTargetAddress         Address of the locker on the target chain
    /// @param _vout                        Outputs of a transaction
    /// @param _startIndex                  Index to start searching for unpaid burn requests in the list
    /// @param _endIndex                    Index to finish searching for unpaid burn requests in the list
    /// @return                             paidOutputCounter that is the number of the outputs that paid a burn request
    function _checkPaidBurnRequests(
        address _lockerTargetAddress,
        bytes memory _vout,
        uint _startIndex,
        uint _endIndex
    ) private returns (uint paidOutputCounter) {
        uint parsedAmount;
        // Below variable is for checking that every output in vout is related to a burn request
        // so that we can set isPaid = true for the whole txId
        paidOutputCounter = 0;
        for (uint i = _startIndex; i <= _endIndex; i++) {
            // Checks that the request has not been paid and its deadline has not passed
            if (
                !burnRequests[_lockerTargetAddress][i].isTransferred &&
                burnRequests[_lockerTargetAddress][i].deadline >= block.number
            ) {
                
                parsedAmount = TxHelper.parseOutputValue(
                    _vout,
                    burnRequests[_lockerTargetAddress][i].userLockingScript
                );
                
                if (burnRequests[_lockerTargetAddress][i].burntAmount == parsedAmount) {
                    burnRequests[_lockerTargetAddress][i].isTransferred = true;
                    paidOutputCounter = paidOutputCounter + 1;
                    emit PaidCCBurn(
                        burnRequests[_lockerTargetAddress][i].sender,
                        burnRequests[_lockerTargetAddress][i].userLockingScript,
                        parsedAmount,
                        _lockerTargetAddress,
                        i
                    );
                }
            }
        }
    }

    /// @notice                                 Checks if all outputs of the transaction paid a burn request
    /// @dev                                    One output might return the remaining value to the locker
    /// @param _paidOutputCounter               Number of the outputs that pay a burn request
    /// @param _vout                            Outputs of a transaction
    /// @param _lockerLockingScript                Address of the locker on Bitcoin
    /// @param _txId                            Transaction Id of the transaction
    function _updateIsPaid(
        uint _paidOutputCounter,
        bytes memory _vout,
        bytes memory _lockerLockingScript,
        bytes32 _txId
    ) private {
        uint parsedAmount;
        parsedAmount = TxHelper.parseOutputValue(_vout, _lockerLockingScript);

        if (
            parsedAmount != 0 &&
            _paidOutputCounter + 1 == TxHelper.numberOfOutputs(_vout)
        ) {
            isPaid[_txId] = true;
        } else if (
            parsedAmount == 0 &&
            _paidOutputCounter == TxHelper.numberOfOutputs(_vout)
        ) {
            isPaid[_txId] = true;
        }
    }

    /// @notice                      Checks if the locker is among transaction senders
    /// @param _vin                  Inputs of the transaction
    /// @param _inputIndex           Index of the input that is from the locker
    /// @param _lockerRedeemScript   Address of the locker on Bitcoin
    /// @return                      True if the transaction sender is the locker
    function _isTxFromLocker(
        bytes memory _vin,
        uint _inputIndex,
        bytes memory _lockerRedeemScript
    ) private view returns (bool) {
        bytes memory scriptSig;
        bytes memory txInputAddress;
        scriptSig = TxHelper.parseInputScriptSig(_vin, _inputIndex);
        txInputAddress = TxHelper.sliceBytes(
            scriptSig,
            scriptSig.length - _lockerRedeemScript.length,
            scriptSig.length - 1
        );
        return txInputAddress.length == _lockerRedeemScript.length &&
        keccak256(txInputAddress) == keccak256(_lockerRedeemScript);
    }

    /// @notice                           Records burn request of user
    /// @param _amount                    Amount of wrapped token that user wants to burn
    /// @param _burntAmount            Amount of wrapped token that actually gets burnt after deducting fees from the original value (_amount)
    /// @param _userLockingScript         User's Bitcoin address
    /// @param _lastSubmittedHeight       Last block header height submitted on the relay contract
    /// @param _lockerTargetAddress       Locker's target chain address that the request belongs to
    function _saveBurnRequest(
        uint _amount,
        uint _burntAmount,
        bytes memory _userLockingScript,
        uint _lastSubmittedHeight,
        address _lockerTargetAddress
    ) private {
        burnRequest memory request;
        request.amount = _amount;
        request.burntAmount = _burntAmount;
        request.sender = msg.sender;
        request.userLockingScript = _userLockingScript;
        request.deadline = _lastSubmittedHeight + transferDeadline;
        request.isTransferred = false;
        burnRequests[_lockerTargetAddress].push(request);
    }

    /// @notice                         Checks inclusion of the transaction in the specified block
    /// @dev                            Calls the relay contract to check Merkle inclusion proof
    /// @param _txId                    Id of the transaction
    /// @param _blockNumber             Height of the block containing the transaction
    /// @param _intermediateNodes       Merkle inclusion proof for the transaction
    /// @param _index                   Index of transaction in the block
    /// @return                         True if the transaction was included in the block
    function _isConfirmed(
        bytes32 _txId,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) private returns (bool) {
        // Finds fee amount
        uint feeAmount = IBitcoinRelay(relay).getBlockHeaderFee(_blockNumber, 0);
        require(msg.value >= feeAmount, "CCBurnRouter: relay fee is not sufficient");

        // Calls relay contract
        bytes memory data = Address.functionCallWithValue(
            relay,
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint256,bytes,uint256)",
                _txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            msg.value
        );

        // Sends extra ETH back to msg.sender
        Address.sendValue(payable(msg.sender), msg.value - feeAmount);

        return abi.decode(data, (bool));
    }

    /// @notice                      Checks inclusion of the transaction in the specified block
    /// @dev                         Calls the relay contract to check Merkle inclusion proof
    /// @param _amount               Id of the transaction
    /// @param _lockerTargetAddress  Id of the transaction
    /// @return                      Remained amount after reducing fees
    function _getFees(
        uint _amount,
        address _lockerTargetAddress
    ) private returns (uint) {
        // Calculates protocol fee
        uint protocolFee = _amount*protocolPercentageFee/10000;

        uint remainedAmount = _amount - protocolFee - bitcoinFee;
        require(remainedAmount > 0, "CCBurnRouter: amount is too low");

        // Transfers protocol fee
        ITeleBTC(teleBTC).transfer(treasury, protocolFee);

        // Transfers bitcoin fee to locker
        ITeleBTC(teleBTC).transfer(_lockerTargetAddress, bitcoinFee);

        return remainedAmount;
    }

    /// @notice                      Calculates the required transaction Id from the transaction details
    /// @dev                         Calculates the hash of transaction details two consecutive times
    /// @param _version              Version of the transaction
    /// @param _vin                  Inputs of the transaction
    /// @param _vout                 Outputs of the transaction
    /// @param _locktime             Lock time of the transaction
    /// @return                      Transaction Id of the required transaction
    function _calculateTxId(
        bytes4 _version,
        bytes memory _vin,
        bytes memory _vout,
        bytes4 _locktime
    ) private pure returns (bytes32) {
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return _revertBytes32(inputHash2);
    }

    /// @notice                      Reverts a Bytes32 input
    /// @param _input                Bytes32 input that we want to revert
    /// @return                      Reverted bytes32
    function _revertBytes32(bytes32 _input) internal pure returns (bytes32) {
        bytes memory temp;
        bytes32 result;
        for (uint i = 0; i < 32; i++) {
            temp = abi.encodePacked(temp, _input[31-i]);
        }
        assembly {
            result := mload(add(temp, 32))
        }
        return result;
    }

}