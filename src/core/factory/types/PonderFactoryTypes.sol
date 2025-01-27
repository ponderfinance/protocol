// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PonderFactoryTypes
 * @notice Type definitions for the Ponder Factory contract
 * @dev Contains all custom errors and constants used in the factory
 */
library PonderFactoryTypes {
    // Custom Errors
    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error Forbidden();
    error InvalidFeeReceiver();
    error InvalidLauncher();
    error TimelockNotFinished();

    // Constants
    uint256 public constant LAUNCHER_TIMELOCK = 2 days;

    /**
    * @dev Hash of the init code of the pair contract
     * @notice Used for deterministic pair addresses
     */
    bytes32 public constant INIT_CODE_PAIR_HASH =
    0x5b2c36488f6f5358809016c6ef0a4062c13d936275a7f4ce9f23145c6a79fc18;
}
