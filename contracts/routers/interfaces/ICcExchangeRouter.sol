// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

interface ICcExchangeRouter {

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

    /// @notice Structure for passing tx and its inclusion proof
    /// @param version of the transaction containing the user request
    /// @param vin Inputs of the transaction containing the user request
    /// @param vout Outputs of the transaction containing the user request
    /// @param locktime of the transaction containing the user request
    /// @param blockNumber Height of the block containing the user request
    /// @param intermediateNodes Merkle inclusion proof for transaction containing the user request
    /// @param index of transaction containing the user request in the block
    struct TxAndProof {
        bytes4 version;
        bytes vin;
        bytes vout;
        bytes4 locktime;
        uint256 blockNumber;
        bytes intermediateNodes;
        uint index;
    }

    // TODO add matic

    /// @notice Structure for storing filling requests
    /// @param startingTime First attemp to fill the request
    /// @param reqToken Requested exchange token
    /// @param lastUsedIdx Last used filler index
    /// @param remainingAmountOfLastFill Amount of unused tokens of last filler
    /// @param isWithdrawnLastFill True if last used filler has withdrawn unused tokens
    struct FillData {
        uint startingTime;
        address reqToken;
        uint lastUsedIdx;
        uint remainingAmountOfLastFill;
        bool isWithdrawnLastFill;
    }

    /// @notice Structure for storing fillers of a request
    /// @param index of filler between fillers
    /// @param token that filler used to fill
    /// @param amount that filler sent to fill
    struct FillerData {
        uint index;
        address token;
        uint amount;
    }

    /// @notice Structure for storing fillings
    /// @param prefixSum Cumulative sum of fillings
    /// @param currentIndex Next filler index
    struct PrefixFillSum {
        uint[] prefixSum;
        uint currentIndex;
    }

    // Events

	event NewFillerWithdrawInterval(
        uint oldFillerWithdrawInterval, 
        uint newFillerWithdrawInterval
    );

    /// @notice Emits when a new filler fills a request
    /// @param filler Address of filler
    /// @param txId Bitcoin request id
    /// @param token that used for filling
    /// @param amount that sent for filling
    event NewFill(
        address filler,
        bytes32 txId, 
        address token,
        uint amount
    );

    /// @notice Emits when a request is filled for the first time
    /// @param txId Bitcoin request id
    /// @param time Filling starting time 
    event FillStarted(
        bytes32 txId,
        uint time
    );

    /// @notice                     Emits when a cc exchange request gets done
    /// @param user                 Exchange recipient address
    /// @param speed                Speed of the request (normal or instant)
    /// @param teleporter          Address of teleporter who submitted the request
    /// @param teleporterFee        Amount of fee that is paid to Teleporter (tx, relayer and teleporter fees)
    event CCExchange(
        bytes lockerLockingScript,
        uint lockerScriptType,
        address lockerTargetAddress,
        address indexed user,
        address[2] inputAndOutputToken,
        uint[2] inputAndOutputAmount,
        uint indexed speed,
        address indexed teleporter,
        uint teleporterFee,
        bytes32 bitcoinTxId,
        uint appId
    );

    /// @notice                     Emits when a cc exchange request fails
    /// @dev                        In this case, instead of excahnging tokens,
    ///                             we mint teleBTC and send it to the user
    /// @param recipientAddress     Exchange recipient address
    /// @param speed                Speed of the request (normal or instant)
    /// @param teleporter          Address of teleporter who submitted the request
    /// @param teleporterFee        Amount of fee that is paid to Teleporter (tx, relayer and teleporter fees)
    event FailedCCExchange(
        bytes lockerLockingScript,
        uint lockerScriptType,
        address lockerTargetAddress,
        address indexed recipientAddress,
        address[2] inputAndOutputToken,
        uint[2] inputAndOutputAmount,
        uint indexed speed,
        address indexed teleporter,
        uint teleporterFee,
        bytes32 bitcoinTxId,
        uint appId
    );

    /// @notice                      Emits when appId for an exchange connector is set
    /// @param appId                 Assigned application id to exchange
    /// @param exchangeConnector     Address of exchange connector contract
    event SetExchangeConnector(
        uint appId,
        address exchangeConnector
    );

    /// @notice                     Emits when changes made to relay address
    event NewRelay (
        address oldRelay, 
        address newRelay
    );

    /// @notice                     Emits when changes made to InstantRouter address
    event NewInstantRouter (
        address oldInstantRouter, 
        address newInstantRouter
    );

    /// @notice                     Emits when changes made to Lockers address
    event NewLockers (
        address oldLockers, 
        address newLockers
    );

    /// @notice                     Emits when changes made to TeleBTC address
    event NewTeleBTC (
        address oldTeleBTC, 
        address newTeleBTC
    );

    /// @notice                     Emits when changes made to protocol percentage fee
    event NewProtocolPercentageFee (
        uint oldProtocolPercentageFee, 
        uint newProtocolPercentageFee
    );

    /// @notice                     Emits when changes made to Treasury address
    event NewTreasury (
        address oldTreasury, 
        address newTreasury
    );

    // Read-only functions
    
    function isRequestUsed(bytes32 _txId) external view returns (bool);

    // Read-only functions
    
    function startingBlockNumber() external view returns (uint);

    function protocolPercentageFee() external view returns (uint);
    
    function chainId() external view returns (uint);

    function relay() external view returns (address);

    function instantRouter() external view returns (address);

    function lockers() external view returns (address);

    function teleBTC() external view returns (address);

    function exchangeConnector(uint appId) external view returns (address);

    function treasury() external view returns (address);

    // State-changing functions

    function setStartingBlockNumber(uint _startingBlockNumber) external;

    function setRelay(address _relay) external;

    function setInstantRouter(address _instantRouter) external;

    function setLockers(address _lockers) external;

    function setTeleBTC(address _teleBTC) external;

    function setExchangeConnector(uint _appId, address _exchangeConnector) external;

	function setTreasury(address _treasury) external;

	function setProtocolPercentageFee(uint _protocolPercentageFee) external;

    function setFillerWithdrawInterval(uint _fillerWithdrawInterval) external;

    function ccExchange(
        // bytes4 _version,
        // bytes memory _vin,
        // bytes calldata _vout,
        // bytes4 _locktime,
        // // ^ Bitcoin tx
        // uint256 _blockNumber, // Bitcoin block number
        // bytes calldata _intermediateNodes, // Merkle proof
        // uint _index,
        TxAndProof memory _txAndProof,
        bytes calldata _lockerLockingScript
    ) external payable returns(bool);

    function fillTx(
        bytes32 _txId,
        address _token,
        uint _amount
    ) external payable;

    function returnUnusedFill(
        bytes32 _txId
    ) external returns (bool);

    function getTeleBtcForFill(
       bytes32 _txId
    ) external returns (bool);
}