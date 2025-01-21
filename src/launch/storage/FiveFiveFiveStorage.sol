// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";

/// @title FiveFiveFiveLauncherStorage
/// @author taayyohh
/// @notice Storage contract for the 555 token launch platform
/// @dev Contains all state variables used by the launcher
abstract contract FiveFiveFiveLauncherStorage {
    using FiveFiveFiveLauncherTypes for *;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol admin state
    address public owner;
    address public feeCollector;

    /// @notice Launch tracking state
    uint256 public launchCount;
    mapping(uint256 => FiveFiveFiveLauncherTypes.LaunchInfo) public launches;

    /// @notice Token name and symbol tracking
    mapping(string => bool) public usedNames;
    mapping(string => bool) public usedSymbols;
}
