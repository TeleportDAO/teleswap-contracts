pragma solidity 0.8.0;

import "./TypedMemView.sol";
import "./ViewBTC.sol";
import "hardhat/console.sol";

// a library for parsing bitcoin transactions

library NewTxHelper {

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
        return (bitcoinAmount, arbitraryData);
    }

    function parseAmountForP2PK (
        bytes memory vout,
        address desiredRecipient
    ) internal returns(uint64, bytes memory) {
        bytes29 voutView = vout.ref(0).tryAsVout();
        bool isvoutViewNull = voutView.isNull();

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
                if (scriptPubkey.len() == 23 || scriptPubkey.len() == 24) {
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
        
        return (bitcoinAmount, arbitraryData);
    }

    function parseChainId(bytes memory arbitraryData) internal returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 0, 0);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    function parseAppId(bytes memory arbitraryData) internal returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 1, 2);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    function parseRecipientAddress(bytes memory arbitraryData) internal returns (address parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 3, 22);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    function parsePercentageFee (bytes memory arbitraryData) internal returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 23, 24);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    function parseSpeed (bytes memory arbitraryData) internal returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 25, 25);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    function parseExchangeToken(bytes memory arbitraryData) internal returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 26, 45);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    function parseExchangeOutputAmount(bytes memory arbitraryData) internal returns (uint224 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 46, 73);
        assembly {
            parsedValue := mload(add(slicedBytes, 28))
        }
    }

    function parseDeadline(bytes memory arbitraryData) internal returns (uint32 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 74, 77);
        assembly {
            parsedValue := mload(add(slicedBytes, 4))
        }
    }

    function parseIsFixedToken(bytes memory arbitraryData) internal returns (uint8 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 78, 78);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    // TODO: use parseExchangeToken to check if the request is a exchange or a transfer
    // function parseIsExchange (bytes memory arbitraryData) internal returns (bool parsedValue) {
    //     bytes memory slicedBytes = sliceBytes(arbitraryData, 28, 28);
    //     bytes1 zero = 0x00;
    //     if (slicedBytes[0] == zero) {
    //         parsedValue = false;
    //     } else {
    //         parsedValue = true;
    //     }
    // }

    // function parseSpeed(bytes memory arbitraryData) internal returns (uint8 parsedValue){
    //     bytes memory slicedBytes = sliceBytes(arbitraryData, 29, 29);
    //     assembly {
    //         parsedValue := mload(add(slicedBytes, 1))
    //     }
    // }

    function sliceBytes(bytes memory data, uint start, uint end) internal returns (bytes memory result) {
        bytes1 temp;
        for (uint i = start; i < end + 1; i++) {
            temp = data[i];
            result = abi.encodePacked(result, temp);
        }
    }

    function calculateTxId (
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime
    ) internal returns (bytes32) {
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return revertBytes32(inputHash2);
    }

    function revertBytes32 (bytes32 input) internal returns (bytes32) {
        bytes memory temp;
        bytes32 result;
        for (uint i = 0; i < 32; i++) {
            temp = abi.encodePacked(temp, input[31-i]);
        }
        assembly {
            result := mload(add(temp, 32))
        }
        return result;
    }

    function parseInput(bytes memory vin, uint index) internal returns (bytes29 input) {
        bytes29 vinView = vin.ref(0).tryAsVin();
        // Extract the desired input
        input = ViewBTC.indexVin(vinView, index);
    }

    function parseInputScriptSig(bytes memory vin, uint index) internal returns (bytes memory scriptSig) {
        // Extract the desired input
        bytes29 input = parseInput(vin, index);
        // Extract the script sig
        bytes29 scriptSigMemView = ViewBTC.scriptSig(input);
        // Extract redeem script from the script sig
        scriptSig = scriptSigMemView.clone();
    }

    function numberOfOutputs(bytes memory vout) internal returns (uint numberOfOutputs) {
        bytes29 voutView = vout.ref(0).tryAsVout();
        numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));
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
