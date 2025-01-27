// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

library TransferHelper {
    using SafeERC20 for IERC20;
    using Address for address payable;

    error ETHTransferFailed();

    /**
     * @notice Safely approves tokens using OpenZeppelin's SafeERC20
     */
    function safeApprove(address token, address to, uint256 value) internal {
        IERC20(token).forceApprove(to, value);
    }

    /**
     * @notice Safely transfers tokens using OpenZeppelin's SafeERC20
     */
    function safeTransfer(address token, address to, uint256 value) internal {
        IERC20(token).safeTransfer(to, value);
    }

    /**
     * @notice Safely transfers tokens from an address using OpenZeppelin's SafeERC20
     */
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        IERC20(token).safeTransferFrom(from, to, value);
    }

    /**
     * @notice Safely transfers ETH using OpenZeppelin's Address utility
     */
    function safeTransferETH(address to, uint256 value) internal {
        if (address(this).balance < value) revert ETHTransferFailed();
        payable(to).sendValue(value);
    }
}
