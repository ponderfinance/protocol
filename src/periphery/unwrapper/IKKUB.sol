// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IWETH } from "./IWETH.sol";

/// @title KKUB Token Interface
/// @notice Interface for the KKUB token with additional KYC functionality
interface IKKUB is IWETH {
    /// @notice Check if an address is blacklisted
    /// @param addr Address to check
    /// @return Whether the address is blacklisted
    function blacklist(address addr) external view returns (bool);

    /// @notice Get KYC level for an address
    /// @param addr Address to check
    /// @return KYC level of the address
    function kycsLevel(address addr) external view returns (uint256);
}
