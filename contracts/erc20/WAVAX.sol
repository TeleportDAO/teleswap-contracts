pragma solidity 0.7.6;

import "./interfaces/IWAVAX.sol";
import "../libraries/SafeMath.sol";
import "hardhat/console.sol";

contract WAVAX is IWAVAX {
    using SafeMath for uint;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
        totalSupply = 0;
    }

    function deposit() external payable override {
        require(msg.value > 0);
        _mint(msg.sender, msg.value);
    }
    
    function withdraw(uint value) external override {
        require(balanceOf[msg.sender] >= value, "Balance is not sufficient");
        _burn(msg.sender, value);
        msg.sender.send(value);
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
    }

    function approve(address spender, uint value) external returns(bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint value) external override returns (bool){
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        return true;
    }
}
