// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICCTransferRouter {

	// Structures

	/// @notice                    Structure for recording cross-chain transfer requests
	/// @dev
	/// @param inputAmount         Amount of locked tokens on source chain
	/// @param recipientAddress    Address of transfer recipient
	/// @param fee                 Transfer fee (aggregated, paid to Teleporter)
	/// @param speed               Speed of the request (normal or instant)
	/// @param isUsed              Whether the tx is used or not
	struct ccTransferRequest {
		uint inputAmount;
		address recipientAddress;
		uint fee;
		uint256 speed;
		uint64 deadline;
		bool isUsed;
	}

	// Events

	/// @notice                    Emits when a cc transfer request gets done
	/// @param user                User recipient Address
	/// @param inputAmount         Amount of locked tokens on source chain
	/// @param speed               Speed of the request (normal or instant)
	/// @param fee                 Transfer fee (aggregated, paid to Teleporter) paid by the user
	event CCTransfer(address indexed user, uint inputAmount, uint indexed speed, uint fee);

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
		address lockerBitcoinDecodedAddress
	) external payable returns (bool);
}