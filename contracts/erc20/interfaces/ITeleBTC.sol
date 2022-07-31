// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IERC20.sol';

interface ITeleBTC is IERC20 {

    // Events

    event Mint(address indexed to, uint value);

    event Burn(address indexed to, uint value);

    // read-only functions

    function ccTransferRouter() external view returns(address);

    function ccExchangeRouter() external view returns(address);

    function ccBurnRouter() external view returns(address);

    // state-changing functions

    function addMinter(address account) external;

    function removeMinter(address account) external;

    function addBurner(address account) external;

    function removeBurner(address account) external;

    function setCCTransferRouter(address _ccTransferRouter) external;

    function setCCExchangeRouter(address _ccExchangeRouter) external;

    function setCCBurnRouter(address _ccBurnRouter) external;

    function mint(address receiver, uint amount) external returns(bool);

    function burn(uint256 amount) external returns(bool);

    function mintTestToken() external; // Just for test TODO: remove it

}