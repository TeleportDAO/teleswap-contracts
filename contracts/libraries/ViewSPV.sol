// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TypedMemView.sol";
import "./ViewBTC.sol";


library ViewSPV {
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ViewBTC for bytes29;

    

    function revertBytes32(bytes32 input) internal pure returns(bytes32) {
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

}