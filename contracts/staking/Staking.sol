pragma solidity 0.8.0;

import './interfaces/IStaking.sol';
import '../libraries/SafeMath.sol';
import '../erc20/interfaces/IERC20.sol';

contract Staking is IStaking {

  using SafeMath for uint256;
  address override public owner;
  address public override TeleportDAOToken;
  address public override instantRouter;
  uint public override totalStakingShare;
  mapping(address => uint) override public stakingShare;
  mapping(address => uint) override public stakedAmount;

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  constructor(address _TeleportDAOToken) public {
    TeleportDAOToken = _TeleportDAOToken;
    totalStakingShare = 0;
    owner = msg.sender;
  }

  function changeOwner (address _owner) external override onlyOwner {
    owner = _owner;
  }

  function setInstantRouter (address _instantRouter) external override onlyOwner {
      instantRouter = _instantRouter;
  }

  function stake (address user, uint amount) external override {
    uint _stakingShare;
    if (totalTDTAmount() == 0) {
      _stakingShare = amount;
    } else {
      _stakingShare = amount*totalStakingShare/totalTDTAmount();
    }
    IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), amount);
    stakingShare[user] = stakingShare[user] + _stakingShare;
    stakedAmount[user] = stakedAmount[user] + amount;
    totalStakingShare = totalStakingShare + _stakingShare;
    emit Stake(user, amount);
  }

  function unstake (address user, uint _stakingShare) public override {
    require(msg.sender == user || msg.sender == instantRouter, "message sender is not correct");
    require(stakingShare[user] >= _stakingShare, "balance is not enough");
    uint returnAmount = _stakingShare*totalTDTAmount()/totalStakingShare;
    stakingShare[user] = stakingShare[user] - _stakingShare;
    stakedAmount[user] = stakedAmount[user] - returnAmount;
    totalStakingShare = totalStakingShare - _stakingShare;
    IERC20(TeleportDAOToken).transfer(msg.sender, returnAmount);
    emit Unstake(user, returnAmount);
  }

  function earnedTDT (address user) public view override returns (uint) {
    uint totalTDTAmount = totalTDTAmount();
    if (totalStakingShare != 0) {
      return (stakingShare[user]*totalTDTAmount/totalStakingShare) - stakedAmount[user];
    } else {
      return 0;
    }
  }

  function claimReward (address user) external override returns (bool) {
    uint earnedTDT = earnedTDT(user);
    if (earnedTDT != 0) {
      uint equivalentStakingShare = equivalentStakingShare(earnedTDT);
      unstake(user, equivalentStakingShare); 
      return true;
    } else {
      return false;
    }
  }

  function equivalentStakingShare (uint TDTAmount) public override returns (uint) {
    uint totalTDTAmount = totalTDTAmount();
    if (totalTDTAmount != 0) {
      return TDTAmount*totalStakingShare/totalTDTAmount;
    } else {
      return 0;
    }
  }

  function equivalentTDT (uint stakingShare) external override returns (uint) {
    if (totalStakingShare != 0) {
      return stakingShare*totalTDTAmount()/totalStakingShare;
    } else {
      return 0;
    }
  }

  function totalTDTAmount () internal view returns (uint) {
    return IERC20(TeleportDAOToken).balanceOf(address(this));
  }
     
}