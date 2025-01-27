// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PonderMasterChefTypes
 * @notice Type definitions for the Ponder MasterChef contract
 * @dev Contains all shared constants, custom errors, and structs used in the MasterChef system
 */
library PonderMasterChefTypes {
    /**
     * @notice User staking information including boost mechanics
     * @param amount Amount of LP tokens staked
     * @param rewardDebt Bookkeeping value for reward calculations
     * @param ponderStaked Amount of PONDER tokens staked for boosting
     * @param weightedShares User's boosted share amount
     */
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 ponderStaked;
        uint256 weightedShares;
    }

    /**
     * @notice Pool information including rewards and boost settings
     * @param lpToken Address of the LP token for this pool
     * @param allocPoint Pool's share of PONDER emissions
     * @param lastRewardTime Last timestamp when rewards were distributed
     * @param accPonderPerShare Accumulated PONDER per share, scaled by 1e12
     * @param totalStaked Total LP tokens staked in this pool
     * @param totalWeightedShares Total boosted shares in this pool
     * @param depositFeeBP Deposit fee in basis points (1 BP = 0.01%)
     * @param boostMultiplier Maximum boost multiplier for this pool
     */
    struct PoolInfo {
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accPonderPerShare;
        uint256 totalStaked;
        uint256 totalWeightedShares;
        uint16 depositFeeBP;
        uint16 boostMultiplier;
    }

    // Custom Errors
    error InvalidBoostMultiplier();
    error ExcessiveDepositFee();
    error Forbidden();
    error InvalidPool();
    error InvalidPair();
    error InvalidAmount();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientAmount();
    error BoostTooHigh();
    error TransferFailed();
    error ExcessiveAllocation();
    error DuplicatePool();
    error NoTokensTransferred();

    // Constants
    /// @notice Base for percentage calculations (100% = 10000)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Base multiplier for boost calculations (1x = 10000)
    uint256 public constant BASE_MULTIPLIER = 10000;

    /// @notice Minimum boost multiplier (2x = 20000)
    uint256 public constant MIN_BOOST_MULTIPLIER = 20000;

    /// @notice Required PONDER stake relative to LP value (10%)
    uint256 public constant BOOST_THRESHOLD_PERCENT = 1000;

    /// @notice Maximum additional boost percentage (100%)
    uint256 public constant MAX_EXTRA_BOOST_PERCENT = 10000;

    /// @notice Maximum allocation points per pool to prevent manipulation
    uint256 public constant MAX_ALLOC_POINT = 10000;
}
