// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";

/*//////////////////////////////////////////////////////////////
                    LAUNCHER STORAGE LAYOUT
//////////////////////////////////////////////////////////////*/

/// @title FiveFiveFiveLauncherStorage
/// @author taayyohh
/// @notice Storage contract for the 555 token launch platform
/// @dev Storage layout for launch platform state variables
///      Uses abstract contract pattern for storage inheritance
///      All state variables are carefully ordered for optimal packing
abstract contract FiveFiveFiveLauncherStorage {
    using FiveFiveFiveLauncherTypes for *;

    /*//////////////////////////////////////////////////////////////
                        LAUNCH MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Total number of launches created
    /// @dev Increments with each new launch
    /// @dev Used as unique identifier for launches
    uint256 public launchCount;

    /// @notice Mapping of launch IDs to launch information
    /// @dev Contains all data for active and completed launches
    /// @dev Uses LaunchInfo struct for packed storage
    mapping(uint256 => FiveFiveFiveLauncherTypes.LaunchInfo) public launches;

    /*//////////////////////////////////////////////////////////////
                        TOKEN REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks used token names to prevent duplicates
    /// @dev Maps token name string to boolean flag
    /// @dev True if name has been used
    mapping(string => bool) public usedNames;

    /// @notice Tracks used token symbols to prevent duplicates
    /// @dev Maps token symbol string to boolean flag
    /// @dev True if symbol has been used
    mapping(string => bool) public usedSymbols;
}
