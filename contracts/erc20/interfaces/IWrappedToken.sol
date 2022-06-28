// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

import './IERC20.sol';

interface IWrappedToken is IERC20 {
  // events
  event Mint(address indexed to, uint value);
  event Burn(address indexed to, uint value);
  // read-only functions
  function CCTransferRouter() external view returns(address);
  // state-changing functions
  function mint(address receiver, uint amount) external returns(bool);
  function burn(uint256 amount) external;
  function mintTestToken() external;

}