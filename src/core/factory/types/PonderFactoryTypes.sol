// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PonderFactoryTypes
 * @notice Type definitions for the Ponder Factory contract
 * @dev Contains all custom errors and constants used in the factory
 */
library PonderFactoryTypes {
    /**
     * @dev Error thrown when trying to create a pair with identical tokens
     */
    error IdenticalAddresses();

    /**
     * @dev Error thrown when a required address parameter is zero
     */
    error ZeroAddress();

    /**
     * @dev Error thrown when attempting to create a pair that already exists
     */
    error PairExists();

    /**
     * @dev Error thrown when a caller lacks the required permissions
     */
    error Forbidden();

    /**
     * @dev Error thrown when attempting to set an invalid fee receiver
     */
    error InvalidFeeReceiver();

    /**
     * @dev Error thrown when attempting to set an invalid launcher address
     */
    error InvalidLauncher();

    /**
     * @dev Error thrown when trying to apply launcher change before timelock expires
     */
    error TimelockNotFinished();

    /**
     * @dev Timelock duration for launcher updates
     */
    uint256 constant LAUNCHER_TIMELOCK = 2 days;

    /**
     * @dev Hash of the init code of the pair contract
     * @notice Used for deterministic pair addresses
     */
    bytes32 constant INIT_CODE_PAIR_HASH = 0x5b2c36488f6f5358809016c6ef0a4062c13d936275a7f4ce9f23145c6a79fc18;
}
