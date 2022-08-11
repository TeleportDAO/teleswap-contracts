// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICCBurnRouter {

	// Structures

    /// @notice                 	Structure for recording burn requests
    /// @param amount         		Amount of burnt tokens
    /// @param remainedAmount   	Amount that user gets (after paying fees)
    /// @param sender       		Address of user who requests burning
    /// @param userPubKeyHash   Public key hash of the user on Bitcoin
    /// @param isScriptHash   		Whether the user's Bitcoin address is script hash or pubKey hash
    /// @param isSegwit			   	Whether the user's Bitcoin address is Segwit or nonSegwit
    /// @param deadline         	Deadline of lockers for executing the request
    /// @param isTransferred    	True if the request has been executed
    /// @param locker		    	The locker assigned to this burn request who should execute it
	struct burnRequest {
		uint amount;
		uint remainedAmount;
		address sender;
		address userPubKeyHash;
		bool isScriptHash;
		bool isSegwit;
		uint deadline;
		bool isTransferred;
  	}

  	// Events

	/// @notice                 		Emits when a burn request gets submitted
    /// @param userTargetAddress        Target address of the user
    /// @param userPubKeyHash       Public key hash of the user on Bitcoin
	/// @param isScriptHash   			Whether the user's Bitcoin address is script hash or pubKey hash
    /// @param isSegwit			   		Whether the user's Bitcoin address is Segwit or nonSegwit
    /// @param amount         			Amount of burnt tokens
    /// @param remainedAmount   		Amount that user gets (after paying fees)
	/// @param lockerTargetAddress		Locker's address on the target chain
    /// @param index       				The index of a request for a locker
    /// @param deadline         		Deadline of lockers for executing the request
  	event CCBurn(
		address indexed userTargetAddress,
		address userPubKeyHash,
		bool isScriptHash,
    	bool isSegwit,
		uint amount, 
		uint remainedAmount, 
		address indexed lockerTargetAddress,
		uint index, 
		uint indexed deadline
	);

	/// @notice                 		Emits when a burn request gets executed
    /// @param userTargetAddress        Target address of the user
    /// @param userPubKeyHash       Public key hash of the user on Bitcoin
    /// @param remainedAmount   		Amount that user gets (after paying fees)
	/// @param lockerTargetAddress		Locker's address on the target chain
    /// @param index       				The index of a request for a locker
	event PaidCCBurn(
		address indexed userTargetAddress, 
		address userPubKeyHash, 
		uint remainedAmount, 
		address indexed lockerTargetAddress, 
		uint index
	);

	/// @notice                 		Emits when a locker gets slashed for withdrawing BTC
	/// @param _lockerTargetAddress		Locker's address on the target chain
	/// @param _blockNumber				Block number of the malicious tx
	/// @param txId						Transaction ID of the malicious tx
	event LockerDispute(
        address _lockerTargetAddress,
    	uint _blockNumber,
        bytes32 txId
    );

	// Read-only functions

	function relay() external view returns (address);

	function lockers() external view returns (address);

	function teleBTC() external view returns (address);

	function treasury() external view returns (address);

	function transferDeadline() external view returns (uint);

	function protocolPercentageFee() external view returns (uint);

	function slasherPercentageReward() external view returns (uint);

	function bitcoinFee() external view returns (uint); // Bitcoin transaction fee

	function isTransferred(address _lockerTargetAddress, uint _index) external view returns (bool);

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
		address _userPubKeyHash,
		bool _isScriptHash,
    	bool _isSegwit,
		address _lockerTargetAddress
	) external returns (bool);

	function burnProof(
		bytes4 _version,
		bytes memory _vin,
		bytes calldata _vout,
		bytes4 _locktime,
		uint256 _blockNumber,
		bytes calldata _intermediateNodes,
		uint _index,
		address _lockerTargetAddress,
		uint _startIndex,
		uint _endIndex
	) external payable returns (bool);

	function disputeBurn(
		address _lockerTargetAddress, 
		uint[] memory _indices
	) external returns (bool);

	function disputeLocker(
		address _lockerTargetAddress,
        uint _inputIndex,
		bytes4 _version,
		bytes memory _vin,
		bytes calldata _vout,
		bytes4 _locktime,
		uint256 _blockNumber,
		bytes calldata _intermediateNodes,
		uint _index
	) external payable returns (bool);
}