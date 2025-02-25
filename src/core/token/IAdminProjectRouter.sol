// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IAdminProjectRouter Interface
/// @notice Interface for the Bitkub Chain project-based admin authorization system
/// @dev Used to verify admin privileges for different project operations
interface IAdminProjectRouter {
    /// @notice Check if an address is a super admin for a specific project
    /// @param _addr The address to check
    /// @param _project The project identifier to check against
    /// @return True if the address is a super admin for the project
    function isSuperAdmin(address _addr, string calldata _project) external view returns (bool);

    /// @notice Check if an address is an admin for a specific project
    /// @param _addr The address to check
    /// @param _project The project identifier to check against
    /// @return True if the address is an admin for the project
    function isAdmin(address _addr, string calldata _project) external view returns (bool);
}
