// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";

interface IBrc20PolyConnector {
    // Structs

    struct UserScriptAndType {
        bytes userScript;
        ScriptTypes scriptType;
    }

    struct exchangeForBrc20Arguments {
        uint256 chainId;
        address user;
        uint256 thirdPartyId;
        uint256 tokenId;
        uint256 appId;
        uint256 amount;
        uint256 inputAmount;
        address[] path;
        UserScriptAndType userScript;
    }

    // Events

    event NewSwapAndUnwrapBrc20(
        uint256 chainId,
        address indexed userTargetAddress,
        uint256 thirdPartyId,
        uint256 tokenId,
        uint256 appId,
        uint256 amount,
        uint256 inputAmount,
        address[] path,
        bytes userScript,
        ScriptTypes scriptType
        // uint256 requestIdOfLocker,
    );

    event FailedSwapAndUnwrapBrc20(
        uint256 chainId,
        address indexed userTargetAddress,
        uint256 thirdPartyId,
        uint256 tokenId,
        uint256 appId,
        uint256 amount,
        uint256 inputAmount,
        address[] path,
        bytes userScript,
        ScriptTypes scriptType
    );

    event MsgReceived(
        string functionName,
        uint256 uniqueCounter,
        uint256 chainId,
        bytes data
    );

    event AcrossUpdated(address oldAcross, address newAcross);

    event PolyConnectorUpdated(address oldPolyConnector, address newPolyConnector);

    event BurnRouterUpdated(address oldBurnRouter, address newBurnRouter);

    event LockersProxyUpdated(address oldLockersProxy, address newLockersProxy);

    // Read-only functions

    // function lockersProxy() external view returns (address);

    function brc20RouterProxy() external view returns (address);

    function across() external view returns (address);

    function failedReqs(address, uint256, address) external returns (uint256);

    // State-changing functions

    function setAcross(address _across) external;

    function setBrc20RouterProxy(address _burnRouterProxy) external;

    // function setLockersProxy(address _lockersProxy) external;

    function withdrawFundsToSourceChain(
        bytes memory _message,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function retrySwapAndUnwrap(
        bytes memory _message,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external;
}
