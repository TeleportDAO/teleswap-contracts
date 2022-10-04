// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICCTransferRouter {

	// Structures

	/// @notice                    Structure for recording cross-chain transfer requests
	/// @param inputAmount         Amount of locked BTC on source chain
	/// @param recipientAddress    Address of transfer recipient
	/// @param fee                 Amount of fee that is paid to Teleporter (tx, relayer and teleporter fees)
	/// @param speed               Speed of the request (normal or instant)
	/// @param isUsed              Whether the tx is used or not
	struct ccTransferRequest {
		uint inputAmount;
		address recipientAddress;
		uint fee;
		uint256 speed;
		bool isUsed;
	}

	// Events

	/// @notice                    	Emits when a cc transfer request gets done
	/// @param lockerLockingScript  Locking script of the locker on bitcoin network
	/// @param lockerScriptType     Script type of the locker locking script
	/// @param lockerTargetAddress  Address of the locker on EVM based target chain
	/// @param user                	Address of teleBTC recipient
	/// @param inputAmount         	Amount of tokens that user locked on source chain
	/// @param receivedAmount      	Amount of tokens that user receives
	/// @param speed               	Speed of the request (normal or instant)
	/// @param teleporter          	Address of teleporter who submitted the request
	/// @param teleporterFee       	Amount of fee that is paid to Teleporter (tx, relayer and teleporter fees)
	/// @param relayFee       	   	Amount of fee that is paid to relay contract
	/// @param protocolFee         	Amount of fee that is paid to the protocol
	/// @param bitcoinTxId         	Address of teleporter who submitted the request
	event CCTransfer(
		bytes indexed lockerLockingScript,
		uint lockerScriptType,
		address lockerTargetAddress,
		address indexed user,
		uint inputAmount,
		uint receivedAmount,
		uint indexed speed,
		address teleporter,
		uint teleporterFee,
		uint relayFee,
		uint protocolFee,
		bytes32 bitcoinTxId
	);

	// Read-only functions

	function startingBlockNumber() external view returns (uint);

	function protocolPercentageFee() external view returns (uint);

	function chainId() external view returns (uint);

	function appId() external view returns (uint);

	function relay() external view returns (address);

	function instantRouter() external view returns (address);

	function lockers() external view returns (address);

	function teleBTC() external view returns (address);

	function treasury() external view returns (address);

	function isRequestUsed(bytes32 _txId) external view returns (bool);

	// State-changing functions

	function setRelay(address _relay) external;

	function setInstantRouter(address _instantRouter) external;

	function setLockers(address _lockers) external;

	function setTeleBTC(address _teleBTC) external;

	function setTreasury(address _treasury) external;

	function setProtocolPercentageFee(uint _protocolPercentageFee) external;

	function ccTransfer(
	// Bitcoin tx
		bytes4 _version,
		bytes memory _vin,
		bytes calldata _vout,
		bytes4 _locktime,
	// Bitcoin block number
		uint256 _blockNumber,
	// Merkle proof
		bytes calldata _intermediateNodes,
		uint _index,
		bytes calldata _lockerLockingScript
	) external payable returns (bool);
}