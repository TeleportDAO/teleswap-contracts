// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './interfaces/ICollateralPoolFactory.sol';
import '../erc20/interfaces/IERC20.sol';
import './CollateralPool.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract CollateralPoolFactory is ICollateralPoolFactory, Ownable, ReentrancyGuard {

    mapping(address => address) public override getCollateralPoolByToken; // collateral token => collateral pool
    address[] public override allCollateralPools;
    address public override instantRouter;

    constructor(address _instantRouter) public {
        instantRouter = _instantRouter;
    }

    /// @return         Total number of collateral pools
    function allCollateralPoolsLength() public override view returns (uint) {
        return allCollateralPools.length;
    }

    /// @notice                   Checks that whether the token is accepted as collateral or not
    /// @param _collateralToken   Address of collateral token
    /// @return                   True if the corresponding collateral pool exists
    function isCollateral(address _collateralToken) external override view returns (bool) {
        return getCollateralPoolByToken[_collateralToken] == address(0) ? false : true;
    }

    /// @notice                 Changes instant router contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instant router contract address
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
    }

    /// @notice                          Creates a new collateral pool
    /// @dev                             Only owner can call this
    /// @param _collateralToken          Address of underlying collateral token
    /// @param _collateralizationRatio   The ratio of over collateralization
    /// @return                          Address of newly created collateral pool
    function createCollateralPool(
        address _collateralToken, 
        uint _collateralizationRatio
    ) external nonReentrant onlyOwner override returns (address) {
        require(_collateralToken != address(0), 'CollateralPoolFactory: Collateral token address is not valid');
        require(_collateralizationRatio != 0, 'CollateralPoolFactory: Collateralization ratio cannot be zero');
        require(
            getCollateralPoolByToken[_collateralToken] == address(0), 
            'CollateralPoolFactory: Collateral pool already exists'
        );
        CollateralPool pool;
        string memory name;
        string memory symbol;
        name = string(abi.encodePacked(IERC20(_collateralToken).name(), "-", "Collateral-Pool"));
        symbol = string(abi.encodePacked(IERC20(_collateralToken).symbol(), "CP"));
        pool = new CollateralPool(name, symbol, _collateralToken, _collateralizationRatio);
        getCollateralPoolByToken[_collateralToken] = address(pool);
        allCollateralPools.push(address(pool));
        emit CreateCollateralPool(name, _collateralToken, _collateralizationRatio, address(pool));
        return address(pool);
    }

    /// @notice                          Removes an existing collateral pool
    /// @dev                             Only owner can call this
    /// @param _collateralToken          Address of underlying collateral token
    /// @param _index                    Index of collateral pool in allCollateralPools
    /// @return                          True if collateral pool is removed successfully
    function removeCollateralPool(
        address _collateralToken, 
        uint _index
    ) external nonReentrant onlyOwner override returns (bool) {
        address collateralPool = getCollateralPoolByToken[_collateralToken];
        require(collateralPool != address(0), 'CollateralPoolFactory: Collateral pool does not exist');
        require(_index < allCollateralPoolsLength(), 'CollateralPoolFactory: Index is out of range');
        require(collateralPool == allCollateralPools[_index], 'CollateralPoolFactory: Index is not correct');
        getCollateralPoolByToken[_collateralToken] = address(0);
        _removeElement(_index);
        emit RemoveCollateralPool(_collateralToken, collateralPool);
        return true;
    }

    /// @notice             Removes an element of allCollateralPools
    /// @dev                Deletes and shifts the array  
    /// @param _index       Index of the element that is deleted
    function _removeElement(uint _index) internal {
        require(_index < allCollateralPoolsLength(), "CollateralPoolFactory: Index is out of range");
        for (uint i = _index; i < allCollateralPoolsLength() - 1; i++) {
            allCollateralPools[i] = allCollateralPools[i+1];
        }
        allCollateralPools.pop();
    }
}