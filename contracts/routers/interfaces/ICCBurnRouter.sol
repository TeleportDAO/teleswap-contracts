// SPDX-License-Identifier: <SPDX-License>
pragma solidity ^0.7.6;

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