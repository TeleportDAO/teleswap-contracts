// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/ICollateralPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import 'hardhat/console.sol'; // Just for test

contract CollateralPool is ICollateralPool, ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CollateralPool: zero address");
        _;
    }

    modifier nonZeroValue(uint _value) {
        require(_value > 0, "CollateralPool: zero value");
        _;
    }
    
    // Public variables
    address public override collateralToken;
    uint public override collateralizationRatio; // Multiplied by 100
    
    /// @notice                          This contract is a vault for collateral token
    /// @dev                             Users deposit collateral to use TeleportDAO instant feature
    ///                                  Collateral pool factory creates collateral pool contract
    /// @param _name                     Name of collateral pool
    /// @param _symbol                   Symbol of collateral pool
    /// @param _collateralToken          Address of underlying collateral token
    /// @param _collateralizationRatio   Over-collateralization ratio of collateral token (e.g. 120 means 1.2) 
    constructor(
        string memory _name,
        string memory _symbol,
        address _collateralToken,
        uint _collateralizationRatio
    ) ERC20(_name, _symbol) {
        collateralToken = _collateralToken;
        _setCollateralizationRatio(_collateralizationRatio);
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @return                 Amount of total added collateral
    function totalAddedCollateral() public view override returns (uint) {
        return IERC20(collateralToken).balanceOf(address(this));
    }

    /// @notice                          Changes the collateralization ratio
    /// @dev                             Only owner can call this
    /// @param _collateralizationRatio   The new collateralization ratio
    function setCollateralizationRatio(
        uint _collateralizationRatio
    ) external override onlyOwner {
        _setCollateralizationRatio(_collateralizationRatio);
    }

    /// @notice                          Internal setter for collateralization ratio
    /// @param _collateralizationRatio   The new collateralization ratio
    function _setCollateralizationRatio(
        uint _collateralizationRatio
    ) private nonZeroValue(_collateralizationRatio)  {
        emit NewCollateralizationRatio(collateralizationRatio, _collateralizationRatio);
        require(
            _collateralizationRatio >= 10000,
            "CollateralPool: CR is low"
        );
        collateralizationRatio = _collateralizationRatio;
    }

    /// @notice                             Converts collateral pool token to collateral token 
    /// @param _collateralPoolTokenAmount   Amount of collateral pool token
    /// @return                             Amount of collateral token
    function equivalentCollateralToken(uint _collateralPoolTokenAmount) external view override returns (uint) {
        require(totalSupply() > 0, "CollateralPool: collateral pool is empty");
        require(totalSupply() >= _collateralPoolTokenAmount, "CollateralPool: liquidity is not sufficient");
        return _collateralPoolTokenAmount*totalAddedCollateral()/totalSupply();
    }

    /// @notice                         Converts collateral token to collateral pool token 
    /// @param _collateralTokenAmount   Amount of collateral token
    /// @return                         Amount of collateral pool token
    function equivalentCollateralPoolToken(uint _collateralTokenAmount) external view override returns (uint) {
        require(totalAddedCollateral() > 0, "CollateralPool: collateral pool is empty");
        require(totalAddedCollateral() >= _collateralTokenAmount, "CollateralPool: liquidity is not sufficient");
        return _collateralTokenAmount*totalSupply()/totalAddedCollateral();
    }

    /// @notice                 Adds collateral to collateral pool 
    /// @dev                    Mints collateral pool token for user
    /// @param _user            Address of user whose collateral balance is increased
    /// @param _amount          Amount of added collateral
    /// @return                 True if collateral is added successfully
    function addCollateral(
        address _user, 
        uint _amount
    ) external nonZeroAddress(_user) nonZeroValue(_amount) nonReentrant override returns (bool) {
        // Calculates collateral pool token amount
        uint collateralPoolTokenAmount;
        if (totalSupply() == 0) {
            collateralPoolTokenAmount = _amount;
        } else {
            collateralPoolTokenAmount = _amount*totalSupply()/totalAddedCollateral();
        }

        // Transfers collateral tokens from message sender to contract
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Mints collateral pool token for _user
        _mint(_user, collateralPoolTokenAmount);
        emit AddCollateral(_user, _amount, collateralPoolTokenAmount);

        return true;
    }

    /// @notice                               Removes collateral from collateral pool
    /// @dev                                  Burns collateral pool token of message sender
    /// @param _collateralPoolTokenAmount     Amount of burnt collateral pool token
    /// @return                               True if collateral is removed successfully
    function removeCollateral(
        uint _collateralPoolTokenAmount
    ) external nonZeroValue(_collateralPoolTokenAmount) nonReentrant override returns (bool) {
        // Checks basic requirements
        require(
            balanceOf(msg.sender) >= _collateralPoolTokenAmount, 
            "CollateralPool: balance is not enough"
        );

        // Finds equivalent collateral token amount
        uint collateralTokenAmount = _collateralPoolTokenAmount*totalAddedCollateral()/totalSupply();

        // Burns collateral pool token of user
        _burn(msg.sender, _collateralPoolTokenAmount);

        // Sends collateral token to user
        IERC20(collateralToken).safeTransfer(msg.sender, collateralTokenAmount);
        emit RemoveCollateral(msg.sender, collateralTokenAmount, _collateralPoolTokenAmount);

        return true;
    }

}