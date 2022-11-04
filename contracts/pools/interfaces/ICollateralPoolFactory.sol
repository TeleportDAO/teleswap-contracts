// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

interface ICollateralPoolFactory {

    // Events

    /// @notice                             Emits when a collateral pool is created
    /// @param name                         Name of the collateral token
    /// @param collateralToken              Collateral token address
    /// @param collateralizationRatio       At most (collateral value)/(collateralization ratio) can be moved instantly by the user
    /// @param collateralPool               Collateral pool contract address
    event CreateCollateralPool(
        string name,
        address indexed collateralToken,
        uint collateralizationRatio,
        address indexed collateralPool
    );

    /// @notice                 Emits when a collateral pool is removed
    /// @param collateralToken  Collateral token address
    /// @param collateralPool   Collateral pool contract address
    event RemoveCollateralPool(
        address indexed collateralToken,
        address indexed collateralPool
    );

    // Read-only functions

    function getCollateralPoolByToken(address _collateralToken) external view returns (address);

    function allCollateralPools(uint _index) external view returns (address);

    function allCollateralPoolsLength() external view returns (uint);

    function isCollateral(address _collateralToken) external view returns (bool);

    // State-changing functions

    function createCollateralPool(address _collateralToken, uint _collateralizationRatio) external returns (address);

    function removeCollateralPool(address _collateralToken, uint _index) external returns (bool);
}