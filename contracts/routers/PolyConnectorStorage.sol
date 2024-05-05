// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./interfaces/IPolyConnector.sol";

abstract contract PolyConnectorStorage is IPolyConnector {
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

    address public override lockersProxy;
    address public override burnRouterProxy;
    address public override sourceChainConnector;
    address public override across;
    uint256 public override sourceChainId;
    mapping(address => mapping(address => uint256)) public override failedReqs;
    // ^ Mapping from [user][token] to amount
}