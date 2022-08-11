// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./TypedMemView.sol";
import "./ViewBTC.sol";
import "hardhat/console.sol";


// A library for parsing bitcoin transactions
library NewTxHelper {

    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ViewBTC for bytes29;

    function parseValueAndData(
        bytes memory _vout,
        address _desiredRecipient
    ) internal view returns (uint64 bitcoinAmount, bytes memory arbitraryData) {
        bytes29 voutView = _vout.ref(0).tryAsVout();
        require(!voutView.isNull(), "TxHelper: vout is null");

        bytes29 output;
        bytes29 scriptPubkey;
        bytes29 _arbitraryData;
        address bitcoinRecipient;

        uint _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));

        for (uint index = 0; index < _numberOfOutputs; index++) {
            output = ViewBTC.indexVout(voutView, index);
            scriptPubkey = ViewBTC.scriptPubkey(output);
            _arbitraryData = ViewBTC.opReturnPayload(scriptPubkey);

            // Checks whether the output is an arbitarary data or not
            if(_arbitraryData == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                // Output is not an arbitrary data

                if (scriptPubkey.len() == 23 || scriptPubkey.len() == 24) {
                    // It is P2SH: OP_HASH160 ScriptHash OP_EQUAL
                    bitcoinRecipient = scriptPubkey.indexAddress(3);
                }

                if (scriptPubkey.len() == 26) {
                    // It is P2PKH: OP_DUP OP_HASH160 PubKeyHash OP_EQUALVERIFY OP_CHECKSIG
                    bitcoinRecipient = scriptPubkey.indexAddress(4);
                }

                if (scriptPubkey.len() == 21) {
                    // It is P2WPKH: 0 PubKeyHash
                    bitcoinRecipient = scriptPubkey.indexAddress(2);
                }

                if (scriptPubkey.len() == 33) {
                    // It is P2WSH: 0 ScriptHash
                    bitcoinRecipient = scriptPubkey.indexAddress(2);
                }

                if (bitcoinRecipient == _desiredRecipient) {
                    bitcoinAmount = ViewBTC.value(output);
                }

            } else {
                arbitraryData = _arbitraryData.clone(); // bytes29.clone() returns the whole bytes array
            }
        }
        
        return (bitcoinAmount, arbitraryData);
    }

    function parseTotalValue(bytes memory vout) internal pure returns (uint64) {
        bytes29 voutView = vout.ref(0).tryAsVout();
        bytes29 output;
        uint64 totalValue;

        uint _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));
        for (uint index = 0; index < _numberOfOutputs; index++) {
            output = ViewBTC.indexVout(voutView, index);
            totalValue = totalValue + ViewBTC.value(output);
        }

        return totalValue;
    }

    function parseChainId(bytes memory arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 0, 0);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    function parseAppId(bytes memory arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 1, 2);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    function parseRecipientAddress(bytes memory arbitraryData) internal pure returns (address parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 3, 22);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    function parsePercentageFee(bytes memory arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 23, 24);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    function parseSpeed(bytes memory arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(arbitraryData, 25, 25);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    function parseExchangeToken(bytes memory arbitraryData) internal pure returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 26, 45);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    function parseExchangeOutputAmount(bytes memory arbitraryData) internal pure returns (uint224 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 46, 73);
        assembly {
            parsedValue := mload(add(slicedBytes, 28))
        }
    }

    function parseDeadline(bytes memory arbitraryData) internal pure returns (uint32 parsedValue){
        bytes memory slicedBytes = sliceBytes(arbitraryData, 74, 77);
        assembly {
            parsedValue := mload(add(slicedBytes, 4))
        }
    }

    function parseIsFixedToken(bytes memory arbitraryData) internal pure returns (uint8 parsedValue){
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

    function sliceBytes(
        bytes memory data, 
        uint start, 
        uint end
    ) internal pure returns (bytes memory result) {
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
    ) internal pure returns (bytes32) {
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return revertBytes32(inputHash2);
    }

    function revertBytes32(bytes32 input) internal pure returns (bytes32) {
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

    function parseInput(bytes memory vin, uint index) internal pure returns (bytes29 input) {
        bytes29 vinView = vin.ref(0).tryAsVin();
        // Extract the desired input
        input = ViewBTC.indexVin(vinView, index);
    }

    function parseInputScriptSig(bytes memory vin, uint index) internal view returns (bytes memory scriptSig) {
        // Extract the desired input
        bytes29 input = parseInput(vin, index);
        // Extract the script sig
        bytes29 scriptSigMemView = ViewBTC.scriptSig(input);
        // Extract redeem script from the script sig
        scriptSig = scriptSigMemView.clone();
    }

    function numberOfOutputs(bytes memory vout) internal pure returns (uint _numberOfOutputs) {
        bytes29 voutView = vout.ref(0).tryAsVout();
        _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));
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
