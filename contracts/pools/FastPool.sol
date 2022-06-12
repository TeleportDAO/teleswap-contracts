pragma solidity ^0.7.6;

import './interfaces/IFastPool.sol';
import '../libraries/SafeMath.sol';
import '../erc20/ERC20.sol';
import 'hardhat/console.sol';

contract FastPool is IFastPool, ERC20{

  using SafeMath for uint256;
  address public override wrappedBitcoin;
  address public override fastRouter;
  mapping (uint=>uint) public override totalRequestedAmount;
  mapping (address => uint256) private _balances;
  mapping (address => mapping (address => uint256)) private _allowances;
  uint256 private _totalSupply;
  string private _name;
  string private _symbol;
  uint public override fastLimit;
  uint public override fastFee; // percentage of total amount 
  uint public override fastConfirmationParameter;
  address public override owner;

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  constructor(
    address _wrappedBitcoin,
    address _fastRouter,
    string memory _name,
    string memory _symbol,
    uint _fastLimit,
    uint _fastFee,
    uint _fastConfirmationParameter,
    address _owner
  ) ERC20(_name, _symbol, 0) public {
    wrappedBitcoin = _wrappedBitcoin;
    fastRouter = _fastRouter;
    fastLimit = _fastLimit;
    fastFee = _fastFee;
    fastConfirmationParameter = _fastConfirmationParameter;
    owner = _owner;
  }

  function changeOwner(address _owner) external override onlyOwner {
    owner = _owner;
  }

  function setFastRouter(address _fastRouter) external override onlyOwner {
    fastRouter = _fastRouter;
  }

  function setFastLimit(uint _fastLimit) external override onlyOwner {
    fastLimit = _fastLimit;
  }

  function setFastFee(uint _fastFee) external override onlyOwner {
    fastFee = _fastFee;
  }

  function setFastConfirmationParameter(uint _fastConfirmationParameter) external override {
    fastConfirmationParameter = _fastConfirmationParameter;
  }
      
  function addLiquidity (address user, uint wrappedBitcoinAmount) public override returns (uint) {
    uint liquidity;
    uint totalWrappedBitcoin = totalWrappedBitcoin();
    if (totalWrappedBitcoin == 0) {
      liquidity = wrappedBitcoinAmount;
    } else {
      liquidity = wrappedBitcoinAmount*_totalSupply/totalWrappedBitcoin;
    }
    IERC20(wrappedBitcoin).transferFrom(msg.sender, address(this), wrappedBitcoinAmount);
    _mint(user, liquidity); // mint fast pool token for user
    emit AddLiquidity(user, wrappedBitcoinAmount);
    return wrappedBitcoinAmount;
  }

  function removeLiquidity(address user, uint fastPoolTokenAmount) public override returns(uint){
    require(_balances[msg.sender] >= fastPoolTokenAmount, "balance is not sufficient"); // cannot burn more than his fp token balance
    uint userShare = (totalWrappedBitcoin()*fastPoolTokenAmount)/_totalSupply;
    require(IERC20(wrappedBitcoin).transfer(user, userShare), "balance is not sufficient"); // give msg.sender his share of fees
    _burn(msg.sender, fastPoolTokenAmount); 
    emit RemoveLiquidity(user, userShare); // TODO: is user correct?
    return userShare;
  }
  
  function fastTransfer(address user, uint amount, uint blockNumber) override public returns(bool){
    require(msg.sender == fastRouter, "sender is not fast router");
    require((totalRequestedAmount[blockNumber] + amount) < fastLimit, "fast limit is reached");
    require(totalWrappedBitcoin() >= amount, "fast pool does not have enough balance");
    uint transferredAmount = amount*(100-fastFee)/100; // get fast fee from user
    IERC20(wrappedBitcoin).transfer(user, transferredAmount);
    totalRequestedAmount[blockNumber] = totalRequestedAmount[blockNumber] + amount;
    emit FastTransfer(user, amount, transferredAmount, blockNumber);
    return true;
  }
  
  function totalWrappedBitcoin() override public view returns(uint){
    return IERC20(wrappedBitcoin).balanceOf(address(this));
  }
    
}