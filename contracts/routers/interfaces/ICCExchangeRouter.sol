// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

interface ICCExchangeRouter {
    // Structures

    /// @notice                    Structure for recording cross-chain exchange requests
    /// @param appId               Application id that user wants to use
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
    }

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

    /// @notice                      Emits when appId for an exchange connector is set
    /// @param appId                 Assigned application id to exchange
    /// @param exchangeConnector     Address of exchange connector contract
    event SetExchangeConnector(
        uint appId,
        address exchangeConnector
    );

    // Read-only functions
    
    function startingBlockNumber() external view returns (uint);

    function protocolPercentageFee() external view returns (uint);
    
    function chainId() external view returns (uint);

    function relay() external view returns (address);

    function instantRouter() external view returns (address);

    function lockers() external view returns (address);

    function teleBTC() external view returns (address);

    function isRequestUsed(bytes32 _txId) external view returns (bool);

    function exchangeConnector(uint appId) external view returns (address);

    function treasury() external view returns (address);

    // State-changing functions

    function setRelay(address _relay) external;

    function setInstantRouter(address _instantRouter) external;

    function setLockers(address _lockers) external;

    function setTeleBTC(address _teleBTC) external;

    function setExchangeConnector(uint _appId, address _exchangeConnector) external;

	function setTreasury(address _treasury) external;

	function setProtocolPercentageFee(uint _protocolPercentageFee) external;

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
        uint index,
        address lockerBitcoinDecodedAddress
    ) external payable returns(bool);
}