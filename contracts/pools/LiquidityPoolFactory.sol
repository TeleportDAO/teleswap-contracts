pragma solidity 0.8.0;

import './interfaces/ILiquidityPoolFactory.sol';
import './interfaces/ILiquidityPool.sol';
import '../erc20/interfaces/IERC20.sol';
import './LiquidityPool.sol';

contract LiquidityPoolFactory is ILiquidityPoolFactory {
    address public override feeTo;
    address public override feeToSetter;

    mapping(address => mapping(address => address)) public override getLiquidityPool;
    address[] public override allLiquidityPools;

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allLiquidityPoolsLength() public override view returns (uint) {
        return allLiquidityPools.length;
    }

    function createLiquidityPool(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'TeleportDAO: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'TeleportDAO: ZERO_ADDRESS');
        require(getLiquidityPool[token0][token1] == address(0), 'TeleportDAO: PAIR_EXISTS'); // single check is sufficient
        LiquidityPool pair;
        string memory name;
        string memory symbol;
        name = string(abi.encodePacked(IERC20(token0).name(), "-", IERC20(token1).name(), "Liquidity-Pool"));
        symbol = string(abi.encodePacked(IERC20(token0).symbol(), "-", IERC20(token1).symbol(), "LPT"));
        pair = new LiquidityPool(token0, token1, name, symbol);
        // ILiquidityPool(address(pair)).initialize(token0, token1);
        getLiquidityPool[token0][token1] = address(pair);
        getLiquidityPool[token1][token0] = address(pair); // populate mapping in the reverse direction
        allLiquidityPools.push(address(pair));
        emit LiquidityPoolCreated(token0, token1, address(pair), allLiquidityPools.length);

        return address(pair);
    }

    function setFeeTo (address _feeTo) public override {
        require(msg.sender == feeToSetter, 'TeleportDAO: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter (address _feeToSetter) public override  {
        require(msg.sender == feeToSetter, 'TeleportDAO: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
