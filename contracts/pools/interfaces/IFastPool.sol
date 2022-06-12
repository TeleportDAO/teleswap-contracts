// SPDX-License-Identifier: <SPDX-License>
pragma solidity ^0.7.6;

import '../../erc20/interfaces/IERC20.sol';

interface IFastPool is IERC20 {
  // events
  event AddLiquidity(address user, uint wrappedBitcoinAmount); 
  event RemoveLiquidity(address user, uint256 wrappedBitcoinAmount);
  event FastTransfer(address user, uint256 requestedAmount, uint256 transferredAmount, uint blockNumber);

  // read-only functions
  function owner() external view returns (address);
  function wrappedBitcoin() external view returns (address); // gives back the wrapped bitcoin address
  function fastRouter() external view returns (address);
  function fastFee() external view returns (uint);
  function fastLimit() external view returns (uint);
  function fastConfirmationParameter() external view returns(uint);
  function totalRequestedAmount(uint blockNumber) external view returns(uint);
  function totalWrappedBitcoin() external view returns(uint);

  // state-changing functions
  function changeOwner(address _owner) external;
  function setFastRouter(address _fastRouter) external;
  function setFastLimit(uint _fastLimit) external;
  function setFastFee(uint _fastFee) external;
  function setFastConfirmationParameter (uint _fastConfirmationParameter) external;
  function addLiquidity(address user, uint wrappedBitcoinAmount) external returns (uint);
  function removeLiquidity(address user, uint fastPoolTokenAmount) external returns (uint);
  function fastTransfer(address user, uint amount, uint blockNumber) external returns(bool);
}