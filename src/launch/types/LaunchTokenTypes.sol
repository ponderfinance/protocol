// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

library LaunchTokenTypes {
    /// @notice Protocol constants
    uint256 constant TOTAL_SUPPLY = 555_555_555 ether;
    uint256 constant VESTING_DURATION = 180 days;
    uint256 constant MIN_CLAIM_INTERVAL = 1 hours;
    uint256 constant TRADING_RESTRICTION_PERIOD = 15 minutes;

    /// @notice Custom errors
    error TransfersDisabled();
    error Unauthorized();
    error InsufficientAllowance();
    error NoTokensAvailable();
    error VestingNotStarted();
    error VestingNotInitialized();
    error VestingAlreadyInitialized();
    error InvalidCreator();
    error InvalidAmount();
    error ExcessiveAmount();
    error InsufficientLauncherBalance();
    error PairAlreadySet();
    error ClaimTooFrequent();
    error ZeroAddress();
    error NotPendingLauncher();
    error MaxTransferExceeded();
    error ContractBuyingRestricted();
    error TradingRestricted();
}
