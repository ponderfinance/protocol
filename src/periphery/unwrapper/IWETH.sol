// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Wrapped Ether Interface
/// @notice Interface for the Wrapped Ether (WETH) contract
/// @dev Defines the basic functionality of WETH - deposit, withdraw, and standard ERC20 transfer methods
interface IWETH {
    /// @notice Deposit ETH and receive WETH tokens
    /// @dev This function handles the wrapping of ETH to WETH
    /// The amount of ETH to wrap should be sent with the transaction
    function deposit() external payable;

    /// @notice Withdraw ETH by burning WETH tokens
    /// @dev Burns the specified amount of WETH and sends equivalent ETH to msg.sender
    /// @param amount The amount of WETH to burn and ETH to withdraw
    function withdraw(uint256 amount) external;

    /// @notice Transfer WETH tokens to another address
    /// @dev Standard ERC20 transfer function
    /// @param to The address to transfer WETH to
    /// @param value The amount of WETH to transfer
    /// @return success Whether the transfer was successful
    function transfer(address to, uint256 value) external returns (bool success);

    /// @notice Transfer WETH tokens from one address to another
    /// @dev Standard ERC20 transferFrom function
    /// @param from The address to transfer WETH from
    /// @param to The address to transfer WETH to
    /// @param value The amount of WETH to transfer
    /// @return success Whether the transfer was successful
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool success);
}
