// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.7.6;

interface ICCExchangeRouter {
    // structures
    struct request{
        uint bitcoinAmount; //total amount of tokenA (exchange + fee)
        uint exchangeAmount;
        uint remainedInputAmount;
        address exchangeToken; // exchangeToken pool address on DEX
        bool isFixedToken;
        address bitcoinRecipient;
        address exchangeRecipientAddress;
        address[] path;
        uint teleporterFee;
        address teleporterAddress;
        uint deadline;
        bool isExchange;
        uint speed;
    }

    // events
    event CCExchange(address user, address inputToken, address outputToken, uint inputAmount, uint outputAmount, uint speed);

    // read-only functions
    function owner() external view returns (address);
    function liquidityPoolFactory() external view returns(address);
    function WAVAX() external view returns(address);
    function exchangeRouter() external view returns(address);
    function wrappedBitcoin() external view returns(address);

    // state-changing functions
    function changeOwner(address _owner) external;
    function setInstantRouter (address _instantRouter) external;
    function setBitcoinTeleporter (address _bitcoinTeleporter) external;
    function setCCTransferRouter (address _ccTransferRouter) external;
    function setExchangeRouter (address _exchangeRouter) external;
    function setWrappedBitcoin (address _wrappedBitcoin) external;
    function ccExchange(
        bytes4 version,
        bytes memory vin,
        bytes calldata vout,
        bytes4 locktime,
        uint256 blockNumber,
        bytes calldata intermediateNodes,
        uint index,
        bool payWithTDT
    ) external;
    function instantCCExchangeWithPermit(
        address signer,
        bytes memory signature,
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address receiver,
        uint deadline
    ) external;
}
