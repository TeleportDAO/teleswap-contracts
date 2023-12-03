// SPDX-License-Identifier: MIT
pragma solidity <0.8.4;

import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";

contract UniswapV2 is UniswapV2Router02 {

    constructor(
        address _factory, 
        address _WETH
    ) UniswapV2Router02(_factory, _WETH) public {
        // JUST FOR TEST
    }

}