// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../libraries/SafeMath.sol';
import './interfaces/ICollateralPool.sol';
import '../erc20/interfaces/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import 'hardhat/console.sol'; // Just for test

contract CollateralPool is ICollateralPool, Ownable, ReentrancyGuard {
    
    using SafeMath for uint;
    string public override name;
    address public override instantRouter;
    address public override collateralToken;
    uint public override collateralizationRatio; // MultIplied by 100
    uint public override totalPoolShare;
    mapping(address => uint) public override poolShare; // user => pool share
    
    constructor(
        string memory _name,
        address _instantRouter,
        address _collateralToken,
        uint _collateralizationRatio
    ) public {
        _name = name;
        instantRouter = _instantRouter;
        collateralToken = _collateralToken;
        collateralizationRatio = _collateralizationRatio;
    }


    /// @return                 Amount of total added collateral
    function totalAddedCollateral() public view override returns (uint) {
        return IERC20(collateralToken).balanceOf(address(this));
    }

    /// @return                 Amount of total added collateral
    function poolShareToCollateral(uint _poolShare) public view override returns (uint) {
        return totalAddedCollateral().mul(_poolShare).div(totalPoolShare);
    }

    /// @notice                 Changes instant router contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instant router contract address    
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
    }

    /// @notice                          Changes the collateralization ratio
    /// @dev                             Only owner can call this
    /// @param _collateralizationRatio   The new collateralization ratio
    function setCollateralizationRatio(uint _collateralizationRatio) external override onlyOwner {
        collateralizationRatio = _collateralizationRatio;
    }

    /// @notice                 Adds collateral to collateral pool
    /// @dev                    
    /// @param _user            Address of user whose collateral is increased
    /// @param _amount          Amount of added collateral
    /// @return                 True if collateral is added successfully
    function addCollateral(address _user, uint _amount) external nonReentrant override returns (bool) {
        uint _poolShare;
        // Transfers collateral tokens from message sender to contract
        IERC20(collateralToken).transferFrom(msg.sender, address(this), _amount);
        // Prevents reentrancy
        uint totalAddedCollateral = totalAddedCollateral() - _amount;
        if (totalAddedCollateral == 0) {
            _poolShare = _amount;
        } else {
            _poolShare = _amount.mul(totalPoolShare).div(totalAddedCollateral);
        }
        totalPoolShare = totalPoolShare.add(_poolShare);
        poolShare[_user] = poolShare[_user].add(_poolShare);
        emit AddCollateral(_user, _amount, _poolShare);
        return true;
    }

    /// @notice                 Removes collateral from collateral pool
    /// @dev                    Instant router can remove users collateral for slashing them
    /// @param _user            Address of user whose collateral is decreased
    /// @param _poolShare       Amount of burnt pool share
    /// @return                 True if collateral is removed successfully
    function removeCollateral(address _user, uint _poolShare) external nonReentrant override returns (bool) {
        require(msg.sender == _user || msg.sender == instantRouter, "CollateralPool: sender is not allowed");
        require(poolShare[_user] >= _poolShare, "CollateralPool: balance is not enough");
        uint collateralAmount = _poolShare.mul(totalAddedCollateral()).div(totalPoolShare);
        poolShare[_user] = poolShare[_user].sub(_poolShare);
        totalPoolShare = totalPoolShare.sub(_poolShare);
        IERC20(collateralToken).transfer(msg.sender, collateralAmount);
        emit RemoveCollateral(_user, collateralAmount, _poolShare);
        return true;
    }

    /// @notice                 Locks part of the user collateral
    /// @dev                    Only instant router can call this
    /// @param _user            Address of user whose collateral is locked
    /// @param _amount          Amount of locked collateral
    /// @return                 True if collateral is locked successfully
    function lockCollateral(address _user, uint _amount) external nonReentrant override returns (bool) {
        require(msg.sender == instantRouter, "CollateralPool: sender is not allowed");
        uint _poolShare = _amount.mul(totalPoolShare).div(totalAddedCollateral());
        require(_poolShare <= poolShare[_user], "CollateralPool: available collateral is not enough");
        // Transfers pool share from user to instant router
        poolShare[_user] = poolShare[_user].sub(_poolShare);
        poolShare[instantRouter] = poolShare[instantRouter].add(_poolShare);
        emit LockCollateral(_user, _amount, _poolShare);
        return true;
    }

    /// @notice                 Unlocks the user collateral
    /// @dev                    Only instant router can call this
    /// @param _user            Address of user whose collateral is unlocked
    /// @param _amount          Amount of unlocked collateral
    /// @return                 True if collateral is unlocked successfully
    function unlockCollateral(address _user, uint _amount) external nonReentrant override returns (bool) {
        require(msg.sender == instantRouter, "CollateralPool: sender is not allowed");
        uint _poolShare = _amount.mul(totalPoolShare).div(totalAddedCollateral());
        require(_poolShare <= poolShare[instantRouter], "CollateralPool: available collateral is not enough");
        // Transfers pool share from instant router to user
        poolShare[instantRouter] = poolShare[instantRouter].sub(_poolShare);
        poolShare[_user] = poolShare[_user].add(_poolShare);
        emit UnlockCollateral(_user, _amount, _poolShare);
        return true;
    }

}