// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    LAUNCH TOKEN DEFINITIONS
//////////////////////////////////////////////////////////////*/

/// @title LaunchTokenTypes
/// @author taayyohh
/// @notice Defines constants and custom errors for launch token implementation
/// @dev Contains core parameters for token economics and error handling
library LaunchTokenTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Total supply of launch tokens
    /// @dev Fixed supply in wei units (18 decimals)
    /// @dev 555,555,555 tokens total
    uint256 constant public TOTAL_SUPPLY = 555_555_555 ether;

    /// @notice Duration of creator token vesting period
    /// @dev Time period over which creator allocation vests
    /// @dev 180 days from launch
    uint256 constant public VESTING_DURATION = 180 days;

    /// @notice Minimum time between vested token claims
    /// @dev Prevents excessive claim transactions
    /// @dev 1 hour cooldown period
    uint256 constant public MIN_CLAIM_INTERVAL = 1 hours;

    /// @notice Initial trading restriction period after launch
    /// @dev Prevents immediate large trades post-launch
    /// @dev 15 minutes from trading enable
    uint256 constant public TRADING_RESTRICTION_PERIOD = 15 minutes;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    // Permission Errors
    error Unauthorized();                 /// @dev Caller lacks required permission
    error InvalidCreator();               /// @dev Invalid creator address specified
    error NotPendingLauncher();           /// @dev Caller not pending launcher

    // Token State Errors
    error TransfersDisabled();            /// @dev Token transfers not yet enabled
    error TradingRestricted();            /// @dev Within trading restriction period
    error PairAlreadySet();               /// @dev Trading pairs already configured

    // Transfer Errors
    error InsufficientAllowance();        /// @dev Spender allowance too low
    error MaxTransferExceeded();          /// @dev Transfer exceeds size limit
    error ContractBuyingRestricted();     /// @dev Contract purchases restricted

    // Vesting Errors
    error NoTokensAvailable();            /// @dev No tokens available to claim
    error VestingNotStarted();            /// @dev Vesting period not started
    error VestingNotInitialized();        /// @dev Vesting not set up
    error VestingAlreadyInitialized();    /// @dev Vesting already configured
    error ClaimTooFrequent();             /// @dev Claim within cooldown period

    // Balance Errors
    error InvalidAmount();                /// @dev Invalid transfer amount
    error ExcessiveAmount();              /// @dev Amount exceeds limits
    error InsufficientLauncherBalance();  /// @dev Launcher lacks tokens

    // Parameter Errors
    error ZeroAddress();                  /// @dev Invalid zero address provided
}
