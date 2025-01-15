// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/PonderERC20.sol";

contract TestPonderERC20 is PonderERC20 {
    constructor() PonderERC20("Ponder LP Token", "PONDER-LP") {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public {
        _burn(from, value);
    }
}
