pragma solidity 0.8.0;

interface IBitcoinRelay {
    // structures

    /// @notice                 	Structure for recording block header
    /// @param selfHash             Hash of block header
    /// @param parentHash          	Hash of parent block header
    /// @param merkleRoot       	Merkle root of transactions in the block
    /// @param relayer              Address of relayer who submitted the block header
    struct blockHeader {
        bytes32 selfHash;
        bytes32 parentHash;
        bytes32 merkleRoot;
        address relayer;
    }

    // events

    /// @notice                     Emits when a block header is added
    /// @param height               Height of submitted header
    /// @param selfHash             Hash of submitted header
    /// @param parentHash           Parent hash of submitted header
    /// @param relayer              Address of relayer who submitted the block header
    event BlockAdded(
        uint indexed height,
        bytes32 selfHash,
        bytes32 indexed parentHash,
        address indexed relayer
    );

    /// @notice                     Emits when a block header gets finalized
    /// @param height               Height of the header
    /// @param selfHash             Hash of the header
    /// @param parentHash           Parent hash of the header
    /// @param relayer              Address of relayer who submitted the block header
    /// @param rewardAmountTNT      Amount of reward that the relayer receives in target native token
    /// @param rewardAmountTDT      Amount of reward that the relayer receives in TDT
    event BlockFinalized(
        uint indexed height,
        bytes32 selfHash,
        bytes32 parentHash,
        address indexed relayer,
        uint rewardAmountTNT,
        uint rewardAmountTDT
    );

    // Read-only functions

    function relayGenesisHash() external view returns (bytes32);

    function initialHeight() external view returns(uint);

    function lastSubmittedHeight() external view returns(uint);

    function finalizationParameter() external view returns(uint);

    function TeleportDAOToken() external view returns(address);

    function relayerPercentageFee() external view returns(uint);

    function epochLength() external view returns(uint);

    function lastEpochQueries() external view returns(uint);

    function currentEpochQueries() external view returns(uint);

    function baseQueries() external view returns(uint);

    function submissionGasUsed() external view returns(uint);

    function exchangeRouter() external view returns(address);

    function wrappedNativeToken() external view returns(address);

    function getBlockHeaderHash(uint height, uint index) external view returns(bytes32);

    function getNumberOfSubmittedHeaders(uint height) external view returns (uint);

    function availableTDT() external view returns(uint);

    function availableTNT() external view returns(uint);

    function findHeight(bytes32 _hash) external view returns (uint256);

    function findAncestor(bytes32 _hash, uint256 _offset) external view returns (bytes32); // see if it's needed

    function isAncestor(bytes32 _ancestor, bytes32 _descendant, uint256 _limit) external view returns (bool); // see if it's needed

    function rewardAmountInTDT() external view returns (uint);


    // State-changing functions
    function pauseRelay() external;

    function unPauseRelay() external;

    function setRewardAmountInTDT(uint _rewardAmountInTDT) external;

    function setFinalizationParameter(uint _finalizationParameter) external;

    function setRelayerPercentageFee(uint _relayerPercentageFee) external;

    function setEpochLength(uint _epochLength) external;

    function setBaseQueries(uint _baseQueries) external;

    function setSubmissionGasUsed(uint _submissionGasUsed) external;

    function setExchangeRouter(address _exchangeRouter) external;

    function checkTxProof(
        bytes32 txid,
        uint blockHeight,
        bytes calldata intermediateNodes,
        uint index
    ) external payable returns (bool);

    function addHeaders(bytes calldata _anchor, bytes calldata _headers) external returns (bool);

    function addHeadersWithRetarget(
        bytes calldata _oldPeriodStartHeader,
        bytes calldata _oldPeriodEndHeader,
        bytes calldata _headers
    ) external returns (bool);

}