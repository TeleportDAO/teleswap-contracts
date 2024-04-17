// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@teleportdao/btc-evm-bridge/contracts/libraries/BitcoinHelper.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../routers/BurnRouterStorage.sol";

library BurnRouterLib {

   /// @notice Checks if all outputs of the transaction used to pay a cc burn request
    /// @dev  One output might return the remaining value to the locker
    /// @param _paidOutputCounter  Number of the tx outputs that pay a cc burn request
    /// @param _vout Outputs of a transaction
    /// @param _lockerLockingScript Locking script of locker
    /// @param _txId Transaction id
    function updateIsUsedAsBurnProof(
        mapping(bytes32 => bool) storage _isUsedAsBurnProof,
        uint _paidOutputCounter,
        bytes memory _vout,
        bytes memory _lockerLockingScript,
        bytes32 _txId
    ) external {
        uint parsedAmount = BitcoinHelper.parseValueHavingLockingScript(_vout, _lockerLockingScript);
        uint numberOfOutputs = BitcoinHelper.numberOfOutputs(_vout);

        if (parsedAmount != 0 && _paidOutputCounter + 1 == numberOfOutputs) {
            // One output sends the remaining value to locker
            _isUsedAsBurnProof[_txId] = true;
        } else if (_paidOutputCounter == numberOfOutputs) {
            // All output pays cc burn requests
            _isUsedAsBurnProof[_txId] = true;
        }
    }

    function disputeBurnHelper(
        mapping(address => BurnRouterStorage.burnRequest[]) storage burnRequests,
        address _lockerTargetAddress,
        uint _index, 
        uint _transferDeadline,
        uint _lastSubmittedHeight,
        uint _startingBlockNumber
    ) external {
        // Checks that locker has not provided burn proof
        require(
            !burnRequests[_lockerTargetAddress][_index].isTransferred,
            "BurnRouterLogic: already paid"
        );

        // Checks that payback deadline has passed
        require(
            burnRequests[_lockerTargetAddress][_index].deadline < _lastSubmittedHeight,
            "BurnRouterLogic: deadline not passed"
        );

        require(
            burnRequests[_lockerTargetAddress][_index].deadline > _startingBlockNumber + _transferDeadline,
            "BurnRouterLogic: old request"
        );

        // Sets "isTransferred = true" to prevent slashing the locker again
        burnRequests[_lockerTargetAddress][_index].isTransferred = true;
    }

    function disputeAndSlashLockerHelper(
        address lockers,
        bytes memory _lockerLockingScript,
        bytes4[] memory _versions, // [inputTxVersion, outputTxVersion]
        bytes[3] memory _inputOutputVinVout, // [_inputVin, _outputVin, _outputVout]
        mapping(bytes32 => bool) storage _isUsedAsBurnProof,
        uint _transferDeadline,
        address _relay,
        uint _startingBlockNumber,
        bytes32 _inputTxId,
        bytes4[] memory _locktimes, // [inputTxLocktime, outputTxLocktime]
        bytes memory _inputIntermediateNodes,
        uint[] memory _indexesAndBlockNumbers // [inputIndex, inputTxIndex, inputTxBlockNumber]
    ) external {
        // Checks if the locking script is valid
        require(
            ILockersManager(lockers).isLocker(_lockerLockingScript),
            "BurnRouterLogic: not locker"
        );

        // Checks input array sizes
        require(
            _versions.length == 2 &&
            _locktimes.length == 2 &&
            _indexesAndBlockNumbers.length == 3,
            "BurnRouterLogic: wrong inputs"
        );

        require(_indexesAndBlockNumbers[2] >= _startingBlockNumber, "BurnRouterLogic: old request");

        require(
            isConfirmed(
                _relay,
                _inputTxId,
                _indexesAndBlockNumbers[2], // Block number
                _inputIntermediateNodes,
                _indexesAndBlockNumbers[1] // Index of input tx in the block
            ),
            "BurnRouterLogic: not finalized"
        );

        /*
            Checks that input tx has not been provided as a burn proof
            note: if a locker executes a cc burn request but doesn't provide burn proof before deadline,
            we consider the transaction as a malicious tx
        */
        require(
            !_isUsedAsBurnProof[_inputTxId],
            "BurnRouterLogic: already used"
        );

        // prevents multiple slashing of locker
        _isUsedAsBurnProof[_inputTxId] = true;  

        // Checks that deadline for using the tx as burn proof has passed
        require(
            lastSubmittedHeight(_relay) > _transferDeadline + _indexesAndBlockNumbers[2],
            "BurnRouterLogic: deadline not passed"
        ); 

        // Extracts outpoint id and index from input tx
        (bytes32 _outpointId, uint _outpointIndex) = BitcoinHelper.extractOutpoint(
            _inputOutputVinVout[0],
            _indexesAndBlockNumbers[0] // Index of malicious input in input tx
        );

        // Checks that "outpoint tx id == output tx id"
        require(
            _outpointId == BitcoinHelper.calculateTxId(_versions[1], _inputOutputVinVout[1], _inputOutputVinVout[2], _locktimes[1]),
            "BurnRouterLogic: wrong output tx"
        );

        // Checks that _outpointIndex of _outpointId belongs to locker locking script
        require(
            keccak256(BitcoinHelper.getLockingScript(_inputOutputVinVout[2], _outpointIndex)) ==
            keccak256(_lockerLockingScript),
            "BurnRouterLogic: not for locker"
        );
    }

    function slashLockerHelper(
        bytes memory _lockerLockingScript,
        bytes4 _version,
        bytes memory _inputVin,
        uint _index,
        bytes memory _outputVin,
        bytes memory _outputVout,
        bytes4 _locktime
    ) external {
        // Extracts outpoint id and index from input tx
        (bytes32 _outpointId, uint _outpointIndex) = BitcoinHelper.extractOutpoint(
            _inputVin,
            _index // Index of malicious input in input tx
        );

        // Checks that "outpoint tx id == output tx id"
        require(
            _outpointId == BitcoinHelper.calculateTxId(_version, _outputVin, _outputVout, _locktime),
            "BurnRouterLogic: wrong output tx"
        );

        // Checks that _outpointIndex of _outpointId belongs to locker locking script
        require(
            keccak256(BitcoinHelper.getLockingScript(_outputVout, _outpointIndex)) ==
            keccak256(_lockerLockingScript),
            "BurnRouterLogic: not for locker"
        );

    }

    function burnProofHelper(
        uint256 _blockNumber,
        uint256 startingBlockNumber,
        bytes4 _locktime,
        address lockers,
        bytes memory _lockerLockingScript,
        uint _burnReqIndexesLength,
        uint _voutIndexesLength
    ) external {
        require(_blockNumber >= startingBlockNumber, "BurnRouterLogic: old request");
        // Checks that locker's tx doesn't have any locktime
        require(_locktime == bytes4(0), "BurnRouterLogic: non-zero lock time");

        // Checks if the locking script is valid
        require(
            ILockersManager(lockers).isLocker(_lockerLockingScript),
            "BurnRouterLogic: not locker"
        );

        require(
            _burnReqIndexesLength == _voutIndexesLength,
            "BurnRouterLogic: wrong indexes"
        );
    }

    /// @notice Checks inclusion of the transaction in the specified block
    /// @dev Calls the relay contract to check Merkle inclusion proof
    /// @param _relay Address of Relay contract
    /// @param _txId of the transaction
    /// @param _blockNumber Height of the block containing the transaction
    /// @param _intermediateNodes Merkle inclusion proof for the transaction
    /// @param _index Index of transaction in the block
    /// @return True if the transaction was included in the block
    function isConfirmed(
        address _relay,
        bytes32 _txId,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) public returns (bool) {
        // Finds fee amount
        uint feeAmount = getFinalizedBlockHeaderFee(_relay, _blockNumber);
        require(msg.value >= feeAmount, "BitcoinRelay: low fee");

        // Calls relay contract
        bytes memory data = Address.functionCallWithValue(
            _relay,
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint256,bytes,uint256)",
                _txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            feeAmount
        );

        //TODO?
        // Sends extra ETH back to msg.sender
        Address.sendValue(payable(msg.sender), msg.value - feeAmount);

        return abi.decode(data, (bool));
    }

    /// @notice Checks the user hash script to be valid (based on its type)
    function checkScriptTypeAndLocker(bytes memory _userScript, ScriptTypes _scriptType, address lockers, bytes calldata _lockerLockingScript) external view {
        if (_scriptType == ScriptTypes.P2PK || _scriptType == ScriptTypes.P2WSH || _scriptType == ScriptTypes.P2TR) {
            require(_userScript.length == 32, "BurnRouterLogic: invalid script");
        } else {
            require(_userScript.length == 20, "BurnRouterLogic: invalid script");
        }

        // Checks if the given locking script is locker
        require(
            ILockersManager(lockers).isLocker(_lockerLockingScript),
            "BurnRouterLogic: not locker"
        );
    }

    function lastSubmittedHeight(address _relay) public view returns (uint) {
        return IBitcoinRelay(_relay).lastSubmittedHeight();
    }

    function finalizationParameter(address _relay) external view returns (uint) {
        return IBitcoinRelay(_relay).finalizationParameter();
    }

    function getFinalizedBlockHeaderFee(address _relay, uint _blockNumber) public view returns (uint) {
        return IBitcoinRelay(_relay).getBlockHeaderFee(_blockNumber, 0);
    }
}