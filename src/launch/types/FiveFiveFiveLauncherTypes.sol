// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FiveFiveFiveLauncherTypes
/// @author taayyohh
/// @notice Defines all custom types, constants, and errors used in the 555 token launch platform
library FiveFiveFiveLauncherTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Time Constants
    uint256 public constant LAUNCH_DURATION = 7 days;
    uint256 public constant LP_LOCK_PERIOD = 180 days;
    uint256 public constant PRICE_STALENESS_THRESHOLD = 2 hours;

    // Target and Base Values
    uint256 public constant TARGET_RAISE = 5555 ether;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_POOL_LIQUIDITY = 50 ether;

    // Contribution Limits
    uint16 public constant MAX_PONDER_PERCENT = 2000;    // 20%
    uint256 public constant MIN_KUB_CONTRIBUTION = 0.01 ether;
    uint256 public constant MIN_PONDER_CONTRIBUTION = 0.1 ether;

    // Token Distribution (packed into uint16s to save gas)
    uint16 public constant CREATOR_PERCENT = 1000;       // 10%
    uint16 public constant LP_PERCENT = 2000;            // 20%
    uint16 public constant CONTRIBUTOR_PERCENT = 7000;   // 70%

    // KUB Distribution (packed into uint16s)
    uint16 public constant KUB_TO_MEME_KUB_LP = 6000;    // 60%
    uint16 public constant KUB_TO_PONDER_KUB_LP = 2000;  // 20%
    uint16 public constant KUB_TO_MEME_PONDER_LP = 2000; // 20%

    // PONDER Distribution (packed into uint16s)
    uint16 public constant PONDER_TO_MEME_PONDER = 8000; // 80%
    uint16 public constant PONDER_TO_BURN = 2000;        // 20%

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error LaunchNotFound();
    error AlreadyLaunched();
    error LaunchStillActive();
    error LaunchSucceeded();
    error LaunchDeadlinePassed();
    error LaunchBeingFinalized();
    error LaunchNotCancellable();
    error ImageRequired();
    error InvalidTokenParams();
    error TokenNameExists();
    error TokenSymbolExists();
    error InsufficientLPTokens();
    error TokenApprovalRequired();
    error TokenTransferFailed();
    error ApprovalFailed();
    error StalePrice();
    error ExcessivePriceDeviation();
    error InsufficientPriceHistory();
    error PriceOutOfBounds();
    error ExcessiveContribution();
    error InsufficientPoolLiquidity();
    error InsufficientLiquidity();
    error ContributionTooSmall();
    error Unauthorized();
    error ZeroAddress();
    error InsufficientBalance();
    error NoContributionToRefund();
    error RefundFailed();

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Base information about a token launch
    /// @dev Optimized for packing into storage slots
    struct LaunchBaseInfo {
        address tokenAddress;        // 20 bytes
        address creator;            // 20 bytes
        uint40 lpUnlockTime;       // 5 bytes
        uint40 launchDeadline;     // 5 bytes
        bool launched;             // 1 byte
        bool cancelled;            // 1 byte
        bool isFinalizingLaunch;   // 1 byte
        // The above fits in 2 slots (32 bytes each)
        string name;               // separate slot(s)
        string symbol;             // separate slot(s)
        string imageURI;           // separate slot(s)
    }

    /// @notice Tracks all contribution amounts for a launch
    /// @dev Single slot packing where possible
    struct ContributionState {
        uint256 kubCollected;          // 32 bytes
        uint256 ponderCollected;       // 32 bytes
        uint256 ponderValueCollected;  // 32 bytes
        uint256 tokensDistributed;     // 32 bytes
    }

    /// @notice Token distribution tracking for a launch
    struct TokenAllocation {
        uint128 tokensForContributors;  // 16 bytes
        uint128 tokensForLP;            // 16 bytes - packed into single slot
    }

    /// @notice Pool addresses and state for a launch
    struct PoolInfo {
        address memeKubPair;     // 20 bytes
        address memePonderPair;  // 20 bytes - can pack with additional flags if needed
    }

    /// @notice Tracks individual contributor information
    /// @dev Packed into two storage slots
    struct ContributorInfo {
        uint128 kubContributed;     // 16 bytes
        uint128 ponderContributed;  // 16 bytes - first slot
        uint128 ponderValue;        // 16 bytes
        uint128 tokensReceived;     // 16 bytes - second slot
    }

    /// @notice Input parameters for launch creation
    struct LaunchParams {
        string name;
        string symbol;
        string imageURI;
    }

    /// @notice Internal state for handling contributions
    struct ContributionResult {
        uint256 contribution;
        uint256 tokensToDistribute;
        uint256 refund;
    }

    /// @notice Configuration for pool creation
    struct PoolConfig {
        uint256 kubAmount;
        uint256 tokenAmount;
        uint256 ponderAmount;
    }

    /// @notice State for handling launch finalization
    struct FinalizationState {
        address tokenAddress;
        uint128 kubAmount;      // 16 bytes
        uint128 ponderAmount;   // 16 bytes - packed into single slot with kubAmount
        uint256 tokenAmount;    // separate slot
    }

    /// @notice Main launch info struct combining all launch data
    struct LaunchInfo {
        LaunchBaseInfo base;
        ContributionState contributions;
        TokenAllocation allocation;
        PoolInfo pools;
        mapping(address => ContributorInfo) contributors;
    }
}
