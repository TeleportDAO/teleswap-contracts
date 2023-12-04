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


    function addSupportedExchangeToken(address _token) external;

    function removeSupportedExchangeToken(address _token) external;

    function updateAcross(address _across) external;
}