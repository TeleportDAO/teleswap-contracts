// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import './IERC20.sol';

interface IWETH is IERC20 {
    function deposit() external payable;
    // function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}