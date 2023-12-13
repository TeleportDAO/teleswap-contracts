// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./ICcExchangeRouter.sol";

interface IEthCcExchangeRouter is ICcExchangeRouter {

    event ExchangeTokenAdded (
        address newExchangeToke
    );

    event ExchangeTokenRemoved (
        address oldExchangeToke
    );

    event AcrossUpdated (
        address oldAcross,
        address newAcross
    );

    event AcrossRelayerFeeUpdated (
        int64 oldAcrossFee,
        int64 newAcrossFee
    );

    event BurnRouterUpdated (
        address oldBurnRouter,
        address newBurnRouter
    );


    function addSupportedExchangeToken(address _token) external;

    function removeSupportedExchangeToken(address _token) external;

    function updateAcross(address _across) external;

    function updateAcrossRelayerFee(int64 _fee) external;

    function updateBurnRouter(address _burnRouter) external;

    function withdrawFailedCcExchangeToBTC(
        bytes memory _message,
        bytes32 r,
        bytes32 s,
        uint8 v,
        // extract from user's message
        // bytes memory _userScript,
        // ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript
    ) external returns (bool);


    function reDoFailedCcExchange(
        bytes memory _message,
        bytes32 r,
        bytes32 s,
        uint8 v
        // extract from user's message
        // outputAmount,
        // deadline,
    ) external returns (bool);
}