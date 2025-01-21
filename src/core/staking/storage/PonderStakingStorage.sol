// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title PonderStakingStorage
 * @notice Abstract contract containing state variables for PonderStaking
 */
abstract contract PonderStakingStorage {
    /// @notice Address that can perform admin functions
    address public owner;

    /// @notice Pending owner for 2-step transfer
    address public pendingOwner;

    /// @notice Last time the rewards were distributed
    uint256 public lastRebaseTime;

    /// @notice Amount of PONDER per share
    uint256 public ponderPerShare;

    /// @notice Tracks total PONDER deposited by users
    uint256 public totalDepositedPonder;
}
