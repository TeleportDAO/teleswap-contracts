// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IWETH.sol";
import "./ERC20.sol";
import "hardhat/console.sol";

contract WETH is ERC20 {

    constructor(string memory _name, string memory _symbol)
    ERC20(_name, _symbol, 0) {}

    function deposit() external payable {
        require(msg.value > 0);
        _mint(_msgSender(), msg.value);
    }

    function withdraw(uint value) external {
        require(balanceOf(_msgSender()) >= value, "Balance is not sufficient");
        _burn(_msgSender(), value);
        address payable recipient = payable(_msgSender());
        recipient.transfer(value);
    }
}