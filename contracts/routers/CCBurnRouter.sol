// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../libraries/BitcoinTxParser.sol";
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
    address public override treasuryAddress;
    mapping(address => burnRequest[]) public burnRequests;
    uint public override transferDeadline;
    uint public override lockerPercentageFee; // min amount is %0.01
    uint public override protocolPercentageFee; // min amount is %0.01
    uint public override bitcoinFee;

    /// @notice                             Handles cross-chain burn requests
    /// @dev                                Lockers use this contract for coordinating of burning wrapped tokens
    /// @param _relay                       Address of relay contract
    /// @param _lockers                     Address of lockers contract
    /// @param _treasuryAddress             Address of the treasury of the protocol
    /// @param _transferDeadline            Dealine of sending BTC to user
    /// @param _lockerPercentageFee         Percentage of tokens that user pays to lockers for burning
    /// @param _protocolPercentageFee       Percentage of tokens that user pays to protocol for burning 
    /// @param _bitcoinFee                  Transaction fee on Bitcoin that lockers pay
    constructor(
        address _relay,
        address _lockers,
        address _treasuryAddress,
        uint _transferDeadline,
        uint _lockerPercentageFee,
        uint _protocolPercentageFee,
        uint _bitcoinFee
    ) public {
        relay = _relay;
        lockers = _lockers;
        treasuryAddress = _treasuryAddress;
        transferDeadline = _transferDeadline;
        lockerPercentageFee = _lockerPercentageFee;
        protocolPercentageFee = _protocolPercentageFee;
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
    /// @param _treasuryAddress     The new treasury address
	function setTreasuryAddress(address _treasuryAddress) external override onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    /// @notice                             Changes deadline for sending tokens
    /// @dev                                Only owner can call this
    /// @param _transferDeadline            The new transfer deadline
    function setTransferDeadline(uint _transferDeadline) external override onlyOwner {
        transferDeadline = _transferDeadline;
    }

    /// @notice                             Changes locker percentage fee for burning tokens
    /// @dev                                Only owner can call this
    /// @param _lockerPercentageFee         The new locker percentage fee
    function setLockerPercentageFee(uint _lockerPercentageFee) external override onlyOwner {
        lockerPercentageFee = _lockerPercentageFee;
    }

    /// @notice                             Changes protocol percentage fee for burning tokens
    /// @dev                                Only owner can call this
    /// @param _protocolPercentageFee       The new protocol percentage fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        protocolPercentageFee = _protocolPercentageFee;
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
    /// @param _userBitcoinDecodedAddress   Address of user on Bitcoin
    /// @param _isScriptHash   		        Whether the user's Bitcoin address is script hash or pubKey hash
    /// @param _isSegwit			   	    Whether the user's Bitcoin address is Segwit or nonSegwit
    /// @param _lockerTargetAddress		    Locker's address on the target chain
    /// @return                             True if request is recorded successfully
    function ccBurn(
            uint _amount,
            address _userBitcoinDecodedAddress, 
            bool _isScriptHash,
            bool _isSegwit,
            address _lockerTargetAddress
        ) external nonReentrant override returns (bool) {
        ITeleBTC(teleBTC).transferFrom(msg.sender, address(this), _amount);
        uint remainedAmount = _getFee(_amount);
        // Burns remained wrapped tokens
        ITeleBTC(teleBTC).burn(remainedAmount);
        uint lastSubmittedHeight = IBitcoinRelay(relay).lastSubmittedHeight();
        _saveBurnRequest(
            _amount, 
            remainedAmount, 
            _userBitcoinDecodedAddress, 
            _isScriptHash, 
            _isSegwit, 
            lastSubmittedHeight, 
            _lockerTargetAddress
        );
        uint index = burnRequests[_lockerTargetAddress].length - 1;
        emit CCBurn(
            msg.sender,
            _userBitcoinDecodedAddress, 
            _isScriptHash,
            _isSegwit,
            _amount,
            remainedAmount, 
            _lockerTargetAddress, 
            index,
            burnRequests[_lockerTargetAddress][index].deadline
        );
        return true;
    }

    /// @notice                     Checks the correctness of burn proof
    /// @dev                        Makes isTransferred flag true for the paid requests
    /// @param _version             Version of the transaction containing the burn transaction
    /// @param _vin                 Inputs of the transaction containing the burn transaction
    /// @param _vout                Outputs of the transaction containing the burn transaction
    /// @param _locktime            Lock time of the transaction containing the burn transaction
    /// @param _blockNumber         Height of the block containing the burn transaction
    /// @param _intermediateNodes   Merkle inclusion proof for transaction containing the burn transaction
    /// @param _index               Index of transaction containing the burn transaction in the block
    /// @param _lockerTargetAddress Locker's address on the target chain that this burn request belong to
    /// @param _startIndex          Index to start searching for unpaid burn requests in the list
    /// @param _endIndex            Index to finish searching for unpaid burn requests in the list
    /// @return  
    function burnProof(
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes calldata _intermediateNodes,
        uint _index,
        address _lockerTargetAddress,
        uint _startIndex,
        uint _endIndex
    ) external nonReentrant override returns (bool) {
        // Checks the correction of input indices
        require(_startIndex >= 0 && _endIndex < burnRequests[_lockerTargetAddress].length
        , 'CCBurnRouter: burnProof wrong index input');
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
        uint parsedAmount;
        for (uint i = _startIndex; i <= _endIndex; i++) {
            // Checks that the request has not been paid and its deadline has not passed
            if (
                !burnRequests[_lockerTargetAddress][i].isTransferred &&
                burnRequests[_lockerTargetAddress][i].deadline >= block.number
            ) {
                (parsedAmount,) = BitcoinTxParser.parseAmountForP2PK( 
                    _vout, 
                    burnRequests[_lockerTargetAddress][i].userBitcoinDecodedAddress
                );
                if (burnRequests[_lockerTargetAddress][i].remainedAmount == parsedAmount)
                {
                    burnRequests[_lockerTargetAddress][i].isTransferred = true;
                    emit PaidCCBurn(
                        burnRequests[_lockerTargetAddress][i].sender, 
                        burnRequests[_lockerTargetAddress][i].userBitcoinDecodedAddress, 
                        parsedAmount, 
                        _lockerTargetAddress, 
                        i
                    );
                }
            }
        }
        return true;
    }

    /// @notice                     Slashes lockers if they did not paid burn request before its deadline
    /// @dev                        
    /// @param _lockerTargetAddress locker's target chain address that the unpaid request belongs to
    /// @param _indices             Array of indices of the requests for that locker
    /// @return                     True if dispute is successfull
    function disputeBurn(address _lockerTargetAddress, uint[] memory _indices) external nonReentrant override returns (bool) {
        for (uint i = 0; i < _indices.length; i++) { 
            require(
                !burnRequests[_lockerTargetAddress][_indices[i]].isTransferred,
                "CCBurnRouter: request has been paid before"
            );
            console.log("deadline");
            console.log(burnRequests[_lockerTargetAddress][_indices[i]].deadline);
            console.log("last height");
            console.log(IBitcoinRelay(relay).lastSubmittedHeight());
            require(
                burnRequests[_lockerTargetAddress][_indices[i]].deadline < IBitcoinRelay(relay).lastSubmittedHeight(),
                "CCBurnRouter: payback deadline has not passed yet"
            );
            // Slashes locker and sends the slashed amount to the user
            console.log("amount to be slashed:", burnRequests[_lockerTargetAddress][_indices[i]].amount);
            console.log("sender to get refunded:", burnRequests[_lockerTargetAddress][_indices[i]].sender);
            ILockers(lockers).slashLocker(
                _lockerTargetAddress,
                burnRequests[_lockerTargetAddress][_indices[i]].amount,
                burnRequests[_lockerTargetAddress][_indices[i]].sender
            );
        }
        return true;
    }

    /// @notice                           Records burn request of user  
    /// @param _amount                    Amount of wrapped token that user wants to burn
    /// @param _remainedAmount            Amount of wrapped token that actually gets burnt after deducting fees from the original value (_amount)
    /// @param _userBitcoinDecodedAddress User's Bitcoin address
    /// @param _isScriptHash              Whether user's Bitcoin address is script hash or not
    /// @param _isSegwit                  Whether user's Bitcoin address is segwit or nonSegwit
    /// @param _lastSubmittedHeight       Last block header height submitted on the relay contract
    /// @param _lockerTargetAddress       Locker's target chain address that the request belongs to
    function _saveBurnRequest(
        uint _amount,
        uint _remainedAmount,
        address _userBitcoinDecodedAddress,
        bool _isScriptHash,
        bool _isSegwit,
        uint _lastSubmittedHeight,
        address _lockerTargetAddress
    ) internal {
        burnRequest memory request;
        request.amount = _amount;
        request.remainedAmount = _remainedAmount;
        request.sender = msg.sender;
        request.userBitcoinDecodedAddress = _userBitcoinDecodedAddress;
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
    ) internal returns (bool) {
        // TODO: uncomment it
        // uint feeAmount;
        // ITeleBTC(feeTokenAddress).transferFrom(msg.sender, address(this), feeAmount);
        return IBitcoinRelay(relay).checkTxProof(
            _txId,
            _blockNumber,
            _intermediateNodes,
            _index
        );
    }

    /// @notice                      Checks inclusion of the transaction in the specified block 
    /// @dev                         Calls the relay contract to check Merkle inclusion proof
    /// @param _amount               Id of the transaction     
    /// @return                      Remained amount after reducing fees   
    function _getFee(
        uint _amount
    ) internal returns (uint) {
        // Calculates Locker fee
        uint lockerFee = _amount * lockerPercentageFee / 10000;
        // Calculates protocol fee
        uint protocolFee = _amount * protocolPercentageFee / 10000;
        uint remainedAmount = _amount - lockerFee - protocolFee - bitcoinFee;
        require(remainedAmount > 0, "CCBurnRouter: amount is too low");
        // Transfers protocol fee
        // ITeleBTC(teleBTC).transfer(treasuryAddress, protocolFee); TODO: uncomment when live
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
    ) internal returns (bytes32) {
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return _revertBytes32(inputHash2);
    }

    /// @notice                      Reverts a Bytes32 input
    /// @param _input                Bytes32 input that we want to revert    
    /// @return                      Reverted bytes32   
    function _revertBytes32(bytes32 _input) internal returns (bytes32) {
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