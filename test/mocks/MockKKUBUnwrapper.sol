// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/periphery/unwrapper/IKKUB.sol";

contract MockKKUBUnwrapper {
    error TransferFailed();
    error BlacklistedAddress();

    IKKUB public immutable KKUB;
    mapping(address => bool) public blacklist;

    event UnwrappedKKUB(address indexed recipient, uint256 amount);

    constructor(address _weth) {
        KKUB = IKKUB(_weth);
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

        // Transfer KKUB to this contract
        require(KKUB.transferFrom(msg.sender, address(this), amount), "KKUB transfer failed");

        // Withdraw ETH
        KKUB.withdraw(amount);

        // Transfer ETH to recipient
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit UnwrappedKKUB(recipient, amount);
        return true;
    }

    receive() external payable {}
}
