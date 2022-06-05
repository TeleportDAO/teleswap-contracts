pragma solidity 0.7.6;

interface IBitcoinRelay {
    // structures
    struct blockHeader{
        bytes32 selfHash;
		bytes32 parentHash;
		bytes32 merkleRoot;
    }

    // events
    event BlockAdded(uint256 firstHeight, uint256 lastHeight, address relayer, uint rewardAmount, bool isTDT);
    event NewTip(bytes32 indexed _from, bytes32 indexed _to, bytes32 indexed _gcd);

    // read-only functions
    function owner() external view returns (address);
    function getCurrentEpochDifficulty() external view returns (uint256);
    function getPrevEpochDifficulty() external view returns (uint256);
    function getRelayGenesis() external view returns (bytes32);
    function getBestKnownDigest() external view returns (bytes32);
    function getLastReorgCommonAncestor() external view returns (bytes32);
    function initialHeight() external view returns(uint);
    function lastSubmittedHeight() external view returns(uint);
    function finalizationParameter() external view returns(uint);
    function TeleportDAOToken() external view returns(address);
	function feeRatio() external view returns(uint);
	function epochLength() external view returns(uint);
	function lastEpochQueries() external view returns(uint);
	function baseQueries() external view returns(uint);
	function submissionGasUsed() external view returns(uint);
	// function chain(uint) external returns(blockHeader[] memory);
	function getBlockHeaderHash (uint height, uint index) external returns(bytes32);
	function getNumberOfSubmittedHeaders (uint height) external view returns (uint);
	// function availableTDT() external view returns(uint);
    // function availableTNT() external view returns(uint);
	function lastBuyBack() external view returns(uint);
	function buyBackPeriod() external view returns(uint);
	function exchangeRouter() external view returns(address);
	function WAVAX() external view returns(address);
    function findHeight(bytes32 _digest) external view returns (uint256);
    function findAncestor(bytes32 _digest, uint256 _offset) external view returns (bytes32);
    function isAncestor(bytes32 _ancestor, bytes32 _descendant, uint256 _limit) external view returns (bool);

    // state-changing functions
    function changeOwner(address _owner) external;
    function setFinalizationParameter(uint _finalizationParameter) external;
    function setFeeRatio(uint _feeRatio) external;
    function setEpochLength(uint _epochLength) external;
    function setBuyBackPeriod(uint _buyBackPeriod) external;
    function setBaseQueries(uint _baseQueries) external;
    function setSubmissionGasUsed(uint _submissionGasUsed) external;
    function setExchangeRouter(address _exchangeRouter) external;
    function checkTxProof(
        bytes32 txid,
        uint blockHeight,
        bytes calldata intermediateNodes,
        uint index,
        bool payWithTDT,
        uint neededConfirmations
    ) external returns (bool);
    function addHeaders(bytes calldata _anchor, bytes calldata _headers) external returns (bool);
    function addHeadersWithRetarget(
        bytes calldata _oldPeriodStartHeader,
        bytes calldata _oldPeriodEndHeader,
        bytes calldata _headers
    ) external returns (bool);
    function markNewHeaviest(
        bytes32 _ancestor,
        bytes calldata _currentBest,
        bytes calldata _newBest,
        uint256 _limit
    ) external returns (bool);
    function calculateTxId (
        bytes4 _version,
        bytes memory _vin,
        bytes memory _vout,
        bytes4 _locktime
    ) external returns(bytes32);

}