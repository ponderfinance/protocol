// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/token/PonderERC20.sol";

contract ERC20Mint is PonderERC20 {
    constructor(string memory _name, string memory _symbol) PonderERC20(_name, _symbol) {}

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        _burn(from, value);
    }
}
