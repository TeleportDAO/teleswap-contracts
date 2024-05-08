// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";

interface IPolyConnector {
    /// @notice Structure for _swapAndUnwrap function
    struct exchangeForBtcArguments {
        uint256 chainId;
        address user;
        address exchangeConnector;
        uint256 minOutputAmount;
        address[] path;
        bytes userScript;
        ScriptTypes scriptType;
        bytes lockerLockingScript;
        uint256 thirdParty;
    }

    // Events

    event NewSwapAndUnwrap(
        uint256 chainId,
        address exchangeConnector,
        address inputToken,
        uint256 inputAmount,
        address indexed userTargetAddress,
        bytes userScript,
        ScriptTypes scriptType,
        address lockerTargetAddress,
        uint256 requestIdOfLocker,
        address[] path
    );

    event FailedSwapAndUnwrap(
        uint256 chainId,
        address exchangeConnector,
        address inputToken,
        uint256 inputAmount,
        address indexed userTargetAddress,
        bytes userScript,
        ScriptTypes scriptType,
        address[] path
    );

    event MsgReceived(
        string functionName,
        uint256 uniqueCounter,
        uint256 chainId,
        bytes data
    );

    event AcrossUpdated(address oldAcross, address newAcross);

    event EthConnectorUpdated(address oldEthConnector, address newEthConnector);

    event BurnRouterUpdated(address oldBurnRouter, address newBurnRouter);

    event LockersProxyUpdated(address oldLockersProxy, address newLockersProxy);

    // Read-only functions

    function lockersProxy() external view returns (address);

    function burnRouterProxy() external view returns (address);

    function sourceChainConnector() external view returns (address);

    function across() external view returns (address);

    function sourceChainId() external view returns (uint256);

    function failedReqs(address, address) external returns (uint256);

    // State-changing functions

    function setAcross(address _across) external;

    function setSourceChainConnector(address _sourceChainConnector) external;

    function setBurnRouterProxy(address _burnRouterProxy) external;

    function setLockersProxy(address _lockersProxy) external;

    function withdrawFundsToEth(
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
