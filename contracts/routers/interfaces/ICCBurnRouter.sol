// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

interface ICCBurnRouter {

  struct unWrapRequest {
    uint amount;
    address requestSender;
    address pubKeyHash;
    uint burningFee;
    uint transferDeadline;
    bool isTransferred;
  }

  struct psbt {
    bytes psbtBase;
    bytes psbtSigned;
  }

  // events
  event CCBurn(address pubKeyHash, uint amount, uint requestIndex);
  event PaidCCBurn(address pubKeyHash, uint amount, uint requestIndex);
  event SubmitPSBT(bytes psbtBase, bytes psbtSigned, uint teleporterIndex, uint requestIndex);

  // read-only functions
  function owner() external view returns (address);
  function wrappedBitcoin() external view returns(address);

  // state-changing functions
  function changeOwner(address _owner) external;
  function setConfirmationParameter(uint _confirmationParameter) external;
  function setBitcoinRelay(address _bitcoinRelay) external;
  function setWrappedBitcoin(address _wrappedBitcoin) external;
  function setTransferDeadline(uint _transferDeadline) external;
  function ccBurn(uint amount, bytes memory decodedAddress) external returns(bool);
  function burnProof(
    bytes4 version,
    bytes memory vin,
    bytes calldata vout,
    bytes4 locktime,
    uint256 blockNumber,
    bytes calldata intermediateNodes,
    uint index,
    bool payWithTDT,
    uint requestIndex
  ) external returns(bool);
  function disputeBurn(uint requestIndex, address recipient) external;
  function submitPSBT(
      uint teleporterIndex,
      bytes memory psbtBase,
      bytes memory psbtSigned,
      uint requestIndex
  ) external returns(bool);
}


//pragma solidity ^0.7.6;
//interface ICCBurnRouter {
//
//  // Structures
//
//  /// @notice                 	Structure for recording burn requests
//  /// @param amount         		Amount of burnt tokens
//  /// @param remainedAmount   	Amount that user gets (after paying fees)
//  /// @param sender       		Address of user who requests burning
//  /// @param userBitcoinAddress   Public key hash of the user on Bitcoin
//  /// @param deadline         	Deadline of lockers for executing the request
//  /// @param isTransferred    	True if the request has been executed
//  /// @param locker		    	The locker assigned to this burn request who should execute it
//  struct burnRequest {
//    uint amount;
//    uint remainedAmount;
//    address sender;
//    address userBitcoinAddress;
//    bool isScriptHash;
//    uint deadline;
//    bool isTransferred;
//    address lockerTargetAddress;
//  }
//
//  // Events
//
//  /// @notice                 		Emits when a burn request gets submitted
//  /// @param userTargetAddress        Target address of the user
//  /// @param userBitcoinAddress       Public key hash of the user on Bitcoin
//  /// @param amount         			Amount of burnt tokens
//  /// @param remainedAmount   		Amount that user gets (after paying fees)
//  /// @param lockerTargetAddress		Locker's address on the target chain
//  /// @param index       				The index of a request for a locker
//  /// @param deadline         		Deadline of lockers for executing the request
//  event CCBurn(
//    address indexed userTargetAddress,
//    address userBitcoinAddress,
//    uint amount,
//    uint remainedAmount,
//    address indexed lockerTargetAddress,
//    uint index,
//    uint indexed deadline
//  );
//
//  /// @notice                 		Emits when a burn request gets executed
//  /// @param userTargetAddress        Target address of the user
//  /// @param userBitcoinAddress       Public key hash of the user on Bitcoin
//  /// @param remainedAmount   		Amount that user gets (after paying fees)
//  /// @param lockerTargetAddress		Locker's address on the target chain
//  /// @param index       				The index of a request for a locker
//  event PaidCCBurn(
//    address indexed userTargetAddress,
//    address userBitcoinAddress,
//    uint remainedAmount,
//    address indexed lockerTargetAddress,
//    uint index
//  );
//
//  // Read-only functions
//
//  function relay() external view returns (address);
//
//  function teleBTC() external view returns (address);
//
//  function transferDeadline() external view returns (uint);
//
//  // To cover transaction cost for calling burnProof + service they provide
//  function lockerPercentageFee() external view returns (uint);
//
//  function protocolPercentageFee() external view returns (uint);
//
//  function bitcoinFee() external view returns (uint); // Bitcoin transaction fee
//
//  function isTransferred(address _lockerTargetAddress, uint _index) external view returns (bool);
//
//  // State-changing functions
//
//  function setRelay(address _relay) external;
//
//  function setTeleBTC(address _teleBTC) external;
//
//  function setTransferDeadline(uint _transferDeadline) external;
//
//  function setLockerPercentageFee(uint _lockerPercentageFee) external;
//
//  function setProtocolPercentageFee(uint _protocolPercentageFee) external;
//
//  function setBitcoinFee(uint _bitcoinFee) external;
//
//  function ccBurn(
//    uint _amount,
//    bytes memory _decodedUserBitcoinAddress,
//    address _lockerTargetAddress
//  ) external returns (bool);
//
//  function burnProof(
//    bytes4 _version,
//    bytes memory _vin,
//    bytes calldata _vout,
//    bytes4 _locktime,
//    uint256 _blockNumber,
//    bytes calldata _intermediateNodes,
//    uint _index,
//    address _lockerTargetAddress,
//    uint _startIndex,
//    uint _endIndex
//  ) external returns (bool);
//
//  function disputeBurn(address _lockerTargetAddress, uint[] _indices) external returns (bool);
//}