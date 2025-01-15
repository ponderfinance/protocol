// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IWETH.sol";

contract MockKKUBUnwrapper {
    error TransferFailed();
    error BlacklistedAddress();

    IWETH public immutable WETH;
    mapping(address => bool) public blacklist;

    event UnwrappedKKUB(address indexed recipient, uint256 amount);

    constructor(address _weth) {
        WETH = IWETH(_weth);
    }

    // Mock function to set blacklist status
    function setBlacklist(address user, bool status) external {
        blacklist[user] = status;
    }

    function unwrapKKUB(uint256 amount, address recipient) external returns (bool) {
        // Simplified blacklist check - only check recipient
        if (blacklist[recipient]) {
            revert BlacklistedAddress();
        }

        // Transfer WETH to this contract
        require(WETH.transferFrom(msg.sender, address(this), amount), "WETH transfer failed");

        // Withdraw ETH
        WETH.withdraw(amount);

        // Transfer ETH to recipient
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit UnwrappedKKUB(recipient, amount);
        return true;
    }

    receive() external payable {}
}
