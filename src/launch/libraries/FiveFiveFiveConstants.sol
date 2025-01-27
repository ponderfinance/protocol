// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FiveFiveFiveConstants
/// @author taayyohh
/// @notice Constants used throughout the 555 token launch platform
/// @dev All time-based constants are in seconds, percentages in basis points
library FiveFiveFiveConstants {
    /*//////////////////////////////////////////////////////////////
                            TIME CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration of the launch period
    uint256 internal constant LAUNCH_DURATION = 7 days;

    /// @notice Duration LP tokens are locked after launch
    uint256 internal constant LP_LOCK_PERIOD = 180 days;

    /// @notice Maximum time before price is considered stale
    uint256 internal constant PRICE_STALENESS_THRESHOLD = 2 hours;

    /*//////////////////////////////////////////////////////////////
                        FUNDRAISING CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Total fundraising target in wei
    uint256 internal constant TARGET_RAISE = 5555 ether;

    /// @notice Basis points denominator for percentage calculations
    uint256 internal constant BASIS_POINTS = 10000;

    /// @notice Maximum percentage of raise that can be in PONDER (20%)
    uint256 internal constant MAX_PONDER_PERCENT = 2000;

    /*//////////////////////////////////////////////////////////////
                        DISTRIBUTION CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // KUB Distribution
    uint256 internal constant KUB_TO_MEME_KUB_LP = 6000;    // 60%
    uint256 internal constant KUB_TO_PONDER_KUB_LP = 2000;  // 20%
    uint256 internal constant KUB_TO_MEME_PONDER_LP = 2000; // 20%

    // PONDER Distribution
    uint256 internal constant PONDER_TO_MEME_PONDER = 8000; // 80%
    uint256 internal constant PONDER_TO_BURN = 2000;        // 20%

    // Token Distribution
    uint256 internal constant CREATOR_PERCENT = 1000;      // 10%
    uint256 internal constant LP_PERCENT = 2000;           // 20%
    uint256 internal constant CONTRIBUTOR_PERCENT = 7000;  // 70%

    /*//////////////////////////////////////////////////////////////
                        MINIMUM REQUIREMENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum KUB contribution amount
    uint256 internal constant MIN_KUB_CONTRIBUTION = 0.01 ether;

    /// @notice Minimum PONDER contribution amount
    uint256 internal constant MIN_PONDER_CONTRIBUTION = 0.1 ether;

    /// @notice Minimum liquidity required for pool creation
    uint256 internal constant MIN_POOL_LIQUIDITY = 50 ether;

    /*//////////////////////////////////////////////////////////////
                            MATH CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum value for uint256
    uint256 internal constant MAX_UINT = type(uint256).max;
}
