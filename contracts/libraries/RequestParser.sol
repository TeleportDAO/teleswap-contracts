// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

/// @notice Library for parsing cc transfer and cc exchange requests
library RequestParser {

    /// @notice Returns chain id of the request
    /// @param _arbitraryData Data written in Bitcoin tx
    function parseChainId(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 0, 1);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    /// @notice Returns app id of the request
    /// @dev Determines the app that request belongs to (e.g. cc transfer app id is 0)
    function parseAppId(bytes memory _arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 2, 2);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    /// @notice Returns recipient address
    /// @dev Minted TeleBTC or exchanged tokens will be sent to this address
    function parseRecipientAddress(bytes memory _arbitraryData) internal pure returns (address parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 3, 22);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    /// @notice Returns percentage fee (from total minted TeleBTC)
    /// @dev This fee goes to Teleporter who submitted the request
    function parsePercentageFee(bytes memory _arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 23, 24);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    /// @notice Determines type of the request
    /// @dev 0 for normal requests, 1 for fixed-rate requests
    function parseFixedRate(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 25, 25);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    /// @notice Returns address of exchange token
    /// @dev Minted TeleBTC will be exchanged for this token
    function parseExchangeToken(bytes memory _arbitraryData) internal pure returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 26, 45);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    /// @notice Returns min expected output (exchange) amount
    function parseExchangeOutputAmount(bytes memory _arbitraryData) internal pure returns (uint224 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 46, 73);
        assembly {
            parsedValue := mload(add(slicedBytes, 28))
        }
    }

    /// @notice Returns the sliced bytes
    /// @param _data Slicing data
    /// @param _start index of slicing
    /// @param _end index of slicing
    function sliceBytes(
        bytes memory _data,
        uint _start,
        uint _end
    ) internal pure returns (bytes memory _result) {
        bytes1 temp;
        for (uint i = _start; i < _end + 1; i++) {
            temp = _data[i];
            _result = abi.encodePacked(_result, temp);
        }
    }

}
