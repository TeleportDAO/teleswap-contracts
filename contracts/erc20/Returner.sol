// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Returner is Ownable, ReentrancyGuard, Pausable {
    struct SellerParams {
        string tokenName; 
        uint256 tokenAmount; 
        uint256 teleBTCAmount;
    }
    mapping (address => SellerParams) public seller;

    struct BurnerParams {
        string tokenName;
        uint256 tokenAmount;
    }
    mapping (address => BurnerParams) public burner;

    mapping (string => address) public tokenMapping; 

    address public teleBTC;

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    constructor(string[] memory tokenName, address[] memory tokenAddress, address _teleBTC) {
        require(tokenName.length == tokenAddress.length, "Invalid input parameters");
        for (uint i = 0; i < tokenName.length; i++)
            tokenMapping[tokenName[i]] = tokenAddress[i];
        teleBTC = _teleBTC;
    }

    function changeToken(string memory tokenName, address tokenAddress) public onlyOwner {
        tokenMapping[tokenName] = tokenAddress;
    }

    function addTeleBTCSeller(address account, string memory tokenName, uint256 tokenAmount, uint256 teleBTCAmount) public onlyOwner{
        seller[account] = SellerParams(
            tokenName, 
            tokenAmount, 
            teleBTCAmount
        );
    }

    function addBurner(address account, string memory tokenName, uint256 tokenAmount) public onlyOwner{
        burner[account] = BurnerParams(
            tokenName, 
            tokenAmount
        );
    }

    function sellTeleBTC(address account) nonReentrant whenNotPaused public {
        require(account == msg.sender, "not owner");
        require(seller[account].tokenAmount != 0, "not seller");
        require(
            ERC20(teleBTC).transferFrom(account, address(this), seller[account].teleBTCAmount),
            "Unable to transfer TeleBTC to contract"
        );
        require(
            ERC20(tokenMapping[seller[account].tokenName]).transfer(account, seller[account].tokenAmount), 
            "Unable to transfer token to the account"
        );
        seller[account].tokenAmount = 0;
    }

    function refund(address account) nonReentrant whenNotPaused public {
        require(account == msg.sender, "not owner");
        require(burner[account].tokenAmount != 0, "not burner");
        require(
            ERC20(tokenMapping[burner[account].tokenName]).transfer(account, burner[account].tokenAmount), 
            "Unable to transfer token to the account"
        );
        burner[account].tokenAmount = 0;
    }

    function withdrawToken(string memory tokenName, uint256 tokenAmount) public onlyOwner{
        require(ERC20(tokenMapping[tokenName]).balanceOf(address(this)) >= tokenAmount, "Not enough balance in the contract");
        ERC20(tokenMapping[tokenName]).transfer(msg.sender, tokenAmount);
    }
}