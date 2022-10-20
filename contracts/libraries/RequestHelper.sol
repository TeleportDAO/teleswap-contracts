// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "hardhat/console.sol";

// A library for parsing cc transfer and cc exchange requests
library RequestHelper {

    /// @notice                     Returns chain id of the request
    /// @dev                        Determines the chain that request belongs to
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseChainId(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 0, 0);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    /// @notice                     Returns app id of the request
    /// @dev                        Determines the app that request belongs to (e.g. cross-chain transfer app id is 0)
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseAppId(bytes memory _arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 1, 2);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    /// @notice                     Returns recipient address
    /// @dev                        Minted TeleBTC or exchanged tokens will be sent to this address
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseRecipientAddress(bytes memory _arbitraryData) internal pure returns (address parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 3, 22);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    /// @notice                     Returns percentage fee (from total minted TeleBTC)
    /// @dev                        This fee goes to Teleporter who submitted the request
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parsePercentageFee(bytes memory _arbitraryData) internal pure returns (uint16 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 23, 24);
        assembly {
            parsedValue := mload(add(slicedBytes, 2))
        }
    }

    /// @notice                     Returns speed of request
    /// @dev                        0 for normal requests, 1 for instant requests
    ///                             Instant requests are used to pay back an instant loan
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseSpeed(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue) {
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 25, 25);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    /// @notice                     Returns address of exchange token
    /// @dev                        Minted TeleBTC will be exchanged to this token
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseExchangeToken(bytes memory _arbitraryData) internal pure returns (address parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 26, 45);
        assembly {
            parsedValue := mload(add(slicedBytes, 20))
        }
    }

    /// @notice                     Returns amount of output (exchange) token
    /// @dev                        If input token is fixed, outputAmount means the min expected output amount
    ///                             If output token is fixed, outputAmount is desired output amount
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseExchangeOutputAmount(bytes memory _arbitraryData) internal pure returns (uint224 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 46, 73);
        assembly {
            parsedValue := mload(add(slicedBytes, 28))
        }
    }

    /// @notice                     Returns deadline of executing exchange request
    /// @dev                        This value is compared to block.timestamp
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseDeadline(bytes memory _arbitraryData) internal pure returns (uint32 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 74, 77);
        assembly {
            parsedValue := mload(add(slicedBytes, 4))
        }
    }

    /// @notice                     Returns true if input token is fixed
    /// @param _arbitraryData       Data written in Bitcoin tx
    function parseIsFixedToken(bytes memory _arbitraryData) internal pure returns (uint8 parsedValue){
        bytes memory slicedBytes = sliceBytes(_arbitraryData, 78, 78);
        assembly {
            parsedValue := mload(add(slicedBytes, 1))
        }
    }

    /// @notice                 Returns a sliced bytes
    /// @param _data            Data that is sliced
    /// @param _start           Start index of slicing
    /// @param _end             End index of slicing
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
