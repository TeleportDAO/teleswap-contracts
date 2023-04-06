// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/utils/Address.sol";

library RelayHelper {

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

    function getFinalizedBlockHeaderFee(address _relay, uint _blockNumber) public view returns (uint) {
        return IBitcoinRelay(_relay).getBlockHeaderFee(_blockNumber, 0);
    }
}