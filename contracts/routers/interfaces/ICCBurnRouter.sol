// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "../../types/ScriptTypesEnum.sol";

interface ICCBurnRouter {

	// Structures

    /// @notice Structure for recording cc burn requests
    /// @param amount of tokens that user wants to burn
    /// @param burntAmount that user will receive (after reducing fees from amount)
    /// @param sender Address of user who requests burning
    /// @param userScript Script hash of the user on Bitcoin
    /// @param deadline of locker for executing the request
    /// @param isTransferred True if the request has been processed
    /// @param scriptType The script type of the user
    /// @param requestIdOfLocker The index of the request for a specific locker
	struct burnRequest {
		uint amount;
		uint burntAmount;
		address sender;
		bytes userScript;
		uint deadline;
		bool isTransferred;
		ScriptTypes scriptType;
		uint requestIdOfLocker;
  	}

  	// Events

	/// @notice Emits when a burn request gets submitted
    /// @param userTargetAddress Address of the user
    /// @param userScript Script of user on Bitcoin
    /// @param scriptType Script type of the user (for bitcoin address)
    /// @param inputAmount Amount of input token (0 if input token is teleBTC)
    /// @param inputToken Address of token that will be exchanged for teleBTC (address(0) if input token is teleBTC)
	/// @param teleBTCAmount amount of teleBTC that user sent OR Amount of teleBTC after exchanging
    /// @param burntAmount that user will receive (after reducing fees)
	/// @param lockerTargetAddress Address of Locker
	/// @param requestIdOfLocker Index of request between Locker's burn requests
	/// @param deadline of Locker for executing the request (in terms of Bitcoin blocks)
  	event CCBurn(
		address indexed userTargetAddress,
		bytes userScript,
		ScriptTypes scriptType,
		uint inputAmount,
		address inputToken,
		uint teleBTCAmount, 
		uint burntAmount,
		address lockerTargetAddress,
		uint requestIdOfLocker,
		uint indexed deadline
	);

	/// @notice Emits when a burn proof is provided
    /// @param lockerTargetAddress Address of Locker
    /// @param requestIdOfLocker Index of paid request of among Locker's requests
    /// @param bitcoinTxId The hash of tx that paid a burn request
	/// @param bitcoinTxOutputIndex The output index in tx
	event PaidCCBurn(
		address indexed lockerTargetAddress,
		uint requestIdOfLocker,
		bytes32 bitcoinTxId,
		uint bitcoinTxOutputIndex
	);

	/// @notice  Emits when a locker gets slashed for withdrawing BTC without proper reason
	/// @param _lockerTargetAddress	Locker's address on the target chain
	/// @param _blockNumber	Block number of the malicious tx
	/// @param txId	Transaction ID of the malicious tx
	/// @param amount Slashed amount
	event LockerDispute(
        address _lockerTargetAddress,
		bytes lockerLockingScript,
    	uint _blockNumber,
        bytes32 txId,
		uint amount
    );

	event BurnDispute(
		address indexed userTargetAddress,
		address indexed _lockerTargetAddress,
		bytes lockerLockingScript,
		uint requestIdOfLocker
	);

	/// @notice Emits when relay address is updated
    event NewRelay(
        address oldRelay, 
        address newRelay
    );

	/// @notice Emits when treasury address is updated
    event NewTreasury(
        address oldTreasury, 
        address newTreasury
    );

	/// @notice Emits when lockers address is updated
    event NewLockers(
        address oldLockers, 
        address newLockers
    );

	/// @notice Emits when TeleBTC address is updated
    event NewTeleBTC(
        address oldTeleBTC, 
        address newTeleBTC
    );

	/// @notice Emits when transfer deadline is updated
    event NewTransferDeadline(
        uint oldTransferDeadline, 
        uint newTransferDeadline
    );

	/// @notice Emits when percentage fee is updated
    event NewProtocolPercentageFee(
        uint oldProtocolPercentageFee, 
        uint newProtocolPercentageFee
    );

	/// @notice Emits when slasher percentage fee is updated
    event NewSlasherPercentageFee(
        uint oldSlasherPercentageFee, 
        uint newSlasherPercentageFee
    );

	/// @notice Emits when bitcoin fee is updated
    event NewBitcoinFee(
        uint oldBitcoinFee, 
        uint newBitcoinFee
    );

	// Read-only functions

    function startingBlockNumber() external view returns (uint);
	
	function relay() external view returns (address);

	function lockers() external view returns (address);

	function teleBTC() external view returns (address);

	function treasury() external view returns (address);

	function transferDeadline() external view returns (uint);

	function protocolPercentageFee() external view returns (uint);

	function slasherPercentageReward() external view returns (uint);

	function bitcoinFee() external view returns (uint); // Bitcoin transaction fee

	function isTransferred(address _lockerTargetAddress, uint _index) external view returns (bool);

	function isUsedAsBurnProof(bytes32 _txId) external view returns (bool);

	// State-changing functions

	function setRelay(address _relay) external;

	function setLockers(address _lockers) external;

	function setTeleBTC(address _teleBTC) external;

	function setTreasury(address _treasury) external;

	function setTransferDeadline(uint _transferDeadline) external;

	function setProtocolPercentageFee(uint _protocolPercentageFee) external;

	function setSlasherPercentageReward(uint _slasherPercentageReward) external;

	function setBitcoinFee(uint _bitcoinFee) external;

	function ccBurn(
		uint _amount, 
		bytes calldata _userScript,
		ScriptTypes _scriptType,
		bytes calldata _lockerLockingScript
	) external returns (uint);

    function ccExchangeAndBurn(
        address _exchangeConnector,
        uint[] calldata _amounts,
        bool _isFixedToken,
        address[] calldata _path,
        uint256 _deadline, 
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript
	) external returns (uint);

	function burnProof(
		bytes4 _version,
		bytes memory _vin,
		bytes memory _vout,
		bytes4 _locktime,
		uint256 _blockNumber,
		bytes memory _intermediateNodes,
		uint _index,
		bytes memory _lockerLockingScript,
        uint[] memory _burnReqIndexes,
        uint[] memory _voutIndexes
	) external payable returns (bool);

	function disputeBurn(
		bytes calldata _lockerLockingScript,
		uint[] memory _indices
	) external;

    function disputeLocker(
        bytes memory _lockerLockingScript,
        bytes4[] memory _versions, // [inputTxVersion, outputTxVersion]
        bytes memory _inputVin,
        bytes memory _inputVout,
        bytes memory _outputVin,
        bytes memory _outputVout,
        bytes4[] memory _locktimes, // [inputTxLocktime, outputTxLocktime]
        bytes memory _inputIntermediateNodes,
        uint[] memory _indexesAndBlockNumbers 
		// ^ [inputIndex, inputTxIndex, outputTxIndex, inputTxBlockNumber, outputTxBlockNumber]
    ) external payable;
}