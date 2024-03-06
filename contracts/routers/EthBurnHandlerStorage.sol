// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;
import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";
contract EthBurnHandlerStorage {
    
    struct Bid {
        uint amount; 
        address token;
    }
   
    address constant public ETH_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; 

    address public lockersProxy;
    address public burnRouterProxy;
    address public ethConnectorProxy;
    address public across;
    address public acrossV3;
    uint256 public sourceChainId;

    mapping(address => mapping(address => uint)) public failedReqs;
    // ^ Mapping from [user][token] to amount

    struct UserScriptData {
        bytes userScript;
        ScriptTypes scriptType;
    }

}