// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "../IPonderFactory.sol";

/// @title PonderFactoryLib
/// @author taayyohh
/// @notice Library containing helper functions for PonderFactory validation
library PonderFactoryLib {
    /// @notice Ensures an address is not the zero address
    /// @param addr Address to validate
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert IPonderFactory.ZeroAddress();
    }

    /// @notice Validates the fee recipient address
    /// @param addr Address of proposed fee recipient
    function validateFeeTo(address addr) internal pure {
        validateAddress(addr);
    }

    /// @notice Validates the launcher address
    /// @param addr Address of proposed launcher
    function validateLauncher(address addr) internal pure {
        validateAddress(addr);
    }

    /// @notice Verifies the sender has appropriate permissions
    /// @param sender Address attempting the operation
    /// @param authorizedAddress Address with admin permissions
    function verifyAccess(address sender, address authorizedAddress) internal pure {
        if (sender != authorizedAddress) revert IPonderFactory.Forbidden();
    }
}
