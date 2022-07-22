// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICollateralPool {

  // Events

  event AddCollateral(address indexed user, uint amount, uint poolShare);

  event RemoveCollateral(address indexed user, uint amount, uint poolShare);

  event LockCollateral(address indexed user, uint amount, uint poolShare);

  event UnlockCollateral(address indexed user, uint amount, uint poolShare);

  // Read-only functions

  function name() external view returns (string memory);

  function instantRouter() external view returns (address);

  function collateralToken() external view returns (address);

  function collateralizationRatio() external view returns(uint);

  function totalPoolShare() external view returns (uint);

  function poolShare(address _user) external view returns (uint);

  function totalAddedCollateral() external view returns (uint);

  function poolShareToCollateral(uint poolShare) external view returns (uint);

  // State-changing functions
  
  function setInstantRouter(address _instantRouter) external;

  function setCollateralizationRatio(uint _collateralizationRatio) external;

  function addCollateral(address _user, uint _amount) external returns (bool);

  function removeCollateral(address _user, uint _poolShare) external returns (bool);

  function lockCollateral(address _user, uint _amount) external returns (bool);

  function unlockCollateral(address _user, uint _amount) external returns (bool);
}