// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER MASTERCHEF TYPES
//////////////////////////////////////////////////////////////*/

/// @title PonderMasterChefTypes
/// @author taayyohh
/// @notice Type definitions for Ponder protocol's farming rewards system
/// @dev Library containing all shared types, constants, and errors used in the MasterChef system
library PonderMasterChefTypes {
    /*//////////////////////////////////////////////////////////////
                            USER POSITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice User staking position information
    /// @dev Tracks individual user's staking data and boost mechanics
    struct UserInfo {
        /// @notice User's staked LP token amount
        /// @dev Raw amount of LP tokens deposited by user
        uint256 amount;

        /// @notice Reward tracking for accurate distribution
        /// @dev Bookkeeping variable used to track entitled rewards
        uint256 rewardDebt;

        /// @notice PONDER tokens staked for boost
        /// @dev Amount of PONDER tokens locked for multiplier boost
        uint256 ponderStaked;

        /// @notice User's boosted share calculation
        /// @dev Amount of shares after applying boost multiplier
        uint256 weightedShares;
    }

    /*//////////////////////////////////////////////////////////////
                            POOL SETTINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Farming pool configuration and state
    /// @dev Contains all settings and current state for a farming pool
    struct PoolInfo {
        /// @notice Address of pool's LP token
        /// @dev Token that users stake to earn rewards
        address lpToken;

        /// @notice Pool's reward allocation weight
        /// @dev Determines pool's share of PONDER emissions
        uint256 allocPoint;

        /// @notice Last reward distribution timestamp
        /// @dev Used to calculate accumulated rewards
        uint256 lastRewardTime;

        /// @notice Accumulated rewards per share
        /// @dev Tracked with 1e12 precision for accurate reward calculation
        uint256 accPonderPerShare;

        /// @notice Total LP tokens in pool
        /// @dev Sum of all user deposits
        uint256 totalStaked;

        /// @notice Total boosted shares in pool
        /// @dev Sum of all user shares after boost
        uint256 totalWeightedShares;

        /// @notice Deposit fee rate
        /// @dev Fee charged on deposits in basis points (1 BP = 0.01%)
        uint16 depositFeeBP;

        /// @notice Maximum boost multiplier
        /// @dev Caps the boost multiplier for this pool
        uint16 boostMultiplier;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Base for percentage calculations
    /// @dev 100% = 10000 basis points
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Base multiplier for boost calculations
    /// @dev 1x = 10000
    uint256 public constant BASE_MULTIPLIER = 10000;

    /// @notice Minimum boost multiplier
    /// @dev 2x = 20000
    uint256 public constant MIN_BOOST_MULTIPLIER = 20000;

    /// @notice Required PONDER stake relative to LP value
    /// @dev 10% = 1000 basis points
    uint256 public constant BOOST_THRESHOLD_PERCENT = 1000;

    /// @notice Maximum additional boost percentage
    /// @dev 100% = 10000 basis points
    uint256 public constant MAX_EXTRA_BOOST_PERCENT = 10000;

    /// @notice Maximum allocation points per pool
    /// @dev Prevents pool reward manipulation
    uint256 public constant MAX_ALLOC_POINT = 10000;
}
