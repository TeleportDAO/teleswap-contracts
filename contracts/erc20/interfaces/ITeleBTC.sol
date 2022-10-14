// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IERC20.sol';

interface ITeleBTC is IERC20 {

    // Events

    event Mint(address indexed doer, address indexed receiver, uint value);

    event Burn(address indexed doer, address indexed burner, uint value);

    event NewMinterAdded(address indexed newMinter);

    event MinterRemoved(address indexed minter);

    event NewBurnerAdded(address indexed newBurner);

    event BurnerRemoved(address indexed burner);

    // state-changing functions

    function addMinter(address account) external;

    function removeMinter(address account) external;

    function addBurner(address account) external;

    function removeBurner(address account) external;

    function mint(address receiver, uint amount) external returns(bool);

    function burn(uint256 amount) external returns(bool);

    function mintTestToken() external; // Just for test

}