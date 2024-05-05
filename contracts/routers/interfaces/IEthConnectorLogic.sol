// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";

interface IEthConnectorLogic {
    // Events

    event MsgSent(
        uint256 uniqueCounter,
        string functionName,
        bytes data,
        address sourceChainInputToken,
        uint256 amount
    );

    event AcrossUpdated(address oldAcross, address newAcross);

    event PolygonConnectorUpdated(
        address oldPolygonConnector,
        address newPolygonConnector
    );

    event PolygonTeleBtcUpdated(
        address oldPolygonTeleBtc,
        address newPolygonTeleBtc
    );

    event WrappedNativeTokenUpdated(
        address oldWrappedNativeToken,
        address newWrappedNativeToken
    );

    function setAcross(address _across) external;

    function setPolygonConnectorProxy(address _polygonConnector) external;

    function setPolygonTeleBTC(address _polygonTeleBTC) external;

    function setWrappedNativeToken(address _wrappedNativeToken) external;

    function exchangeForBtcAcross(
        address _token,
        address _exchangeConnector,
        uint256[] calldata _amounts,
        address[] calldata _path,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        int64 _relayerFeePercentage,
        uint256 thirdParty
    ) external payable;

    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external;
}
