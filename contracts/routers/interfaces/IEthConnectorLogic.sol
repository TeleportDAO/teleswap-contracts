// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";
import "@teleportdao/teleordinal/contracts/TeleOrdinalLib.sol";

interface IEthConnectorLogic {

    // Events

    event MsgSent(
        uint uniqueCounter,
        string functionName,
        bytes data,
        address sourceChainInputToken, 
        uint amount
    );

    event MinAmountUpdated(
        address token, 
        uint minAmount
    );

    event MinModifierUpdated( 
        uint oldMinModifier,
        uint newMinModifier
    );

    event AcrossUpdated( 
        address oldAcross,
        address newAcross
    );

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

    function setMinAmount(address _token, uint _minAmount) external;

    function setMinModifier(uint _minModifier) external;

    function setPolygonTeleBTC(address _polygonTeleBTC) external;

    function setWrappedNativeToken(address _wrappedNativeToken) external;

    function exchangeForBtcAcross(
        address _token,
        address _exchangeConnector,
        uint[] calldata _amounts,
        address[] calldata _path,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        int64 _relayerFeePercentage
	) external;

    function emergencyWithdraw(
        address _token,
        address _to,
        uint _amount
    ) external;

}