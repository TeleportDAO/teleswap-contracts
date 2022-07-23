// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../erc20/interfaces/IERC20.sol';

interface ICollateralPool is IERC20 {

  // Events

  event AddCollateral(address indexed user, uint amount, uint collateralPoolTokenAmount);

  event RemoveCollateral(address indexed user, uint amount, uint collateralPoolTokenAmount);

  // Read-only functions

  function collateralToken() external view returns (address);

  function collateralizationRatio() external view returns(uint);

  function totalAddedCollateral() external view returns (uint);

  // State-changing functions

  function setCollateralizationRatio(uint _collateralizationRatio) external;

  function addCollateral(address _user, uint _amount) external returns (bool);

  function removeCollateral(uint _collateralPoolTokenAmount) external returns (bool);

}