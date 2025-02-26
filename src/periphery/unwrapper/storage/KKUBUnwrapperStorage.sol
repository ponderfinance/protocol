// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    KKUB UNWRAPPER STORAGE
//////////////////////////////////////////////////////////////*/

/// @title KKUBUnwrapperStorage
/// @author taayyohh
/// @notice Storage layout for KKUB unwrapping system
/// @dev Abstract contract defining state variables for unwrapper implementation
///      Storage slots are carefully ordered to optimize gas costs
///      Includes storage gap for future upgrades
abstract contract KKUBUnwrapperStorage {
    /*//////////////////////////////////////////////////////////////
                        TIMING STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp of the most recent successful withdrawal
    /// @dev Used for enforcing withdrawal delay period
    /// @dev Updated automatically after each successful withdrawal
    /// @dev Stored in Unix timestamp format
    uint256 internal lastWithdrawalTime;

    /*//////////////////////////////////////////////////////////////
                        BALANCE TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks ETH reserved for pending unwrap operations
    /// @dev Amount in wei (1e18) that is committed but not yet released
    /// @dev Increases when unwrap is initiated, decreases when completed
    /// @dev Critical for preventing over-commitment of ETH
    uint256 internal _lockedBalance;
}
