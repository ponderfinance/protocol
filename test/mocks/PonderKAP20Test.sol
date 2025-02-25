// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/core/token/PonderKAP20.sol";

contract TestPonderKAP20 is PonderKAP20 {
    constructor() PonderKAP20("Ponder LP Token", "PONDER-LP") {}

    function mint(address to, uint256 value) public {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public {
        _burn(from, value);
    }
}
