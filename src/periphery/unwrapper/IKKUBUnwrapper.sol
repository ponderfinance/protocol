// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title KKUBUnwrapper Interface
/// @notice Interface for the KKUBUnwrapper contract that handles unwrapping KKUB to ETH
interface IKKUBUnwrapper {
    /// @notice Emitted when KKUB is successfully unwrapped
    /// @param recipient Address receiving the unwrapped ETH
    /// @param amount Amount of KKUB unwrapped
    event UnwrappedKKUB(address indexed recipient, uint256 amount);

    /// @notice Emitted when emergency withdrawal is executed
    /// @param amount Amount withdrawn
    /// @param timestamp Time of withdrawal
    event EmergencyWithdraw(uint256 amount, uint256 timestamp);

    /// @notice Emitted when withdrawal limit is reset
    event WithdrawalLimitReset();

    /// @notice Get the KKUB token address
    /// @return Address of the KKUB token contract
    function kkub() external view returns (address);

    /// @notice Get the amount of ETH locked in active unwrapping operations
    /// @return Amount of ETH locked
    function getLockedBalance() external view returns (uint256);

    /// @notice Unwrap KKUB to ETH
    /// @param amount Amount of KKUB to unwrap
    /// @param recipient Address to receive the unwrapped ETH
    /// @return Success boolean
    function unwrapKKUB(uint256 amount, address recipient) external returns (bool);

    /// @notice Execute emergency withdrawal of excess ETH
    function emergencyWithdraw() external;

    /// @notice Reset the withdrawal limit timer
    function resetWithdrawalLimit() external;

    /// @notice Pause the contract
    function pause() external;

    /// @notice Unpause the contract
    function unpause() external;
}
