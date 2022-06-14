pragma solidity ^0.7.6;

import './interfaces/IInstantPool.sol';
import '../libraries/SafeMath.sol';
import '../erc20/ERC20.sol';
import 'hardhat/console.sol';

contract InstantPool is IInstantPool, ERC20{

  using SafeMath for uint256;
  address public override wrappedBitcoin;
  address public instantRouter;
  address public override owner;
  // FIXME: why _balances has overwrited the one in ERC20 ?!
  // mapping (address => uint256) private _balances;
  // mapping (address => mapping (address => uint256)) private _allowances;
  // uint256 private _totalSupply;
  // string private _name;
  // string private _symbol;
  uint public override instantFee; // percentage of total amount

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  constructor(
    address _instantRouter,
    address _wrappedBitcoin,
    string memory _name,
    string memory _symbol,
    address _owner,
    uint _instantFee
  ) ERC20(_name, _symbol, 0) public {
    instantRouter = _instantRouter;
    wrappedBitcoin = _wrappedBitcoin;
    owner = _owner;
    instantFee = _instantFee;
  }

  function changeOwner(address _owner) external override onlyOwner {
    owner = _owner;
  }

  function setInstantRouter(address _instantRouter) external override onlyOwner {
    instantRouter = _instantRouter;
  }

  function setInstantFee (uint _instantFee) external override onlyOwner {
    instantFee = _instantFee;
  }

  function addLiquidity(address user, uint wrappedBitcoinAmount) external override returns(uint) {
    uint liquidity;
    uint totalWrappedBitcoin = totalWrappedBitcoin();
    if (totalWrappedBitcoin == 0) {
      liquidity = wrappedBitcoinAmount;
    } else {
      uint256 theTotalSupply = totalSupply();
      liquidity = wrappedBitcoinAmount * theTotalSupply / totalWrappedBitcoin;
    }
    IERC20(wrappedBitcoin).transferFrom(msg.sender, address(this), wrappedBitcoinAmount);
    _mint(user, liquidity); // mint instant pool token for user
    emit AddLiquidity(user, wrappedBitcoinAmount);
    return wrappedBitcoinAmount;
  }

  function removeLiquidity(address user, uint instantPoolTokenAmount) external override returns(uint) {
    console.log("the balance of the instant router");
    console.log(balanceOf(msg.sender));

    require(balanceOf(msg.sender) >= instantPoolTokenAmount, "balance is not sufficient"); // cannot burn more than his ip token balance

    uint256 theTotalSupply = totalSupply();
    uint userShare = (instantPoolTokenAmount*totalWrappedBitcoin()) / theTotalSupply;
    //  FIXME: why this contract send the wrapped BTC to the instant router instead of the user ?!
    IERC20(wrappedBitcoin).transfer(msg.sender, userShare); // give msg.sender his share of fees
    _burn(msg.sender, instantPoolTokenAmount);
    emit RemoveLiquidity(msg.sender, userShare);
    return userShare;
  }

  function instantTransfer(address user, uint amount) override external returns(bool){
    require(msg.sender == instantRouter, "sender is not instant router");
    uint transferredAmount = amount*(100-instantFee)/100; // get instant fee from user
    IERC20(wrappedBitcoin).transfer(user, transferredAmount);
    emit InstantTransfer(user, amount, transferredAmount);
    return true;
  }

  function totalWrappedBitcoin() override public view returns(uint){
    return IERC20(wrappedBitcoin).balanceOf(address(this));
  }

}