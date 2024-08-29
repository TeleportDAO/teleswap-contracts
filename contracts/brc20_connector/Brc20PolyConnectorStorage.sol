// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./interfaces/IBrc20PolyConnector.sol";

abstract contract Brc20PolyConnectorStorage is IBrc20PolyConnector {
    struct Bid {
        uint256 amount;
        address token;
    }

    struct UserScriptData {
        bytes userScript;
        ScriptTypes scriptType;
    }

    address public constant ETH_ADDR =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public override brc20RouterProxy;
    address public override across;
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        public
        override failedReqs;
    // ^ Mapping from [user][chainId][token] to amount
}
