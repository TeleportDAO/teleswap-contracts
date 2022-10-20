// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/ICollateralPoolFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./CollateralPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CollateralPoolFactory is ICollateralPoolFactory, Ownable, ReentrancyGuard {

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CollateralPoolFactory: zero address");
        _;
    }

    modifier nonZeroValue(uint _value) {
        require(_value > 0, "CollateralPoolFactory: zero value");
        _;
    }

    // Public variables
    mapping(address => address) public override getCollateralPoolByToken; // collateral token => collateral pool
    address[] public override allCollateralPools; // List of all collateral pools

    /// @notice         This contract creates collateral pool for tokens
    constructor() {}

    function renounceOwnership() public virtual override onlyOwner {}

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

    /// @notice                          Creates a new collateral pool
    /// @dev                             Only owner can call this
    /// @param _collateralToken          Address of underlying collateral token
    /// @param _collateralizationRatio   The ratio of over collateralization
    /// @return                          Address of newly created collateral pool
    function createCollateralPool(
        address _collateralToken, 
        uint _collateralizationRatio
    ) external nonZeroAddress(_collateralToken) nonZeroValue(_collateralizationRatio) 
        nonReentrant onlyOwner override returns (address) {
        // Checks that collateral pool for the token doesn't exist
        require(
            getCollateralPoolByToken[_collateralToken] == address(0), 
            'CollateralPoolFactory: collateral pool already exists'
        );
        
        // Creates collateral pool
        CollateralPool pool;
        string memory name;
        string memory symbol;
        name = string(abi.encodePacked(ERC20(_collateralToken).name(), "-", "Collateral-Pool"));
        symbol = string(abi.encodePacked(ERC20(_collateralToken).symbol(), "CP"));
        pool = new CollateralPool(name, symbol, _collateralToken, _collateralizationRatio);

        // Transfers ownership of collateral pool to owner of this contract
        CollateralPool(address(pool)).transferOwnership(msg.sender);

        // Stores collateral pool address
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
    ) external nonReentrant nonZeroAddress(_collateralToken) onlyOwner override returns (bool) {
        // Checks that collateral pool exists
        address collateralPool = getCollateralPoolByToken[_collateralToken];
        require(collateralPool != address(0), 'CollateralPoolFactory: collateral pool does not exist');

        // Removes collateral pool address
        require(_index < allCollateralPoolsLength(), 'CollateralPoolFactory: index is out of range');
        require(collateralPool == allCollateralPools[_index], 'CollateralPoolFactory: index is not correct');
        getCollateralPoolByToken[_collateralToken] = address(0);
        _removeElement(_index);
        emit RemoveCollateralPool(_collateralToken, collateralPool);

        return true;
    }

    /// @notice             Removes an element of allCollateralPools
    /// @dev                Deletes and shifts the array  
    /// @param _index       Index of the element that is deleted
    function _removeElement(uint _index) private {
        for (uint i = _index; i < allCollateralPoolsLength() - 1; i++) {
            allCollateralPools[i] = allCollateralPools[i+1];
        }
        allCollateralPools.pop();
    }
}