// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libraries/SafeMath.sol';
import './interfaces/ICollateralPool.sol';
import '../erc20/interfaces/IERC20.sol';
import '../erc20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import 'hardhat/console.sol'; // Just for test

contract CollateralPool is ICollateralPool, ERC20, Ownable, ReentrancyGuard {
    
    using SafeMath for uint;
    address public override collateralToken;
    uint public override collateralizationRatio; // Multiplied by 100
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _collateralToken,
        uint _collateralizationRatio
    ) ERC20(_name, _symbol, 0) public {
        collateralToken = _collateralToken;
        collateralizationRatio = _collateralizationRatio;
    }


    /// @return                 Amount of total added collateral
    function totalAddedCollateral() public view override returns (uint) {
        return IERC20(collateralToken).balanceOf(address(this));
    }

    /// @notice                          Changes the collateralization ratio
    /// @dev                             Only owner can call this
    /// @param _collateralizationRatio   The new collateralization ratio
    function setCollateralizationRatio(uint _collateralizationRatio) external override onlyOwner {
        collateralizationRatio = _collateralizationRatio;
    }

    /// @notice                 Adds collateral to collateral pool 
    /// @dev                    Mints collateral pool token for user
    /// @param _user            Address of user whose collateral balance is increased
    /// @param _amount          Amount of added collateral
    /// @return                 True if collateral is added successfully
    function addCollateral(address _user, uint _amount) external nonReentrant override returns (bool) {
        // Checks basic requirements
        require(_user != address(0), "CollateralPool: User address is zero");
        require(_amount != 0, "CollateralPool: Amount is zero");

        // Calculates collateral pool token amount
        uint collateralPoolTokenAmount;
        if (totalSupply() == 0) {
            collateralPoolTokenAmount = _amount;
        } else {
            collateralPoolTokenAmount = _amount*totalSupply()/totalAddedCollateral();
        }

        // Transfers collateral tokens from message sender to contract
        IERC20(collateralToken).transferFrom(msg.sender, address(this), _amount);

        // Mints collateral pool token for _user
        _mint(_user, collateralPoolTokenAmount);
        emit AddCollateral(_user, _amount, collateralPoolTokenAmount);

        return true;
    }

    /// @notice                               Removes collateral from collateral pool
    /// @dev                                  Burns collateral pool token of message sender
    /// @param _collateralPoolTokenAmount     Amount of burnt collateral pool token
    /// @return                               True if collateral is removed successfully
    function removeCollateral(uint _collateralPoolTokenAmount) external nonReentrant override returns (bool) {
        // Checks basic requirements
        require(_collateralPoolTokenAmount != 0, "CollateralPool: Amount is zero");
        require(balanceOf(msg.sender) >= _collateralPoolTokenAmount, "CollateralPool: balance is not enough");

        // Finds equivalent collateral token amount
        uint collateralTokenAmount = _collateralPoolTokenAmount*totalAddedCollateral()/totalSupply();

        // Burn collateral pool token of user
        _burn(msg.sender, _collateralPoolTokenAmount);

        // Sends collateral token to user
        IERC20(collateralToken).transfer(msg.sender, collateralTokenAmount);
        emit RemoveCollateral(msg.sender, collateralTokenAmount, _collateralPoolTokenAmount);
        return true;
    }

}