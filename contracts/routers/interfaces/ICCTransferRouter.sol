// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

interface ICCTransferRouter {

  struct wrapRequest {
    uint bitcoinAmount;
    address recipientAddress;
    bool isExchange;
    uint teleporterFee; // TODO: should I change it to uint8?
    uint256 speed;
    bool isUsed;
    uint deadline;
    uint blockNumber; // only store for fast transfers
    bytes intermediateNodes; // only store for fast transfers
    uint index; // only store for fast transfers
    bool isMinted; // initially is false for fast tranfer
    uint exchangeAmount;
    address exchangeToken;
  }

  // events
  event CCTransfer(address user, address inputToken, uint inputAmount, uint speed);
  event PaybackFastLoan(address user, uint amount);

  // read-only functions
  function owner() external view returns (address);
  function isRequestUsed(bytes32 txId) external view returns(bool);
  function isRequestMinted(bytes32 txId) external view returns(bool);
  function wrappedBitcoin() external view returns(address);
  function bitcoinFastPool() external view returns(address);
  function normalConfirmationParameter() external view returns(uint);

  // state-changing functions
  function changeOwner (address _owner) external;
  function setNormalConfirmationParameter (uint _normalConfirmationParameter) external;
  function setBitcoinRelay (address _bitcoinRelay) external;
  function setFastRouter (address _fastRouter) external;
  function setWrappedBitcoin (address _wrappedBitcoin) external returns (bool);
  function setInstantRouter (address _instantRouter) external;
  function setCCExchangeRouter (address _ccExchangeRouter) external;

  function ccTransfer(
    bytes4 version,
    bytes memory vin,
    bytes calldata vout,
    bytes4 locktime,
    uint256 blockNumber,
    bytes calldata intermediateNodes,
    uint index,
    bool payWithTDT
  ) external returns(bool);
  function mintAfterFinalization(bytes32 txId) external returns(bool);
  function instantCCTransferWithPermit(
    address signer,
    bytes memory signature,
    address receiver,
    uint instantTokenAmount,
    uint deadline
  ) external returns(bool);
}