// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

library BurnRouterLib {

    function disputeLockerHelper(
        mapping(bytes32 => bool) storage _isUsedAsBurnProof,
        uint _transferDeadline,
        address _relay,
        uint _startingBlockNumber,
        bytes32 _inputTxId,
        bytes4[] memory _versions, // [inputTxVersion, outputTxVersion]
        bytes4[] memory _locktimes, // [inputTxLocktime, outputTxLocktime]
        bytes memory _inputIntermediateNodes,
        uint[] memory _indexesAndBlockNumbers // [inputIndex, inputTxIndex, inputTxBlockNumber]
    ) external {
        
        // Checks input array sizes
        require(
            _versions.length == 2 &&
            _locktimes.length == 2 &&
            _indexesAndBlockNumbers.length == 3,
            "CCBurnRouter: wrong inputs"
        );

        require(_indexesAndBlockNumbers[2] >= _startingBlockNumber, "CCBurnRouter: old request");

        require(
            isConfirmed(
                _relay,
                _inputTxId,
                _indexesAndBlockNumbers[2], // Block number
                _inputIntermediateNodes,
                _indexesAndBlockNumbers[1] // Index of input tx in the block
            ),
            "CCBurnRouter: not finalized"
        );

        /*
            Checks that input tx has not been provided as a burn proof
            note: if a locker executes a cc burn request but doesn't provide burn proof before deadline,
            we consider the transaction as a malicious tx
        */
        require(
            !_isUsedAsBurnProof[_inputTxId],
            "CCBurnRouter: already used"
        );

        // prevents multiple slashing of locker
        _isUsedAsBurnProof[_inputTxId] = true;  

        // Checks that deadline for using the tx as burn proof has passed
        require(
            lastSubmittedHeight(_relay) > _transferDeadline + _indexesAndBlockNumbers[2],
            "CCBurnRouter: deadline not passed"
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

        // Sends extra ETH back to msg.sender
        Address.sendValue(payable(msg.sender), msg.value - feeAmount);

        return abi.decode(data, (bool));
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