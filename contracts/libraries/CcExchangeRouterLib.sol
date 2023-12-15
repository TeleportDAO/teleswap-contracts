// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@teleportdao/btc-evm-bridge/contracts/libraries/BitcoinHelper.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../routers/interfaces/ICcExchangeRouter.sol";
import "../libraries/RequestHelper.sol";

library CcExchangeRouterLib {

    /// @notice Stores exchange request if it's valid
    /// @param _lockerLockingScript Locker's locking script
    function ccExchangeHelper(
        address _relay,
        ICcExchangeRouter.TxAndProof memory _txAndProof,
        mapping(bytes32 => ICcExchangeRouter.ccExchangeRequest) storage ccExchangeRequests,
        mapping(bytes32 => ICcExchangeRouter.extendedCcExchangeRequest) storage extendedCcExchangeRequests,
        address _teleBTC,
        address _wrappedNativeToken,
        uint _maxProtocolFee,
        bytes memory _lockerLockingScript
    ) external returns (bytes32) {

        // Calculates transaction id
        bytes32 txId = BitcoinHelper.calculateTxId(
            _txAndProof.version, _txAndProof.vin, _txAndProof.vout, _txAndProof.locktime
        );

        // Checks that the request has not been processed before
        require(
            !ccExchangeRequests[txId].isUsed,
            "CcExchangeRouterLib: already used"
        );

        // Checks if transaction has been confirmed on Bitcoin
        _isConfirmed(
            _relay,
            txId,
            _txAndProof
        );

        // Extracts value and opreturn data from request
        ICcExchangeRouter.ccExchangeRequest memory request; // Defines it to save gas
        bytes memory arbitraryData;
        (request.inputAmount, arbitraryData) = BitcoinHelper.parseValueAndDataHavingLockingScriptBigPayload(
            _txAndProof.vout, 
            _lockerLockingScript
        );

        require(arbitraryData.length == 79, "CcExchangeRouterLib: invalid len");

        // Checks that input amount is not zero
        require(request.inputAmount > 0, "CcExchangeRouterLib: zero input");

        extendedCcExchangeRequests[txId].chainId = RequestHelper.parseChainId(arbitraryData);

        request.appId = RequestHelper.parseAppId(arbitraryData);
        
        address exchangeToken = RequestHelper.parseExchangeToken(arbitraryData);
        request.outputAmount = RequestHelper.parseExchangeOutputAmount(arbitraryData);

        // Note: we assume that input amount is fixed
        request.isFixedToken = true ;

        request.recipientAddress = RequestHelper.parseRecipientAddress(arbitraryData);

        // Note: we assume that the path length is two
        ccExchangeRequests[txId].path.push(_teleBTC);
        ccExchangeRequests[txId].path.push(_teleBTC);
        if (exchangeToken != _wrappedNativeToken) {
            ccExchangeRequests[txId].path.push(exchangeToken);
        }
        // address[] memory thePath = new address[](2);
        // thePath[0] = _teleBTC;
        // thePath[1] = exchangeToken;
        // request.path = thePath;

        request.deadline = RequestHelper.parseDeadline(arbitraryData);

        // Calculates fee
        uint percentageFee = RequestHelper.parsePercentageFee(arbitraryData);
        require(percentageFee <= _maxProtocolFee, "CcExchangeRouterLib: wrong percentage fee");
        request.fee = percentageFee*request.inputAmount/_maxProtocolFee;

        // Note: speed now determines floating rate (speed = 0) or fixed rate (speed = 1)
        request.speed = RequestHelper.parseSpeed(arbitraryData);

        request.isUsed = true;

        // Saves request
        ccExchangeRequests[txId] = request;

        return txId;
    }

    function _verifySig(
        bytes memory _message,
        bytes32 _r,
        bytes32 _s,
        uint8 _v,
        address _signer
    ) internal pure returns (bool) {
        // Compute the message hash
        bytes32 messageHash = keccak256(_message);

        // Prefix the message hash as per the Ethereum signing standard
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", uintToString(_message.length), messageHash)
        );

        // Verify the message using ecrecover
        address signer = ecrecover(ethSignedMessageHash, _v, _r, _s);
        require(signer != address(0), "CcExchangeRouterLib: Invalid sig");

        return _signer == signer;
    }

    /// @notice Helper function to convert uint to string
    function uintToString(uint v) private pure returns (string memory str) {
        if (v == 0) {
            return "0";
        }
        uint j = v;
        uint length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint k = length;
        while (v != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(v - v / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            v /= 10;
        }
        str = string(bstr);
    }

    /// @notice Checks inclusion of the transaction in the specified block
    /// @dev Calls the relay contract to check Merkle inclusion proof
    /// @param _relay Address of Relay contract
    /// @param _txId of the transaction
    /// @return True if the transaction was included in the block
    function _isConfirmed(
        address _relay,
        bytes32 _txId,
        ICcExchangeRouter.TxAndProof memory _txAndProof
    ) private returns (bool) {
        // Finds fee amount
        uint feeAmount = _getFinalizedBlockHeaderFee(_relay, _txAndProof.blockNumber);
        require(msg.value >= feeAmount, "CcExchangeRouterLib: low fee");

        // Calls relay contract
        bytes memory data = Address.functionCallWithValue(
            _relay,
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint256,bytes,uint256)",
                _txId,
                _txAndProof.blockNumber,
                _txAndProof.intermediateNodes,
                _txAndProof.index
            ),
            feeAmount
        );

        // Sends extra ETH back to msg.sender
        Address.sendValue(payable(msg.sender), msg.value - feeAmount);

        return abi.decode(data, (bool));
    }

    function _getFinalizedBlockHeaderFee(
        address _relay, 
        uint _blockNumber
    ) private view returns (uint) {
        return IBitcoinRelay(_relay).getBlockHeaderFee(_blockNumber, 0);
    }
}