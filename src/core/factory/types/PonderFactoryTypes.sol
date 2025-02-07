// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER FACTORY TYPES
//////////////////////////////////////////////////////////////*/

/// @title PonderFactoryTypes
/// @author taayyohh
/// @notice Type definitions and constants for the Ponder Factory contract
/// @dev Library containing all custom errors and constants used in factory operations
library PonderFactoryTypes {
    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error thrown when attempting to create a pair with same token twice
    /// @dev Prevents invalid pair creation with identical addresses
    error IdenticalAddresses();

    /// @notice Error thrown when a required address parameter is zero
    /// @dev Basic validation for address inputs
    error ZeroAddress();

    /// @notice Error thrown when attempting to create an already existing pair
    /// @dev Prevents duplicate pair creation
    error PairExists();

    /// @notice Error thrown when caller lacks required permissions
    /// @dev Access control for restricted functions
    error Forbidden();

    /// @notice Error thrown when setting an invalid fee receiver
    /// @dev Validates fee receiver address updates
    error InvalidFeeReceiver();

    /// @notice Error thrown when setting an invalid launcher address
    /// @dev Validates launcher address updates
    error InvalidLauncher();

    /// @notice Error thrown when attempting launcher update before timelock expires
    /// @dev Enforces timelock delay for launcher updates
    error TimelockNotFinished();

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration required between launcher update initiation and execution
    /// @dev Used to implement timelock for launcher address changes
    uint256 public constant LAUNCHER_TIMELOCK = 2 days;

    /// @notice Initialization code hash for pair contract creation
    /// @dev Used in CREATE2 deployment for deterministic pair addresses
    /// @dev Generated from the pair contract's creation code
    bytes32 public constant INIT_CODE_PAIR_HASH =
    0x5b2c36488f6f5358809016c6ef0a4062c13d936275a7f4ce9f23145c6a79fc18;
}
