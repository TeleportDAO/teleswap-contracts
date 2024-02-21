// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@teleportdao/btc-evm-bridge/contracts/libraries/BitcoinHelper.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../routers/interfaces/ICcExchangeRouter.sol";
import "../libraries/RequestParser.sol";

library CcExchangeRouterLib {

    /// @notice Parses and stores exchange request if it's valid
    function ccExchangeHelper(
        ICcExchangeRouter.TxAndProof memory _txAndProof,
        mapping(bytes32 => ICcExchangeRouter.ccExchangeRequest) storage ccExchangeRequests,
        mapping(bytes32 => ICcExchangeRouter.extendedCcExchangeRequest) storage extendedCcExchangeRequests,
        address _teleBTC,
        address _wrappedNativeToken,
        uint _maxProtocolFee,
        bytes memory _lockerLockingScript
    ) external returns (bytes32) {

        // Finds tx id
        bytes32 txId = BitcoinHelper.calculateTxId(
            _txAndProof.version, _txAndProof.vin, _txAndProof.vout, _txAndProof.locktime
        );

        // Checks that the request has not been processed before
        require(
            !ccExchangeRequests[txId].isUsed,
            "ExchangeRouterLib: already used"
        );

        // Extracts value and OP_RETURN data from the request
        ICcExchangeRouter.ccExchangeRequest memory request;
        bytes memory arbitraryData;
        (request.inputAmount, arbitraryData) = BitcoinHelper.parseValueAndDataHavingLockingScriptSmallPayload(
            _txAndProof.vout, 
            _lockerLockingScript
        );

        /*  
            Exchange requests structure:
            1) chainId, 2 byte (OLD: 1 BYTE): max 65535 chains
            2) appId, 1 byte (OLD: 2 BYTE): max 256 apps
            3) recipientAddress, 20 byte: EVM account
            4) teleporterPercentageFee, 2 byte: between [0,10000]
            5) isFixedRate, 1 byte (OLD: SPEED): {0,1}
            6) exchangeToken, 20 byte: token address
            7) outputAmount, 28 byte: min expected output amount. Assuming that the token supply
               is less than 10^18 and token decimal is 18 (> (10^18) * (10^18))
            8) deadline: REMOVED
            9) isFixedToken: REMOVED 
            10) acrossRelayerFeePercentage, 3 byte: will be multiply by 10^11, 10^18 means 100%, so the minimum 
            amount of fee percentage is 10^-5%
            TOTAL = 77 BYTE
        */
        require(arbitraryData.length == 74, "ExchangeRouterLib: invalid len");
        require(request.inputAmount > 0, "ExchangeRouterLib: zero input");

        extendedCcExchangeRequests[txId].chainId = RequestParser.parseChainId(arbitraryData);
        extendedCcExchangeRequests[txId].acrossFeePercentage = RequestParser.parseaArossFeePercentage(arbitraryData); 
        request.appId = RequestParser.parseAppId(arbitraryData);
        address exchangeToken = RequestParser.parseExchangeToken(arbitraryData);
        request.outputAmount = RequestParser.parseExchangeOutputAmount(arbitraryData);
        request.isFixedToken = true; // Note: we assume input amount is fixed
        request.recipientAddress = RequestParser.parseRecipientAddress(arbitraryData);

        // Note: default exchange path is: [teleBTC, wrappedNativeToken, exchangeToken]
        //       since [teleBTC, wrappedNativeToken] pair exists and we assume most tokens have
        //       pair with wrappedNativeToken
        ccExchangeRequests[txId].path.push(_teleBTC);
        ccExchangeRequests[txId].path.push(_wrappedNativeToken);
        if (exchangeToken != _wrappedNativeToken) {
            ccExchangeRequests[txId].path.push(exchangeToken);
        }

        // Finds Teleporter fee
        uint percentageFee = RequestParser.parsePercentageFee(arbitraryData);
        require(percentageFee <= _maxProtocolFee, "ExchangeRouterLib: wrong fee");
        request.fee = percentageFee * request.inputAmount / _maxProtocolFee;
        
        // Note: speed now determines floating-rate (speed = 0) or fixed-rate (speed = 1)
        request.speed = RequestParser.parseFixedRate(arbitraryData);
        request.isUsed = true;

        // Saves request
        ccExchangeRequests[txId] = request;

        return txId;
    }

    /// @notice Verifies the signature of _msgHash
    /// @return _signer Address of message signer (if signature is valid)
    function _verifySig(
        bytes32 _msgHash, 
        bytes32 _r, 
        bytes32 _s,
        uint8 _v
    ) internal pure returns (address _signer) {
        // Verify the message using ecrecover
        _signer = ecrecover(_msgHash, _v, _r, _s);
        require(_signer != address(0), "ExchangeRouterLib: invalid sig");
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
    ) internal returns (bool) {
        // Finds fee amount
        uint feeAmount = _getFinalizedBlockHeaderFee(_relay, _txAndProof.blockNumber);
        require(msg.value >= feeAmount, "ExchangeRouterLib: low fee");

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