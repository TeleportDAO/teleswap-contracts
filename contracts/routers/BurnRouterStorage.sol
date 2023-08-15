// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/IBurnRouterStorage.sol";

contract BurnRouterStorage is IBurnRouterStorage {

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

    // Constants
    uint constant MAX_PROTOCOL_FEE = 10000;
    uint constant MAX_SLASHER_REWARD = 10000;

    // Public variables
    uint public override startingBlockNumber;
    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override treasury;
    uint public override transferDeadline;
    uint public override protocolPercentageFee; // Min amount is %0.01
    uint public override slasherPercentageReward; // Min amount is %1
    uint public override bitcoinFee; // Fee of submitting a tx on Bitcoin
    
    mapping(address => burnRequest[]) public burnRequests; 
    // ^ Mapping from locker target address to assigned burn requests
    mapping(address => uint) public burnRequestCounter;
    mapping(bytes32 => bool) public override isUsedAsBurnProof; 
    // ^ Mapping that shows a txId has been submitted to pay a burn request

}