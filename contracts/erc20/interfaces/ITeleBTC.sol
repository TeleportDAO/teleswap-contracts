// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITeleBTC is IERC20 {

    // Events

    event Mint(address indexed to, uint value);

    event Burn(address indexed to, uint value);

    event AddMinter(address indexed account);

    event RemoveMinter(address indexed account);

    event AddBurner(address indexed account);

    event RemoveBurner(address indexed account);

    // read functions

    function decimals() external view returns (uint8);

    // state-changing functions

    function addMinter(address account) external;

    function removeMinter(address account) external;

    function addBurner(address account) external;

    function removeBurner(address account) external;

    function mint(address receiver, uint amount) external returns(bool);

    function burn(uint256 amount) external returns(bool);

    function mintTestToken() external; // Just for test

}