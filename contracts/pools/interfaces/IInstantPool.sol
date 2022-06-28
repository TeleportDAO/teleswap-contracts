pragma solidity 0.8.0;

import '../../erc20/interfaces/IERC20.sol';

interface IInstantPool is IERC20{
  // events
  event AddLiquidity(address user, uint wrappedBitcoinAmount); 
  event RemoveLiquidity(address user, uint wrappedBitcoinAmount);
  event InstantTransfer(address user, uint256 requestedAmount, uint transferredAmount);

  // read-only functions
  function owner() external view returns (address);
  function wrappedBitcoin() external view returns (address);
  function totalWrappedBitcoin() external view returns(uint);
  function instantFee() external view returns(uint);
  
  // state-changing fucntions
  function changeOwner(address _owner) external;
  function setInstantRouter(address _instantRouter) external;
  function setInstantFee(uint _instantFee) external;
  function addLiquidity(address user, uint wrappedBitcoinAmount) external returns(uint);
  function removeLiquidity(address user, uint instantPoolTokenAmount) external returns (uint);
  function instantTransfer(address user, uint amount) external returns(bool);
}