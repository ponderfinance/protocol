// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    LAUNCHER TYPE DEFINITIONS
//////////////////////////////////////////////////////////////*/

/// @title FiveFiveFiveLauncherTypes
/// @author taayyohh
/// @notice Defines all custom types, constants, and errors for the 555 launch platform
/// @dev Contains optimized storage layouts and packed values for gas efficiency
///      All percentage values use basis points (10000 = 100%)
library FiveFiveFiveLauncherTypes {

    /*//////////////////////////////////////////////////////////////
                            TIME CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration of the launch period
    /// @dev Time window for accepting contributions
    uint256 public constant LAUNCH_DURATION = 7 days;

    /// @notice Duration of LP token lock period
    /// @dev Period during which LP tokens cannot be withdrawn
    uint256 public constant LP_LOCK_PERIOD = 180 days;

    /// @notice Maximum age of price data before considered stale
    /// @dev Used in price validation checks
    uint256 public constant PRICE_STALENESS_THRESHOLD = 2 hours;

    /*//////////////////////////////////////////////////////////////
                        ECONOMIC CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Target raise amount for each launch
    /// @dev In KUB units (wei)
    uint256 public constant TARGET_RAISE = 5555 ether;

    /// @notice Basis points denominator for percentage calculations
    /// @dev 10000 = 100%
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum liquidity required for pool creation
    /// @dev In KUB units (wei)
    uint256 public constant MIN_POOL_LIQUIDITY = 50 ether;

    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTION LIMITS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum percentage of raise that can be in PONDER
    /// @dev 2000 = 20% in basis points
    uint16 public constant MAX_PONDER_PERCENT = 2000;

    /// @notice Minimum KUB contribution amount
    /// @dev In KUB units (wei)
    uint256 public constant MIN_KUB_CONTRIBUTION = 0.01 ether;

    /// @notice Minimum PONDER contribution amount
    /// @dev In PONDER units (wei)
    uint256 public constant MIN_PONDER_CONTRIBUTION = 0.1 ether;

    /*//////////////////////////////////////////////////////////////
                        TOKEN DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Percentage of tokens allocated to creator
    /// @dev 1000 = 10% in basis points
    uint16 public constant CREATOR_PERCENT = 1000;

    /// @notice Percentage of tokens allocated to liquidity
    /// @dev 2000 = 20% in basis points
    uint16 public constant LP_PERCENT = 2000;

    /// @notice Percentage of tokens allocated to contributors
    /// @dev 7000 = 70% in basis points
    uint16 public constant CONTRIBUTOR_PERCENT = 7000;

    /*//////////////////////////////////////////////////////////////
                        KUB DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Percentage of KUB allocated to token-KUB LP
    /// @dev 6000 = 60% in basis points
    uint16 public constant KUB_TO_MEME_KUB_LP = 6000;

    /// @notice Percentage of KUB allocated to PONDER-KUB LP
    /// @dev 2000 = 20% in basis points
    uint16 public constant KUB_TO_PONDER_KUB_LP = 2000;

    /// @notice Percentage of KUB allocated to token-PONDER LP
    /// @dev 2000 = 20% in basis points
    uint16 public constant KUB_TO_MEME_PONDER_LP = 2000;

    /*//////////////////////////////////////////////////////////////
                        PONDER DISTRIBUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Percentage of PONDER allocated to token-PONDER LP
    /// @dev 8000 = 80% in basis points
    uint16 public constant PONDER_TO_MEME_PONDER = 8000;

    /// @notice Percentage of PONDER to be burned
    /// @dev 2000 = 20% in basis points
    uint16 public constant PONDER_TO_BURN = 2000;


    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice Base information about a token launch
    /// @dev Optimized for packing into storage slots
    /// @dev Contains core launch parameters and state flags
    struct LaunchBaseInfo {
        address tokenAddress;        // 20 bytes
        address creator;            // 20 bytes
        uint40 lpUnlockTime;       // 5 bytes
        uint40 launchDeadline;     // 5 bytes
        bool launched;             // 1 byte
        bool cancelled;            // 1 byte
        bool isFinalizingLaunch;   // 1 byte
        string name;               // separate slot(s)
        string symbol;             // separate slot(s)
        string imageURI;           // separate slot(s)
    }

    /// @notice Tracks all contribution amounts for a launch
    /// @dev Each value uses full 256 bits for maximum range
    struct ContributionState {
        uint256 kubCollected;          // Total KUB raised
        uint256 ponderCollected;       // Total PONDER collected
        uint256 ponderValueCollected;  // KUB value of PONDER
        uint256 tokensDistributed;     // Tokens given to contributors
    }

    /// @notice Token distribution tracking for a launch
    /// @dev Packed into single storage slot using uint128
    struct TokenAllocation {
        uint128 tokensForContributors;  // Tokens for contributors
        uint128 tokensForLP;            // Tokens for liquidity
    }

    /// @notice Pool addresses and state for a launch
    /// @dev Stores addresses of created liquidity pools
    struct PoolInfo {
        address memeKubPair;     // Token-KUB pool
        address memePonderPair;  // Token-PONDER pool
    }

    /// @notice Tracks individual contributor information
    /// @dev Packed into two storage slots using uint128
    struct ContributorInfo {
        uint128 kubContributed;     // KUB contributed
        uint128 ponderContributed;  // PONDER contributed
        uint128 ponderValue;        // KUB value of PONDER
        uint128 tokensReceived;     // Tokens received
    }

    /// @notice Input parameters for launch creation
    /// @dev Used in launch initialization
    struct LaunchParams {
        string name;      // Token name
        string symbol;    // Token symbol
        string imageURI;  // Token image URI
    }

    /// @notice Internal state for handling contributions
    /// @dev Used in contribution processing
    struct ContributionResult {
        uint256 contribution;       // Amount contributed
        uint256 tokensToDistribute; // Tokens to give
        uint256 refund;            // Amount to refund
    }

    /// @notice Configuration for pool creation
    /// @dev Used in liquidity pool setup
    struct PoolConfig {
        uint256 kubAmount;     // KUB for liquidity
        uint256 tokenAmount;   // Tokens for liquidity
        uint256 ponderAmount;  // PONDER for liquidity
    }

    /// @notice State for handling launch finalization
    /// @dev Uses packed values for gas efficiency
    struct FinalizationState {
        address tokenAddress;     // Token being launched
        uint128 kubAmount;       // KUB for finalization
        uint128 ponderAmount;    // PONDER for finalization
        uint256 tokenAmount;     // Tokens for finalization
    }

    /// @notice Main launch info struct combining all launch data
    /// @dev Core data structure for launch management
    struct LaunchInfo {
        LaunchBaseInfo base;               // Basic launch info
        ContributionState contributions;    // Contribution tracking
        TokenAllocation allocation;         // Token allocations
        PoolInfo pools;                    // Pool addresses
        mapping(address => ContributorInfo) contributors;  // Per-contributor data
    }
}
