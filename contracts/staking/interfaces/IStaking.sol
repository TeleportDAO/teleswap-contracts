pragma solidity 0.8.0;

interface IStaking {
  // events
  event Stake(address user, uint TDTAmount);
  event Unstake(address user, uint TDTAmount);

  // read-only functions
  function owner() external view returns (address);
  function TeleportDAOToken() external view returns (address);
  function instantRouter() external view returns (address);
  function totalStakingShare() external view returns(uint);
  function stakedAmount (address user) external returns(uint);
  function stakingShare (address user) external returns(uint);
  function earnedTDT (address user) external view returns (uint);
  
  // state-changing fucntions
  function changeOwner (address _owner) external;
  function setInstantRouter (address _instantRouter) external;
  function stake (address user, uint amount) external;
  function unstake (address user, uint _stakingShare) external;
  function claimReward (address user) external returns (bool);
  function equivalentStakingShare (uint TDTAmount) external returns (uint);
  function equivalentTDT (uint stakingShare) external returns (uint);
}