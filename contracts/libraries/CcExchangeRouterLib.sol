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
        uint _chainId,
        address _teleBTC,
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
            "CCExchangeRouter: already used"
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

        require(arbitraryData.length == 79, "CCExchangeRouter: invalid len");

        // Checks that input amount is not zero
        require(request.inputAmount > 0, "CCExchangeRouter: zero input");

        // Checks that the request belongs to this chain
        require(
            _chainId == RequestHelper.parseChainId(arbitraryData), 
            "CCExchangeRouter: wrong chain id"
        );
        request.appId = RequestHelper.parseAppId(arbitraryData);
        
        address exchangeToken = RequestHelper.parseExchangeToken(arbitraryData);
        request.outputAmount = RequestHelper.parseExchangeOutputAmount(arbitraryData);

        if (RequestHelper.parseIsFixedToken(arbitraryData) == 0) {
            request.isFixedToken = false ;
        } else {
            request.isFixedToken = true ;
        }

        request.recipientAddress = RequestHelper.parseRecipientAddress(arbitraryData);

        // note: we assume that the path length is two
        address[] memory thePath = new address[](2);
        thePath[0] = _teleBTC;
        thePath[1] = exchangeToken;
        request.path = thePath;

        request.deadline = RequestHelper.parseDeadline(arbitraryData);

        // Calculates fee
        uint percentageFee = RequestHelper.parsePercentageFee(arbitraryData);
        require(percentageFee <= _maxProtocolFee, "CCExchangeRouter: wrong percentage fee");
        request.fee = percentageFee*request.inputAmount/_maxProtocolFee;

        request.speed = RequestHelper.parseSpeed(arbitraryData);

        request.isUsed = true;

        // Saves request
        ccExchangeRequests[txId] = request;

        return txId;
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
        require(msg.value >= feeAmount, "BitcoinRelay: low fee");

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