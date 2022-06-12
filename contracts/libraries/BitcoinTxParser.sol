pragma solidity 0.7.6;

import "./TypedMemView.sol";
import "./ViewBTC.sol";
import "hardhat/console.sol";

// a library for parsing bitcoin transactions

library BitcoinTxParser {

    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ViewBTC for bytes29;

    function parseAmountForP2SH (bytes memory vout, address desiredRecipient) internal returns(uint64, bytes memory) {
        bytes29 voutView = vout.ref(0).tryAsVout();
        bytes29 output;
        uint64 bitcoinAmount;
        bytes29 scriptPubkey;
        bytes29 _arbitraryData;
        address bitcoinRecipient;
        bytes memory arbitraryData;
        uint numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));
        for(uint index = 0; index < numberOfOutputs; index++){
            output = ViewBTC.indexVout(voutView, index);
            scriptPubkey = ViewBTC.scriptPubkey(output);
            _arbitraryData = ViewBTC.opReturnPayload(scriptPubkey);
            // check whether the output is an arbitarary data or not
            if(_arbitraryData == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                // output is not an arbitrary data
                // indexAddress starts with 3, because the first 2 bytes are opcode.
                bitcoinRecipient = scriptPubkey.indexAddress(3);
                if (bitcoinRecipient == desiredRecipient) {
                    bitcoinAmount = ViewBTC.value(output); // number of btc that user locked
                }
            } else {
                // output is an arbitrary data
                arbitraryData = _arbitraryData.clone(); // bytes29.clone() returns the whole bytes array
            }
        }
        // console.log(value);
        // console.logBytes(requestData);
        return (bitcoinAmount, arbitraryData);
    }

        function parseAmountForP2PK (
            bytes memory vout,
            address desiredRecipient
        ) internal returns(uint64, bytes memory) {
        bytes29 voutView = vout.ref(0).tryAsVout();
        bytes29 output;
        uint64 bitcoinAmount;
        bytes29 scriptPubkey;
        bytes29 _arbitraryData;
        address bitcoinRecipient;
        bytes memory arbitraryData;
        uint numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));
        for (uint index = 0; index < numberOfOutputs; index++) {
            output = ViewBTC.indexVout(voutView, index);
            scriptPubkey = ViewBTC.scriptPubkey(output);
            _arbitraryData = ViewBTC.opReturnPayload(scriptPubkey);
            // check whether the output is an arbitarary data or not
            if(_arbitraryData == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                // output is not an arbitrary data
                if (scriptPubkey.len() == 26) {
                    bitcoinRecipient = scriptPubkey.indexAddress(4);
                }
                if (scriptPubkey.len() == 23) {
                    bitcoinRecipient = scriptPubkey.indexAddress(3);
                }
                if (bitcoinRecipient == desiredRecipient) {
                    bitcoinAmount = ViewBTC.value(output); // number of btc that user locked
                }
            } else {
                // output is an arbitrary data
                arbitraryData = _arbitraryData.clone(); // bytes29.clone() returns the whole bytes array
            }
        }
        // console.log(value);
        // console.logBytes(requestData);
        return (bitcoinAmount, arbitraryData);
    }
    
    function parseRecipientAddress(bytes memory arbitraryData) internal returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 0, 19);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
        // console.log("parseRecipientAddress", parsedValue);
    }

    function parseTeleporterFee(bytes memory arbitraryData) internal returns (uint64 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 20, 27);
        assembly {
            parsedValue := mload(add(slicedBytes, 8))
        }
        // console.log("parseTeleporterFee", parsedValue);
    }

    function parseIsExchange(bytes memory arbitraryData) internal returns (bool parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 28, 28);
        bytes1 zero = 0x00;
        if (slicedBytes[0] == zero) {
            parsedValue = false;
        } else {
            parsedValue = true;
        }
        // console.log("parseIsExchange", parsedValue);
    }

    function parseSpeed(bytes memory arbitraryData) internal returns (uint8 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 29, 29);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
        // console.log("parseSpeed", parsedValue);
    }

    function parseExchangeToken(bytes memory arbitraryData) internal returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 30, 49);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
        // console.log("parseExchangeToken", parsedValue);
    }

    function parseExchangeAmount(bytes memory arbitraryData) internal returns (uint128 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 50, 65);
        assembly {
            parsedValue := mload(add(slicedBytes, 16))
        }
        // console.log("parseExchangeAmount", parsedValue);
    }

    function parseDeadline(bytes memory arbitraryData) internal returns (uint64 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 66, 73);
        assembly {
            parsedValue := mload(add(slicedBytes, 8))
        }
        // console.log("parseDeadline", parsedValue);
    }

    function parseIsFixedToken(bytes memory arbitraryData) internal returns (bool parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 74, 74);
        bytes1 zero = 0x00;
        if (slicedBytes[0] == zero) {
            parsedValue = false;
        } else {
            parsedValue = true;
        }
        // console.log("parseIsFixedToken", parsedValue);
    }

    function sliceBytes(bytes memory data, uint start, uint end) internal returns (bytes memory result) {
        byte temp;
        for (uint i = start; i < end + 1; i++) {
            temp = data[i];
            result = abi.encodePacked(result, temp);
        }
    }

    // TODO: add exchange path to arbitrary data (for now, user only gives us the exchnage token address)
    // function parsePath(bytes memory arbitraryData)
    //     internal
    //     returns (address[] memory)
    // {
    //     uint256 sizeofPath;
    //     assembly {
    //         sizeofPath := mload(add(arbitraryData, 356)) // bias = 4*32 + 4
    //     } // found the postion using testing
    //     address temp;
    //     uint256 index;
    //     index = 356 + 32;

    //     for (uint256 i = 0; i < sizeofPath; i++) {
    //         assembly {
    //             temp := mload(add(arbitraryData, index))
    //         }
    //         parsedPath.push(temp);
    //         index = index + 32;
    //     }
    //     return parsedPath;
    // }

}
