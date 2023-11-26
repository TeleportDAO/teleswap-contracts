pragma solidity >=0.8.0 <0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenBatchTransfer is Ownable {

    ERC20 public token; 
    address public transferOperator; 

    modifier onlyOperator() {
        require(
            msg.sender == transferOperator,
            "Only operator can call this function."
        );
        _;
    }

    constructor(address _token)
    public
    {
        token = ERC20(_token);
        transferOperator = msg.sender;
    }

    event NewOperator(address transferOperator);
    event WithdrawToken(address indexed owner, uint256 stakeAmount);

    function updateOperator(address newOperator) public onlyOwner {
        require(newOperator != address(0), "Invalid operator address");
        
        transferOperator = newOperator;

        emit NewOperator(newOperator);
    }

    function withdrawToken(uint256 value) public onlyOperator
    {
        require(token.balanceOf(address(this)) >= value, "Not enough balance in the contract");

        require(token.transfer(msg.sender, value), "Unable to transfer token to the owner account");

        emit WithdrawToken(msg.sender, value);
    }

    function batchTransfer(address[] calldata tokenHolders, uint256[] calldata amounts) 
    external 
    onlyOperator
    {
        require(tokenHolders.length == amounts.length, "Invalid input parameters");

        for(uint256 indx = 0; indx < tokenHolders.length; indx++) {
            require(token.transfer(tokenHolders[indx], amounts[indx]), "Unable to transfer token to the account");
        }
    }

}