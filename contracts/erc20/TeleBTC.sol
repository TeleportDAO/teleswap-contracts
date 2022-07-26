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
    address public override ccTransferRouter;
    address public override ccExchangeRouter;
    address public override ccBurnRouter;

    constructor(
        string memory _name,
        string memory _symbol,
        address _ccTransferRouter,
        address _ccExchangeRouter,
        address _ccBurnRouter
    ) public ERC20(_name, _symbol, 0) {
        ccTransferRouter = _ccTransferRouter;
        ccExchangeRouter = _ccExchangeRouter;
        ccBurnRouter = _ccBurnRouter;
    }

    // TODO: remove it (just for test)
    function mintTestToken () external override {
        _mint(msg.sender, 10000000000); // mint 100 teleBTC
    }

    /// @notice                     Changes cc transfer router contract address
    /// @dev                        Only owner can call this
    /// @param _ccTransferRouter    The new cc transfer router contract address
    function setCCTransferRouter(address _ccTransferRouter) external override onlyOwner {
        ccTransferRouter = _ccTransferRouter;
    }

    /// @notice                     Changes cc exchange router contract address
    /// @dev                        Only owner can call this
    /// @param _ccExchangeRouter    The new cc exchange router contract address
    function setCCExchangeRouter(address _ccExchangeRouter) external override onlyOwner {
        ccExchangeRouter = _ccExchangeRouter;
    }

    /// @notice                 Changes cc burn router contract address
    /// @dev                    Only owner can call this
    /// @param _ccBurnRouter    The new cc burn router contract address
    function setCCBurnRouter(address _ccBurnRouter) external override onlyOwner {
        ccBurnRouter = _ccBurnRouter;
    }

    function burn(uint amount) external nonReentrant override returns (bool) {
        require(msg.sender == ccBurnRouter, "TeleBTC: Message sender is not CCBurnRouter");
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
        return true;
    }

    function mint(address receiver, uint amount) external nonReentrant override returns (bool) {
        require(
            msg.sender == ccTransferRouter || msg.sender == ccExchangeRouter,
            "TeleBTC: Message sender is not CCTransferRouter or CCExchangeRouter"
        );
        _mint(receiver, amount);
        emit Mint(receiver, amount);
        return true;
    }
}
