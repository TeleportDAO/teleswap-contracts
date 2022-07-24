// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

interface ICCExchangeRouter {
    // Structures

    /// @notice                    Structure for recording cross-chain exchange requests
    /// @dev
    /// @param inputAmount         Amount of locked tokens on source chain
    /// @param outputAmount        Expected amount of output token
    /// @param isFixedToken        True if amount of input token is fixed
    /// @param recipientAddress    Address of exchange recipient
    /// @param fee                 Transfer fee (aggregated, paid to Teleporter)
    /// @param isUsed              Whether the tx is used or not
    /// @param path                Path of exchange tokens (includes input and output token addresses)
    /// @param deadline            Deadline of exchanging tokens
    /// @param speed               Speed of the request (normal or instant)
    struct ccExchangeRequest {
        uint inputAmount;
        uint outputAmount;
        bool isFixedToken;
        address recipientAddress;
        uint fee;
        bool isUsed;
        address[] path;
        uint deadline;
        uint speed;
    }


    // struct request{
    //     uint bitcoinAmount; //total amount of tokenA (exchange + fee)
    //     uint exchangeAmount;
    //     uint remainedInputAmount;
    //     address exchangeToken; // exchangeToken pool address on DEX
    //     bool isFixedToken;
    //     address bitcoinRecipient;
    //     address exchangeRecipientAddress;
    //     address[] path;
    //     uint teleporterFee;
    //     address teleporterAddress;
    //     uint deadline;
    //     bool isExchange;
    //     uint speed;
    // }


    // Events

    /// @notice                     Emits when a cc exchange request gets done
    /// @param user                 User recipient Address
    /// @param inputToken           Source chain token
    /// @param outputToken          Target chain token
    /// @param inputAmount          Amount of locked tokens on the source chain
    /// @param outputAmount         Amount of tokens to get on the target chain
    /// @param speed                Speed of the request (normal or instant)
    /// @param fee                  Transfer fee (aggregated, paid to Teleporter) paid by the user
    event CCExchange(
        address indexed user,
        address inputToken,
        address indexed outputToken,
        uint inputAmount,
        uint outputAmount,
        uint indexed speed,
        uint fee
    );

    /// @notice                     Emits when a cc exchange request fails
    /// @dev                        In this case, instead of excahnging tokens,
    ///                             we mint wrapped tokens and send it to the user
    /// @param recipientAddress     User recipient Address
    /// @param remainedInputAmount  Amount of wrapped tokens transferred to the user after paying fees
    event FailedCCExchange(
        address recipientAddress,
        uint remainedInputAmount
    );

    /// @notice                      Emits when a new exchange connector is added
    /// @param name                  Name of added exchange
    /// @param appId                 Assigned application id to exchange
    /// @param exchangeRouter        Address of exchange router contract
    /// @param exchangeConnector     Address of exchange connector contract
    event AddExchangeConnector(
        string name,
        uint appId,
        address exchangeRouter,
        address exchangeConnector
    );

    /// @notice                         Emits when address of exchange connector is updated
    /// @param name                     Name of updated exchange
    /// @param appId                    Assigned application id to exchange
    /// @param oldExchangeRouter        Previous address of exchange router contract
    /// @param oldExchangeConnector     Previous address of exchange connector contract
    /// @param newExchangeRouter        New address of exchange router contract
    /// @param newExchangeConnector     New address of exchange connector contract
    event UpdateExchangeConnector(
        string name,
        uint appId,
        address oldExchangeRouter,
        address oldExchangeConnector,
        address newExchangeRouter,
        address newExchangeConnector
    );

    /// @notice                      Emits when an exchange connector is removed
    /// @param name                  Name of removed exchange
    /// @param appId                 Assigned application id to exchange
    /// @param exchangeRouter        Address of exchange router contract
    /// @param exchangeConnector     Address of exchange connector contract
    event RemoveExchangeConnector(
        string name,
        uint appId,
        address exchangeRouter,
        address exchangeConnector
    );

    // event CCExchange(address user, address inputToken, address outputToken, uint inputAmount, uint outputAmount, uint speed);

    // Read-only functions

    function relay() external view returns (address);

    function instantRouter() external view returns (address);

    function lockers() external view returns (address);

    // function wrappedNativeToken() external view returns (address);

    function teleBTC() external view returns (address);

    function isRequestUsed(bytes32 _txId) external view returns (bool);

    function exchangeConnectors(uint appId) external view returns (address);


    // function owner() external view returns (address);
    // function liquidityPoolFactory() external view returns(address);
    // function WAVAX() external view returns(address);
    // function exchangeRouter() external view returns(address);
    // function wrappedBitcoin() external view returns(address);

    // State-changing functions

    function setRelay(address _relay) external;

    function setInstantRouter(address _instantRouter) external;

    function setLockers(address _lockers) external;

    // function setWrappedNativeToken() external;

    // function setExchangeRouter(address _exchangeRouter) external;

    function setTeleBTC(address _teleBTC) external;


    // TODO: Add the 3 following functions to the cc exchange
    // function addExchangeConnector(address _exchangeConnector) external returns (uint);

    // function updateExchangeConnector(uint appId, address _exchangeConnector) external returns (bool);

    // function removeExchangeConnector(uint appId) external returns (bool);

    function ccExchange(
    // Bitcoin tx
        bytes4 version,
        bytes memory vin,
        bytes calldata vout,
        bytes4 locktime,
    // Bitcoin block number
        uint256 blockNumber,
    // Merkle proof
        bytes calldata intermediateNodes,
        uint index
    ) external returns(bool);



    // function changeOwner(address _owner) external;
    // function setInstantRouter (address _instantRouter) external;
    // function setBitcoinTeleporter (address _bitcoinTeleporter) external;
    // function setCCTransferRouter (address _ccTransferRouter) external;
    // function setExchangeRouter (address _exchangeRouter) external;
    // function setWrappedBitcoin (address _wrappedBitcoin) external;
    // function ccExchange(
    //     bytes4 version,
    //     bytes memory vin,
    //     bytes calldata vout,
    //     bytes4 locktime,
    //     uint256 blockNumber,
    //     bytes calldata intermediateNodes,
    //     uint index,
    //     bool payWithTDT
    // ) external;
    // function instantCCExchangeWithPermit(
    //     address signer,
    //     bytes memory signature,
    //     uint amountIn,
    //     uint amountOutMin,
    //     address[] memory path,
    //     address receiver,
    //     uint deadline
    // ) external;
}