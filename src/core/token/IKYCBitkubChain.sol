// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IKYCBitkubChain Interface
/// @notice Interface for the Bitkub Chain KYC service
/// @dev Used to verify KYC status of addresses on Bitkub Chain
interface IKYCBitkubChain {
    /// @notice Check the KYC level of an address
    /// @param _addr The address to check
    /// @return The KYC level of the address (0 means no KYC)
    function kycsLevel(address _addr) external view returns (uint256);
}
