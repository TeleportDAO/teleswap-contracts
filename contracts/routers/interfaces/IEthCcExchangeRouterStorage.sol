// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./ICcExchangeRouterStorage.sol";

interface IEthCcExchangeRouterStorage is ICcExchangeRouterStorage {
    // Structures

    /// @notice Structure for recording cross-chain exchange requests
    /// @param appId that user wants to use (which DEX)
    /// @param inputAmount Amount of locked BTC on source chain
    /// @param outputAmount Amount of output token
    /// @param isFixedToken True if amount of input token is fixed
    /// @param recipientAddress Address of exchange recipient
    /// @param fee Amount of fee that is paid to Teleporter (for tx, relayer and teleporter fees)
    /// @param isUsed True if tx has been submitted before
    /// @param path Exchange path from input token to output token
    /// @param deadline for exchanging tokens
    /// @param speed of the request (normal or instant)
    /// @param speed of the request (normal or instant)
    /// @param isTransferedToEth indicates that the required exchange is obtained and transferd or not
    /// @param remainedInputAmount Amount of obtained TELEBTC on target chain
    struct ethCcExchangeRequest {
        uint appId;
        uint inputAmount;
        uint outputAmount;
        bool isFixedToken;
        address recipientAddress;
        uint fee;
        bool isUsed;
        address[] path;
        uint deadline;
        uint speed;
        bool isTransferedToEth;
        uint remainedInputAmount;
    }

    function isExchangeTokenSupported(address _exchangeToken) external view returns (bool);

    function accross() external view returns (address);
}