// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    KKUB UNWRAPPER TYPES
//////////////////////////////////////////////////////////////*/

/// @title KKUBUnwrapperTypes
/// @author taayyohh
/// @notice Type definitions and constants for KKUB unwrapping system
/// @dev Central library for all constants, errors, and type definitions
///      Used across the KKUB unwrapping protocol
///      All constants and errors are immutable and cannot be modified
library KKUBUnwrapperTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Time required between successive withdrawals
    /// @dev Used to implement rate limiting on withdrawals
    /// @dev Set to 6 hours to prevent rapid successive withdrawals
    uint256 public constant WITHDRAWAL_DELAY = 6 hours;

    /// @notice Maximum amount that can be withdrawn in a single period
    /// @dev Caps individual withdrawal size for risk management
    /// @dev Value is denominated in wei (1e18)
    uint256 public constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    /// @notice Minimum KYC verification level required for operations
    /// @dev Enforced by KKUB token contract
    /// @dev Level 1 represents basic KYC verification
    uint256 public constant REQUIRED_KYC_LEVEL = 1;
}
