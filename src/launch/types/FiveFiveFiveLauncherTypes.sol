// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FiveFiveFiveLauncherTypes
/// @author taayyohh
/// @notice Defines all custom types, constants, and errors used in the 555 token launch platform
library FiveFiveFiveLauncherTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration settings
    uint256 public constant LAUNCH_DURATION = 7 days;
    uint256 public constant LP_LOCK_PERIOD = 180 days;
    uint256 public constant PRICE_STALENESS_THRESHOLD = 2 hours;

    /// @notice Target raise and contribution limits
    uint256 public constant TARGET_RAISE = 5555 ether;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_PONDER_PERCENT = 2000; // 20% max PONDER contribution

    /// @notice KUB distribution percentages in basis points
    uint256 public constant KUB_TO_MEME_KUB_LP = 6000;    // 60% to token-KUB LP
    uint256 public constant KUB_TO_PONDER_KUB_LP = 2000;  // 20% to PONDER-KUB LP
    uint256 public constant KUB_TO_MEME_PONDER_LP = 2000; // 20% to token-PONDER LP

    /// @notice PONDER distribution percentages in basis points
    uint256 public constant PONDER_TO_MEME_PONDER = 8000; // 80% to token-PONDER LP
    uint256 public constant PONDER_TO_BURN = 2000;        // 20% to burn

    /// @notice Token distribution percentages in basis points
    uint256 public constant CREATOR_PERCENT = 1000;      // 10% to creator
    uint256 public constant LP_PERCENT = 2000;           // 20% to LP
    uint256 public constant CONTRIBUTOR_PERCENT = 7000;  // 70% to contributors

    /// @notice Minimum contribution and liquidity requirements
    uint256 public constant MIN_KUB_CONTRIBUTION = 0.01 ether;   // Minimum 0.01 KUB
    uint256 public constant MIN_PONDER_CONTRIBUTION = 0.1 ether; // Minimum 0.1 PONDER
    uint256 public constant MIN_POOL_LIQUIDITY = 50 ether;      // Minimum 50 KUB worth for pool

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error LaunchNotFound();                  /// Launch ID doesn't exist
    error AlreadyLaunched();                 /// Launch has already completed
    error ImageRequired();                   /// Image URI is required
    error InvalidTokenParams();              /// Token parameters are invalid
    error Unauthorized();                    /// Caller is not authorized
    error LPStillLocked();                  /// LP tokens are still locked
    error StalePrice();                      /// Price data is stale
    error ExcessiveContribution();           /// Contribution exceeds limit
    error InsufficientLPTokens();            /// Not enough tokens for LP
    error ExcessivePonderContribution();     /// PONDER contribution too high
    error LaunchExpired();                   /// Launch deadline has passed
    error LaunchNotCancellable();            /// Launch cannot be cancelled
    error NoContributionToRefund();          /// No contribution to refund
    error RefundFailed();                    /// Refund transfer failed
    error ContributionTooSmall();            /// Contribution below minimum
    error InsufficientPoolLiquidity();       /// Pool liquidity too low
    error TokenNameExists();                 /// Token name already used
    error TokenSymbolExists();               /// Token symbol already used
    error LaunchBeingFinalized();            /// Launch is being finalized
    error EthTransferFailed();               /// ETH transfer failed
    error ExcessivePriceDeviation();         /// Price deviation too high
    error InsufficientPriceHistory();        /// Not enough price history
    error PriceOutOfBounds();                /// Price outside valid range
    error InsufficientLiquidity();           /// Not enough liquidity
    error LaunchDeadlinePassed();            /// Launch deadline expired
    error ZeroAddress();                     /// Zero address provided
    error LaunchStillActive();               /// Launch is still active
    error LaunchSucceeded();                 /// Launch was successful
    error TokenApprovalRequired();           /// Token approval needed
    error KubTransferFailed();               /// KUB transfer failed
    error InsufficientBalance();
    error TokenTransferFailed();
    error ApprovalFailed();

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Base information about a token launch
    struct LaunchBaseInfo {
        address tokenAddress;
        string name;
        string symbol;
        string imageURI;
        bool launched;
        address creator;
        uint256 lpUnlockTime;
        uint256 launchDeadline;
        bool cancelled;
        bool isFinalizingLaunch;
    }

    /// @notice Tracks all contribution amounts for a launch
    struct ContributionState {
        uint256 kubCollected;
        uint256 ponderCollected;
        uint256 ponderValueCollected;
        uint256 tokensDistributed;
    }

    /// @notice Token distribution tracking for a launch
    struct TokenAllocation {
        uint256 tokensForContributors;
        uint256 tokensForLP;
    }

    /// @notice Pool addresses and state for a launch
    struct PoolInfo {
        address memeKubPair;
        address memePonderPair;
    }

    /// @notice Main launch info struct combining all launch data
    struct LaunchInfo {
        LaunchBaseInfo base;
        ContributionState contributions;
        TokenAllocation allocation;
        PoolInfo pools;
        mapping(address => ContributorInfo) contributors;
    }

    /// @notice Tracks individual contributor information
    struct ContributorInfo {
        uint256 kubContributed;
        uint256 ponderContributed;
        uint256 ponderValue;
        uint256 tokensReceived;
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
        uint256 kubAmount;
        uint256 ponderAmount;
        uint256 tokenAmount;
    }
}
