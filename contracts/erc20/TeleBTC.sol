// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ITeleBTC.sol";
import "../erc20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol"; // Just for test

contract TeleBTC is ITeleBTC, ERC20, Ownable, ReentrancyGuard {

    modifier onlyMinter() {
        require(isMinter(_msgSender()), "TeleBTC: only minters can mint");
        _;
    }

    modifier onlyBurner() {
        require(isBurner(_msgSender()), "TeleBTC: only burners can burn");
        _;
    }

    // Public variables
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 0) {

    }

    function decimals() public view virtual override(ERC20, IERC20) returns (uint8) {
        return 8;
    }

    /**
     * @dev Check if an account is minter.
     * @return bool
     */
    function isMinter(address account) internal view returns (bool) {
        require(account != address(0), "TeleBTC: account is the zero address");
        return minters[account];
    }

    /**
     * @dev Check if an account is burner.
     * @return bool
     */
    function isBurner(address account) internal view returns (bool) {
        require(account != address(0), "TeleBTC: account is the zero address");
        return burners[account];
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

    // TODO: remove it
    ///@notice      Mints TeleBTC just for test
    function mintTestToken () external override {
        _mint(msg.sender, 10000000000); // mint 100 teleBTC
    }

    /// @notice                Burns TeleBTC tokens of msg.sender
    /// @dev                   Only burners can call this
    /// @param _amount         Amount of burnt tokens
    function burn(uint _amount) external nonReentrant onlyBurner override returns (bool) {
        _burn(msg.sender, _amount);
        emit Burn(msg.sender, _amount);
        return true;
    }

    /// @notice                Mints TeleBTC tokens for _receiver
    /// @dev                   Only minters can call this
    /// @param _receiver       Address of token's receiver
    /// @param _amount         Amount of minted tokens
    function mint(address _receiver, uint _amount) external nonReentrant onlyMinter override returns (bool) {
        _mint(_receiver, _amount);
        emit Mint(_receiver, _amount);
        return true;
    }
}
