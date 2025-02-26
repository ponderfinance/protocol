// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/// @title TransferHelper
/// @author taayyohh
/// @notice Library to safely handle token and ETH transfers
/// @dev Wraps OpenZeppelin's SafeERC20 and Address utilities for consistent error handling
library TransferHelper {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice Error thrown when ETH transfer fails
    error ETHTransferFailed();

    /// @notice Approves tokens using OpenZeppelin's SafeERC20
    /// @dev Uses forceApprove to handle tokens that require resetting allowance to zero
    /// @param token The address of the ERC20 token
    /// @param to The address that will spend the tokens
    /// @param value The amount of tokens to approve
    function safeApprove(address token, address to, uint256 value) internal {
        IERC20(token).forceApprove(to, value);
    }

    /// @notice Transfers tokens using OpenZeppelin's SafeERC20
    /// @dev Safely handles non-standard ERC20 tokens that don't return boolean
    /// @param token The address of the ERC20 token
    /// @param to The address to transfer tokens to
    /// @param value The amount of tokens to transfer
    function safeTransfer(address token, address to, uint256 value) internal {
        IERC20(token).safeTransfer(to, value);
    }

    /// @notice Transfers tokens from a specific address using OpenZeppelin's SafeERC20
    /// @dev Requires prior approval from the "from" address
    /// @param token The address of the ERC20 token
    /// @param from The address to transfer tokens from
    /// @param to The address to transfer tokens to
    /// @param value The amount of tokens to transfer
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        IERC20(token).safeTransferFrom(from, to, value);
    }

    /// @notice Transfers ETH using OpenZeppelin's Address utility
    /// @dev Checks balance before transfer and reverts if insufficient
    /// @param to The address to transfer ETH to
    /// @param value The amount of ETH to transfer in wei
    function safeTransferETH(address to, uint256 value) internal {
        if (address(this).balance < value) revert ETHTransferFailed();
        payable(to).sendValue(value);
    }
}
