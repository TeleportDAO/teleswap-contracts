// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ITeleBTC.sol";
import "../libraries/SafeMath.sol";
import "../erc20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol"; // Just for test

contract TeleBTC is ITeleBTC, ERC20, Ownable, ReentrancyGuard {

    using SafeMath for uint;
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "TeleBTC: only minters can mint");
        _;
    }

    /**
     * @dev Give an account access to mint.
     */
    function addMinter(address account) external override onlyOwner {
        require(!isMinter(account), "TeleBTC: account already has role");
        minters[account] = true;
    }

    /**
     * @dev Remove an account's access to mint.
     */
    function removeMinter(address account) external override onlyOwner {
        require(isMinter(account), "TeleBTC: account does not have role");
        minters[account] = false;
    }

    /**
     * @dev Check if an account is minter.
     * @return bool
     */
    function isMinter(address account) internal view returns (bool) {
        require(account != address(0), "TeleBTC: account is the zero address");
        return minters[account];
    }

    modifier onlyBurner() {
        require(isBurner(_msgSender()), "TeleBTC: only burners can burn");
        _;
    }

    /**
     * @dev Give an account access to burn.
     */
    function addBurner(address account) external override onlyOwner {
        require(!isBurner(account), "TeleBTC: account already has role");
        burners[account] = true;
    }

    /**
     * @dev Remove an account's access to burn.
     */
    function removeBurner(address account) external override onlyOwner {
        require(isBurner(account), "TeleBTC: account does not have role");
        burners[account] = false;
    }

    /**
     * @dev Check if an account is burner.
     * @return bool
     */
    function isBurner(address account) internal view returns (bool) {
        require(account != address(0), "TeleBTC: account is the zero address");
        return burners[account];
    }

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 0) {

    }

    // TODO: remove it (just for test)
    function mintTestToken () external override {
        _mint(msg.sender, 10000000000); // mint 100 teleBTC
    }

    function burn(uint amount) external nonReentrant onlyBurner override returns (bool) {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
        return true;
    }

    function mint(address receiver, uint amount) external nonReentrant onlyMinter override returns (bool) {
        _mint(receiver, amount);
        emit Mint(receiver, amount);
        return true;
    }
}
