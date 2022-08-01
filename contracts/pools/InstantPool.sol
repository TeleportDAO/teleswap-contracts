pragma solidity ^0.8.0; 

import './interfaces/IInstantPool.sol'; 
import '../libraries/SafeMath.sol'; 
import '../erc20/ERC20.sol'; 
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract InstantPool is IInstantPool, ERC20, Ownable, ReentrancyGuard {

    using SafeMath for uint256; 
    address public override teleBTC; 
    uint public override instantPercentageFee; // a number between 0-10000 to show %0.01
    uint public override totalTeleBTC;
    address public override instantRouter;
    mapping (address => uint256) private _balances; 
    mapping (address => mapping (address => uint256)) private _allowances; 
    uint256 private _totalSupply; 
    string private _name; 
    string private _symbol;

    constructor(
        address _teleBTC, 
        address _instantRouter,
        uint _instantPercentageFee, 
        string memory _name, 
        string memory _symbol
    ) ERC20(_name, _symbol, 0) public { 
        teleBTC = _teleBTC; 
        instantRouter = _instantRouter;
        instantPercentageFee = _instantPercentageFee; 
    }

    /// @notice                               Gives available wrapped token amount
    /// @dev                                  
    /// @return                               Available amount of wrapped token that can be borrowed    
    function availableTeleBTC() override public view returns (uint) { 
        return IERC20(teleBTC).balanceOf(address(this)); 
    }

    /// @notice                               Gives the unpaid loans amount
    /// @dev                                  
    /// @return                               Amount of wrapped token that has been borrowed but has not been paid back
    function totalUnpaidLoan() override external view returns (uint) { 
        uint availableTeleBTC = availableTeleBTC();
        return totalTeleBTC.sub(availableTeleBTC); 
    }  

    /// @notice                 Changes instant router contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instant router contract address
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
    }
    
    /// @notice                        Changes instant loan fee
    /// @dev                           Only current owner can call this
    /// @param _instantPercentageFee   The new percentage fee    
    function setInstantPercentageFee(uint _instantPercentageFee) external override onlyOwner { 
        instantPercentageFee = _instantPercentageFee; 
    } 

    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        teleBTC = _teleBTC;
    } 

    /// @notice               Adds liquidity to instant pool
    /// @dev                           
    /// @param _user          Address of user who receives instant pool token        
    /// @param _amount        Amount of liquidity that user wants to add   
    /// @return               Amount of instant pool token that user receives
    function addLiquidity(address _user, uint _amount) external nonReentrant override returns (uint) { 
        uint instantPoolTokenAmount; 
        // Transfers wrapped tokens from user 
        IERC20(teleBTC).transferFrom(msg.sender, address(this), _amount); 
        if (totalTeleBTC == 0) { 
            instantPoolTokenAmount = _amount; 
        } else { 
            instantPoolTokenAmount = _amount.mul(_totalSupply).div(totalTeleBTC); 
        }
        totalTeleBTC = totalTeleBTC.add(_amount); 
        // Mints instant pool token for user 
        _mint(_user, instantPoolTokenAmount); 
        emit AddLiquidity(_user, _amount, instantPoolTokenAmount); 
        return instantPoolTokenAmount; 
    } 
    
    /// @notice                               Removes liquidity from instant pool
    /// @dev                           
    /// @param _user                          Address of user who receives wrapped token       
    /// @param _instantPoolTokenAmount        Amount of instant pool token that is burnt  
    /// @return                               Amount of wrapped token that user receives
    function removeLiquidity(address _user, uint _instantPoolTokenAmount) external nonReentrant override returns (uint) {
        require(_balances[msg.sender] >= _instantPoolTokenAmount, "InstantPool: balance is not sufficient"); 
        uint teleBTCAmount = _instantPoolTokenAmount.mul(totalTeleBTC).div(_totalSupply);
        totalTeleBTC = totalTeleBTC.sub(teleBTCAmount); 
        IERC20(teleBTC).transfer(_user, teleBTCAmount); 
        _burn(msg.sender, _instantPoolTokenAmount); 
        emit RemoveLiquidity(msg.sender, teleBTCAmount, _instantPoolTokenAmount); 
        return teleBTCAmount; 
    } 

    /// @notice                               Gives loan to user
    /// @dev                                  Only instant router contract can call this
    /// @param _user                          Address of user who wants loan 
    /// @param _amount                        Amount of requested loan
    /// @return                               Amount of given loan after reducing the fee 
    function getLoan(address _user, uint _amount) nonReentrant override external returns (bool) { 
        require(msg.sender == instantRouter, "InstantPool: sender is not allowed"); 
        // Instant fee increases the total teleBTC amount
        uint instantFee = _amount.mul(instantPercentageFee).div(10000);
        totalTeleBTC = totalTeleBTC.add(instantFee); 
        IERC20(teleBTC).transfer(_user, _amount); 
        emit InstantLoan(_user, _amount, instantFee); 
        return true; 
    } 

}