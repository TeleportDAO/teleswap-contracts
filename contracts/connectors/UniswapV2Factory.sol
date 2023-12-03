// SPDX-License-Identifier: MIT
pragma solidity <0.8.4;

import "@uniswap/v2-core/contracts/UniswapV2Factory.sol";

contract UniswapV2 is UniswapV2Factory {

    constructor(
        address _feeToSetter
    ) UniswapV2Factory(_feeToSetter) public {
        // JUST FOR TEST
    }

}