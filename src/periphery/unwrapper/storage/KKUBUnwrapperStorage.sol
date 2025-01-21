// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title KKUBUnwrapper Storage Contract
/// @notice Abstract contract containing storage layout for the KKUBUnwrapper
/// @dev Only storage variables and their layout should be defined here
abstract contract KKUBUnwrapperStorage {
    /// @notice Last successful withdrawal timestamp
    uint256 internal lastWithdrawalTime;

    /// @notice Amount of ETH currently in active unwrapping operations
    uint256 internal _lockedBalance;

    /// @dev Gap for future storage variables
    /// @dev This gap is added to avoid storage collisions when new variables are added through inheritance
    uint256[48] private __gap;
}
