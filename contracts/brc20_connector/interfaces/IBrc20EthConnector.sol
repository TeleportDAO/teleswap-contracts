// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";

interface IBrc20EthConnector {
    // Structs

    struct UserScriptAndType {
        bytes userScript;
        ScriptTypes scriptType;
    }

    // Events

    event MsgSent(
        uint256 uniqueCounter,
        bytes data,
        address sourceChainInputToken,
        uint256 amount
    );

    event AcrossUpdated(address oldAcross, address newAcross);

    event TargetChainConnectorUpdated(
        address oldTargetChainConnector,
        address newTargetChainConnector
    );

    event TargetChainTeleBTCUpdated(address oldTeleBtc, address newTeleBtc);

    event WrappedNativeTokenUpdated(
        address oldWrappedNativeToken,
        address newWrappedNativeToken
    );

    function setAcross(address _across) external;

    function setTargetChainConnectorProxy(
        address _targetChainConnector
    ) external;

    function setWrappedNativeToken(address _wrappedNativeToken) external;

    function swapAndUnwrap(
        address _token,
        uint256 _thirdPartyId,
        uint256 _tokenId,
        uint256 _appId,
        uint256 _amount,
        uint256 _inputAmount,
        address[] calldata _path,
        UserScriptAndType calldata _userScript,
        int64 _relayerFeePercentage
    ) external payable;

    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external;
}
