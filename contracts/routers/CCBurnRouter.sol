// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/NewTxHelper.sol";
import "./interfaces/ICCBurnRouter.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../lockers/interfaces/ILockers.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "hardhat/console.sol";

contract CCBurnRouter is ICCBurnRouter, Ownable, ReentrancyGuard {
    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override treasury;
    mapping(address => burnRequest[]) public burnRequests;
    mapping(bytes32 => bool) private isPaid;
    uint public override transferDeadline;
    uint public override protocolPercentageFee; // min amount is %0.01
    uint public override slasherPercentageReward; // min amount is %1
    uint public override bitcoinFee;

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
	function isTransferred(address _lockerTargetAddress, uint _index) external view override returns (bool) {
        return burnRequests[_lockerTargetAddress][_index].isTransferred;
    }

    /// @notice               Changes relay contract address
    /// @dev                  Only owner can call this
    /// @param _relay         The new relay contract address
    function setRelay(address _relay) external override onlyOwner {
        relay = _relay;
    }

    /// @notice               Changes lockers contract address
    /// @dev                  Only owner can call this
    /// @param _lockers       The new lockers contract address
    function setLockers(address _lockers) external override onlyOwner {
        lockers = _lockers;
    }

    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                     Changes protocol treasury address
    /// @dev                        Only owner can call this
    /// @param _treasury            The new treasury address
	function setTreasury(address _treasury) external override onlyOwner {
        treasury = _treasury;
    }

    /// @notice                             Changes deadline for sending tokens
    /// @dev                                Only owner can call this
    /// @param _transferDeadline            The new transfer deadline
    function setTransferDeadline(uint _transferDeadline) external override onlyOwner {
        transferDeadline = _transferDeadline;
    }

    /// @notice                             Changes protocol percentage fee for burning tokens
    /// @dev                                Only owner can call this
    /// @param _protocolPercentageFee       The new protocol percentage fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice                            Changes slasher percentage reward for disputing lockers
    /// @dev                               Only owner can call this
    /// @param _slasherPercentageReward    The new slasher percentage reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) external override onlyOwner {
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
    /// @param _userPubKeyHash   Address of user on Bitcoin
    /// @param _isScriptHash   		        Whether the user's Bitcoin address is script hash or pubKey hash
    /// @param _isSegwit			   	    Whether the user's Bitcoin address is Segwit or nonSegwit
    /// @param _lockerScriptHash	Locker's address on Bitcoin
    /// @return                             True if request is recorded successfully
    function ccBurn(
            uint _amount,
            address _userPubKeyHash, 
            bool _isScriptHash,
            bool _isSegwit,
            address _lockerScriptHash
        ) external nonReentrant override returns (bool) {
        // Checks if the locker address is valid
        require(
            ILockers(lockers).isLocker(_lockerScriptHash),
            "CCBurnRouter: locker address is not valid"
        );

        // Transfers users's teleBTC
        ITeleBTC(teleBTC).transferFrom(msg.sender, address(this), _amount);

        uint remainedAmount = _getFee(
            _amount, 
            ILockers(lockers).lockerTargetAddress(_lockerScriptHash)
        );
        
        // Burns remained wrapped tokens
        ITeleBTC(teleBTC).approve(lockers, remainedAmount);
        uint burntAmount = ILockers(lockers).burn(_lockerScriptHash, remainedAmount);

        // Get the target address of the locker from its Bitcoin address
        address _lockerTargetAddress = ILockers(lockers)
            .lockerTargetAddress(_lockerScriptHash);

        _saveBurnRequest(
            _amount, 
            burntAmount, 
            _userPubKeyHash, 
            _isScriptHash, 
            _isSegwit, 
            IBitcoinRelay(relay).lastSubmittedHeight(), 
            _lockerTargetAddress
        );

        emit CCBurn(
            msg.sender,
            _userPubKeyHash, 
            _isScriptHash,
            _isSegwit,
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
    /// @param _lockerScriptHash Locker's address on Bitcoin that this burn request belongs to
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
        address _lockerScriptHash,
        uint _startIndex,
        uint _endIndex
    ) external payable nonReentrant override returns (bool) {
        // Get the target address of the locker from its script hash
        address _lockerTargetAddress = ILockers(lockers)
            .lockerTargetAddress(_lockerScriptHash);

        // Checks the correctness of input indices
        require(
            _endIndex < burnRequests[_lockerTargetAddress].length && 
            _startIndex<= _endIndex,
            'CCBurnRouter: burnProof wrong index input'
        );

        // Checks if the locker address is valid
        require(
            ILockers(lockers).isLocker(_lockerScriptHash),
            "CCBurnRouter: locker address is not valid"
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
        _updateIsPaid(paidOutputCounter, _vout, _lockerScriptHash, txId);
        
        return true;
    }

    /// @notice                             Slashes lockers if they did not paid burn request before its deadline
    /// @dev                        
    /// @param _lockerScriptHash locker's Bitcoin address that the unpaid request belongs to
    /// @param _indices                     Array of indices of the requests for that locker
    /// @return                             True if dispute is successfull
    function disputeBurn(address _lockerScriptHash, uint[] memory _indices) external nonReentrant override returns (bool) {
        // Checks if the locker address is valid
        require(ILockers(lockers).isLocker(_lockerScriptHash),
        "CCBurnRouter: locker address is not valid");
        // Get the target address of the locker from its Bitcoin address
        address _lockerTargetAddress = ILockers(lockers)
            .lockerTargetAddress(_lockerScriptHash);
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
    /// @param _lockerScriptHash                Suspicious locker's script hash
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
        address _lockerScriptHash,
        uint _inputIndex,
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes calldata _intermediateNodes,
        uint _index
    ) external payable nonReentrant override returns (bool) {
        // Checks if the locker address is valid
        require(
            ILockers(lockers).isLocker(_lockerScriptHash),
            "CCBurnRouter: locker address is not valid"
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
            .lockerTargetAddress(_lockerScriptHash);
        bytes memory lockerRedeemScript = ILockers(lockers)
            .getLockerRedeemScript(_lockerTargetAddress);
        require(
            _isTxFromLocker(_vin, _inputIndex, lockerRedeemScript),
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
        uint totalValue = NewTxHelper.parseTotalValue(_vout);

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
    ) internal returns (uint paidOutputCounter) {
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
                (parsedAmount,) = NewTxHelper.parseValueAndData( 
                    _vout, 
                    burnRequests[_lockerTargetAddress][i].userPubKeyHash
                );

                if (burnRequests[_lockerTargetAddress][i].remainedAmount == parsedAmount) {
                    burnRequests[_lockerTargetAddress][i].isTransferred = true;
                    paidOutputCounter = paidOutputCounter + 1;
                    emit PaidCCBurn(
                        burnRequests[_lockerTargetAddress][i].sender, 
                        burnRequests[_lockerTargetAddress][i].userPubKeyHash, 
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
    /// @param _lockerScriptHash                Address of the locker on Bitcoin    
    /// @param _txId                            Transaction Id of the transaction    
    function _updateIsPaid(
        uint _paidOutputCounter, 
        bytes memory _vout, 
        address _lockerScriptHash,
        bytes32 _txId
        ) internal {
        uint parsedAmount;
        (parsedAmount,) = NewTxHelper.parseValueAndData(_vout, _lockerScriptHash);
        if (parsedAmount != 0 &&
            _paidOutputCounter + 1 == NewTxHelper.numberOfOutputs(_vout)) {
            isPaid[_txId] = true;
        } else if (parsedAmount == 0 &&
            _paidOutputCounter == NewTxHelper.numberOfOutputs(_vout)) {
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
    ) internal view returns (bool) {
        bytes memory scriptSig;
        bytes memory txInputAddress;
        scriptSig = NewTxHelper.parseInputScriptSig(_vin, _inputIndex);
        txInputAddress = NewTxHelper.sliceBytes(
            scriptSig, 
            scriptSig.length - _lockerRedeemScript.length, 
            scriptSig.length - 1
        );
        return txInputAddress.length == _lockerRedeemScript.length &&
            keccak256(txInputAddress) == keccak256(_lockerRedeemScript);
    }

    /// @notice                           Records burn request of user  
    /// @param _amount                    Amount of wrapped token that user wants to burn
    /// @param _remainedAmount            Amount of wrapped token that actually gets burnt after deducting fees from the original value (_amount)
    /// @param _userPubKeyHash User's Bitcoin address
    /// @param _isScriptHash              Whether user's Bitcoin address is script hash or not
    /// @param _isSegwit                  Whether user's Bitcoin address is segwit or nonSegwit
    /// @param _lastSubmittedHeight       Last block header height submitted on the relay contract
    /// @param _lockerTargetAddress       Locker's target chain address that the request belongs to
    function _saveBurnRequest(
        uint _amount,
        uint _remainedAmount,
        address _userPubKeyHash,
        bool _isScriptHash,
        bool _isSegwit,
        uint _lastSubmittedHeight,
        address _lockerTargetAddress
    ) internal {
        burnRequest memory request;
        request.amount = _amount;
        request.remainedAmount = _remainedAmount;
        request.sender = msg.sender;
        request.userPubKeyHash = _userPubKeyHash;
        request.isScriptHash = _isScriptHash;
        request.isSegwit = _isSegwit;
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
        uint feeAmount = IBitcoinRelay(relay).getFinalizedHeaderFee(_blockNumber);
        require(msg.value >= feeAmount, "CCTransferRouter: relay fee is not sufficient");
        
        // Calls relay with msg.value
        (bool success, bytes memory data) = payable(relay).call{value: msg.value}(
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint256,bytes,uint256)", 
                _txId, 
                _blockNumber,
                _intermediateNodes,
                _index
            )
        );

        // Checks that call was successful
        require(success, "CCTransferRouter: calling relay was not successful");

        // Sends extra ETH back to msg.sender
        (bool _success,) = payable(msg.sender).call{value: (msg.value - feeAmount)}("");
        require(_success, "CCTransferRouter: sending remained ETH was not successful");

        // Returns result
        bytes32 _data;
        assembly {
            _data := mload(add(data, 32))
        }
        return _data == bytes32(0) ? false : true;
    }

    /// @notice                      Checks inclusion of the transaction in the specified block 
    /// @dev                         Calls the relay contract to check Merkle inclusion proof
    /// @param _amount               Id of the transaction
    /// @param _lockerTargetAddress  Id of the transaction          
    /// @return                      Remained amount after reducing fees   
    function _getFee(
        uint _amount,
        address _lockerTargetAddress
    ) internal returns (uint) {
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
        bytes calldata _vout,
        bytes4 _locktime
    ) internal pure returns (bytes32) {
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