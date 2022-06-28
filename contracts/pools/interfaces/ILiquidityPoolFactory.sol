// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

interface ILiquidityPoolFactory {
    // events
    event LiquidityPoolCreated(address indexed token0, address indexed token1, address pair, uint liquidityPoolsLength);

    // read-only functions
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getLiquidityPool(address tokenA, address tokenB) external view returns (address pair);
    function allLiquidityPools(uint number) external view returns (address pair);
    function allLiquidityPoolsLength() external view returns (uint);

    // state-changing functions
    function createLiquidityPool(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}
