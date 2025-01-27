// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Ponder Router Storage Contract
/// @notice Abstract contract containing storage layout for the PonderRouter
/// @dev Only storage variables and their layout should be defined here
abstract contract PonderRouterStorage {
    /// @dev Gap for future storage variables
    /// @dev This gap is added to avoid storage collisions when new variables are added through inheritance
    uint256[50] private __gap;
}
