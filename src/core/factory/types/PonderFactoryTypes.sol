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
