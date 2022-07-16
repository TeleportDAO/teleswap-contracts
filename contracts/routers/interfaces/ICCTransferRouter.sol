// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

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

  // struct wrapRequest {
  //   uint bitcoinAmount;
  //   address recipientAddress;
  //   bool isExchange;
  //   uint teleporterFee; // TODO: should I change it to uint8?
  //   uint256 speed;
  //   bool isUsed;
  //   uint deadline;
  //   uint blockNumber; // only store for fast transfers
  //   bytes intermediateNodes; // only store for fast transfers
  //   uint index; // only store for fast transfers
  //   bool isMinted; // initially is false for fast tranfer
  //   uint exchangeAmount;
  //   address exchangeToken;
  // }


  // Events

  /// @notice                    Emits when a cc transfer request gets done
  /// @param user                User recipient Address
  /// @param inputAmount         Amount of locked tokens on source chain
  /// @param speed               Speed of the request (normal or instant)
  /// @param fee                 Transfer fee (aggregated, paid to Teleporter) paid by the user
  event CCTransfer(address indexed user, uint inputAmount, uint indexed speed, uint fee);

  // event CCTransfer(address user, address inputToken, uint inputAmount, uint speed);
  // event PaybackFastLoan(address user, uint amount);


  // Read-only functions

  function relay() external view returns (address);

  function instantRouter() external view returns (address);

  function lockers() external view returns (address);

  function teleBTC() external view returns (address);

  function isRequestUsed(bytes32 _txId) external view returns (bool);


  // read-only functions
  // function owner() external view returns (address);
  // function isRequestUsed(bytes32 txId) external view returns(bool);
  // function isRequestMinted(bytes32 txId) external view returns(bool);
  // function wrappedBitcoin() external view returns(address);
  // function bitcoinFastPool() external view returns(address);
  // function normalConfirmationParameter() external view returns(uint);


  // State-changing functions

  function setRelay(address _relay) external;

  function setInstantRouter(address _instantRouter) external;

  function setLockers(address _lockers) external;

  function setTeleBTC(address _teleBTC) external;

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
    uint _index
  ) external returns (bool);

  // state-changing functions
  // function changeOwner (address _owner) external;
  // function setNormalConfirmationParameter (uint _normalConfirmationParameter) external;
  // function setBitcoinRelay (address _bitcoinRelay) external;
  // function setFastRouter (address _fastRouter) external;
  // function setWrappedBitcoin (address _wrappedBitcoin) external returns (bool);
  // function setInstantRouter (address _instantRouter) external;
  // function setCCExchangeRouter (address _ccExchangeRouter) external;

  // function ccTransfer(
  //   bytes4 version,
  //   bytes memory vin,
  //   bytes calldata vout,
  //   bytes4 locktime,
  //   uint256 blockNumber,
  //   bytes calldata intermediateNodes,
  //   uint index,
  //   bool payWithTDT
  // ) external returns(bool);
  // function mintAfterFinalization(bytes32 txId) external returns(bool);
  // function instantCCTransferWithPermit(
  //   address signer,
  //   bytes memory signature,
  //   address receiver,
  //   uint instantTokenAmount,
  //   uint deadline
  // ) external returns(bool);
}