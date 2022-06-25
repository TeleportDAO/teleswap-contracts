pragma solidity ^0.7.6;

import "./interfaces/IWrappedToken.sol";
import "../libraries/SafeMath.sol";
import "../role/Ownable.sol";
import "../role/Roles.sol";
import "hardhat/console.sol";

contract WrappedToken is IWrappedToken, Ownable {
    using Roles for Roles.Role;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);

    event BurnerAdded(address indexed account);
    event BurnerRemoved(address indexed account);

    Roles.Role private _minters;
    Roles.Role private _burner;

    modifier onlyMinter() {
        require(
            isMinter(_msgSender()),
            "WrappedToken: caller does not have the minter role"
        );
        _;
    }

    function isMinter(address account) public view returns (bool) {
        return _minters.has(account);
    }

    function addMinter(address account) public onlyOwner {
        _minters.add(account);
        emit MinterAdded(account);
    }

    function removeMinter(address account) public onlyOwner {
        _minters.remove(account);
        emit MinterRemoved(account);
    }


    modifier onlyBurner() {
        require(
            isBurner(_msgSender()),
            "WrappedToken: caller does not have the burner role"
        );
        _;
    }

    function isBurner(address account) public view returns (bool) {
        return _burner.has(account);
    }

    function addBurner(address account) public onlyOwner {
        _burner.add(account);
        emit MinterAdded(account);
    }

    function removeBurner(address account) public onlyOwner {
        _burner.remove(account);
        emit MinterRemoved(account);
    }

    using SafeMath for uint;
    address public override CCTransferRouter;
    string public override name;
    string public override symbol;
    uint8 public constant override decimals = 8;
    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    constructor(
        string memory _name,
        string memory _symbol,
        address _CCTransferRouter
    ) public {
        name = _name;
        symbol = _symbol;
        totalSupply = 0;

        if (!isMinter(_msgSender())) {
            addMinter(_msgSender());
        }

        if (!isBurner(_msgSender())) {
            addBurner(_msgSender());
        }

        console.log("_CCTransferRouter");
        console.log(_CCTransferRouter);

        addMinter(_CCTransferRouter);

        CCTransferRouter = _CCTransferRouter;
    }

    // TODO: remove it (just for test)
    function mintTestToken () public override {
        _mint(msg.sender, 100000000000000000000); // mint 100 BTC with 18 decimals
        emit Mint(msg.sender, 100000000000000000000);
    }

    function burn(uint256 amount) external override {
        require(balanceOf[msg.sender] >= amount, "Balance is not sufficient");
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    function mint(address receiver, uint amount) external override onlyMinter returns (bool) {
        require(msg.sender == CCTransferRouter, "message sender is not CCTransferRouter");
        _mint(receiver, amount);
        emit Mint(receiver, amount);
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
    }

    function approve(address spender, uint value) external override returns(bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint value) external override returns (bool){
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        return true;
    }

}
