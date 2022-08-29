// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TypedMemView.sol";
import "./ViewBTC.sol";
import "./ScriptTypesEnum.sol";
import "hardhat/console.sol";

// A library for parsing bitcoin transactions
library TxHelper {

    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ViewBTC for bytes29;

    /// @notice                           Parses the BTC amount of a transaction
    /// @dev                              Finds the BTC amount that has been sent to the locking script
    ///                                   Returns zero if no matching locking scrip is found
    /// @param _vout                      The vout of a Bitcoin transaction
    /// @param _lockingScript             Desired locking script
    /// @return bitcoinAmount             Amount of BTC have been sent to the _lockingScript
    function parseOutputValueHavingLockingScript(
        bytes memory _vout,
        bytes memory _lockingScript
    ) internal view returns (uint64 bitcoinAmount) {
        // Checks that vout is not null
        bytes29 voutView = _vout.ref(0).tryAsVout();
        require(!voutView.isNull(), "TxHelper: vout is null");

        bytes29 output;
        bytes29 scriptPubkey;
        
        // Finds total number of outputs
        uint _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));

        for (uint index = 0; index < _numberOfOutputs; index++) {
            output = ViewBTC.indexVout(voutView, index);
            scriptPubkey = ViewBTC.scriptPubkey(output);

            if (
                keccak256(abi.encodePacked(scriptPubkey.clone())) == keccak256(abi.encodePacked(_lockingScript))
            ) {
                bitcoinAmount = ViewBTC.value(output);
                // Stops searching after finding the desired locking script
                break;
            }
        }
    }

    /// @notice                           Parses the BTC amount and the op_return of a transaction
    /// @dev                              Finds the BTC amount that has been sent to the locking script
    /// @param _vout                      The vout of a Bitcoin transaction
    /// @param _lockingScript             Desired locking script
    /// @return bitcoinAmount             Amount of BTC have been sent to the _lockingScript
    /// @return arbitraryData             Opreturn  data of the transaction
    function parseOutputValueAndDataHavingLockingScript(
        bytes memory _vout,
        bytes memory _lockingScript
    ) internal view returns (uint64 bitcoinAmount, bytes memory arbitraryData) {
        // Checks that vout is not null
        bytes29 voutView = _vout.ref(0).tryAsVout();
        require(!voutView.isNull(), "TxHelper: vout is null");

        bytes29 output;
        bytes29 scriptPubkey;
        bytes29 scriptPubkeyWithLength;
        bytes29 _arbitraryData;

        // Finds total number of outputs
        uint _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));

        for (uint index = 0; index < _numberOfOutputs; index++) {
            output = ViewBTC.indexVout(voutView, index);
            scriptPubkey = ViewBTC.scriptPubkey(output);
            scriptPubkeyWithLength = ViewBTC.scriptPubkeyWithLength(output);
            _arbitraryData = ViewBTC.opReturnPayloadBig(scriptPubkeyWithLength);

            // Checks whether the output is an arbitarary data or not
            if(_arbitraryData == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) {
                // Output is not an arbitrary data
                if (
                    keccak256(abi.encodePacked(scriptPubkey.clone())) == keccak256(abi.encodePacked(_lockingScript))
                ) {
                    bitcoinAmount = ViewBTC.value(output);
                }
            } else {
                // Returns the whole bytes array
                arbitraryData = _arbitraryData.clone();
            }
        }
    }

    /// @notice                           Parses the BTC amount that has been sent to 
    ///                                   a specific script in a specific output
    /// @param _vout                      The vout of a Bitcoin transaction
    /// @param _voutIndex                 Index of the output that we are looking at
    /// @param _script                    Desired recipient script
    /// @param _scriptType                Type of the script (e.g. P2PK)
    /// @return bitcoinAmount             Amount of BTC have been sent to the _script
    function parseValueFromSpecificOutputHavingScript(
        bytes memory _vout,
        uint _voutIndex,
        bytes memory _script,
        ScriptTypes _scriptType
    ) internal pure returns (uint64 bitcoinAmount) {

        bytes29 voutView = _vout.ref(0).tryAsVout();
        require(!voutView.isNull(), "TxHelper: vout is null");
        bytes29 output = ViewBTC.indexVout(voutView, _voutIndex);
        bytes29 scriptPubkey = ViewBTC.scriptPubkey(output);

        if (_scriptType == ScriptTypes.P2PK) {
            // note: first byte is Pushdata Bytelength. 
            // note: public key length is 32.           
            bitcoinAmount = keccak256(_script) == keccak256(abi.encodePacked(scriptPubkey.index(1, 32))) ? ViewBTC.value(output) : 0;
        } else if (_scriptType == ScriptTypes.P2PKH) { 
            // note: first three bytes are OP_DUP, OP_HASH160, Pushdata Bytelength. 
            // note: public key hash length is 20.         
            bitcoinAmount = keccak256(_script) == keccak256(abi.encodePacked(scriptPubkey.indexAddress(3))) ? ViewBTC.value(output) : 0;
        } else if (_scriptType == ScriptTypes.P2SH) {
            // note: first two bytes are OP_HASH160, Pushdata Bytelength
            // note: script hash length is 20.                      
            bitcoinAmount = keccak256(_script) == keccak256(abi.encodePacked(scriptPubkey.indexAddress(2))) ? ViewBTC.value(output) : 0;
        } else if (_scriptType == ScriptTypes.P2WPKH) {               
            // note: first two bytes are OP_0, Pushdata Bytelength
            // note: segwit public key hash length is 20. 
            bitcoinAmount = keccak256(_script) == keccak256(abi.encodePacked(scriptPubkey.indexAddress(2))) ? ViewBTC.value(output) : 0;
        } else if (_scriptType == ScriptTypes.P2WSH) {
            // note: first two bytes are OP_0, Pushdata Bytelength 
            // note: segwit script hash length is 32.           
            bitcoinAmount = keccak256(_script) == keccak256(abi.encodePacked(scriptPubkey.index(2, 32))) ? ViewBTC.value(output) : 0;
        }
        
    }

    /// @notice                           Parses locking script from an output
    /// @dev                              Reverts if vout is null
    /// @param _vout                      The vout of a Bitcoin transaction
    /// @param _index                     Index of the output that we are looking at
    /// @return _lockingScript            Parsed locking script
    function getLockingScript(
        bytes memory _vout, 
        uint _index
    ) internal view returns (bytes memory _lockingScript) {
        bytes29 vout = _vout.ref(0).tryAsVout();
        require(!vout.isNull(), "TxHelper: vout is null");
        bytes29 output = ViewBTC.indexVout(vout, _index);
        bytes29 _lockingScriptBytes29 = ViewBTC.scriptPubkey(output);
        _lockingScript = _lockingScriptBytes29.clone();
    }

    /// @notice                           Parses outpoint info from an input
    /// @dev                              Reverts if vin is null
    /// @param _vin                       The vin of a Bitcoin transaction
    /// @param _index                     Index of the input that we are looking at
    /// @return _txId                     Output tx id
    /// @return _outputIndex              Output tx index
    function extractOutpoint(
        bytes memory _vin, 
        uint _index
    ) internal pure returns (bytes32 _txId, uint _outputIndex) {
        bytes29 vin = _vin.ref(0).tryAsVin();
        require(!vin.isNull(), "TxHelper: vin is null");
        bytes29 input = ViewBTC.indexVin(vin, _index);
        bytes29 outpoint = ViewBTC.outpoint(input);
        _txId = ViewBTC.txidLE(outpoint);
        _outputIndex = ViewBTC.outpointIdx(outpoint);
    }

    /// @notice                   Finds total outputs value
    /// @dev                      Reverts if vout is null
    /// @param _vout              The vout of a Bitcoin transaction
    /// @return _totalValue       Total vout value
    function parseTotalValue(bytes memory _vout) internal pure returns (uint64 _totalValue) {
        bytes29 voutView = _vout.ref(0).tryAsVout();
        require(!voutView.isNull(), "TxHelper: vout is null");
        bytes29 output;

        // Finds total number of outputs
        uint _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));

        for (uint index = 0; index < _numberOfOutputs; index++) {
            output = ViewBTC.indexVout(voutView, index);
            _totalValue = _totalValue + ViewBTC.value(output);
        }
    }

    /// @notice                      Calculates the required transaction Id from the transaction details
    /// @dev                         Calculates the hash of transaction details two consecutive times
    /// @param _version              Version of the transaction
    /// @param _vin                  Inputs of the transaction
    /// @param _vout                 Outputs of the transaction
    /// @param _locktime             Lock time of the transaction
    /// @return                      Transaction Id of the required transaction
    function calculateTxId(
        bytes4 _version,
        bytes memory _vin,
        bytes memory _vout,
        bytes4 _locktime
    ) internal pure returns (bytes32) {
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return revertBytes32(inputHash2);
    }

    /// @notice                      Reverts a Bytes32 input
    /// @param _input                Bytes32 input that we want to revert
    /// @return                      Reverted bytes32
    function revertBytes32(bytes32 _input) internal pure returns (bytes32) {
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

    /// @notice                   Returns number of outputs in a vout
    /// @param _vout              The vout of a Bitcoin transaction           
    function numberOfOutputs(bytes memory _vout) internal pure returns (uint _numberOfOutputs) {
        bytes29 voutView = _vout.ref(0).tryAsVout();
        _numberOfOutputs = uint256(ViewBTC.indexCompactInt(voutView, 0));
    }

    function parseChainId(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 0, 0);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    function parseAppId(bytes memory _arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 1, 2);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    function parseRecipientAddress(bytes memory _arbitraryData) internal pure returns (address parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 3, 22);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    function parsePercentageFee(bytes memory _arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 23, 24);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    function parseSpeed(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 25, 25);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    function parseExchangeToken(bytes memory _arbitraryData) internal pure returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 26, 45);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    function parseExchangeOutputAmount(bytes memory _arbitraryData) internal pure returns (uint224 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 46, 73);
        assembly {
            parsedValue := mload(add(slicedBytes, 28))
        }
    }

    function parseDeadline(bytes memory _arbitraryData) internal pure returns (uint32 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 74, 77);
        assembly {
            parsedValue := mload(add(slicedBytes, 4))
        }
    }

    function parseIsFixedToken(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 78, 78);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

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

}
