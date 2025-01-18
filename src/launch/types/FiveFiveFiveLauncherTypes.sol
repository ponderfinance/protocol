// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title FiveFiveFiveLauncherTypes
/// @author taayyohh
/// @notice Defines all custom types and errors used in the 555 token launch platform
interface FiveFiveFiveLauncherTypes {
    /// @notice Base information about a token launch
    /// @param tokenAddress The address of the launched token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param imageURI The URI for the token's image
    /// @param launched Whether the launch has been completed
    /// @param creator The address of the launch creator
    /// @param lpUnlockTime Timestamp when LP tokens can be withdrawn
    /// @param launchDeadline Timestamp when the launch period ends
    /// @param cancelled Whether the launch has been cancelled
    /// @param isFinalizingLaunch Whether the launch is in the process of being finalized
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
    /// @param kubCollected Total KUB collected
    /// @param ponderCollected Total PONDER collected
    /// @param ponderValueCollected KUB value of collected PONDER
    /// @param tokensDistributed Total tokens distributed to contributors
    struct ContributionState {
        uint256 kubCollected;
        uint256 ponderCollected;
        uint256 ponderValueCollected;
        uint256 tokensDistributed;
    }

    /// @notice Token distribution tracking for a launch
    /// @param tokensForContributors Amount of tokens allocated to contributors
    /// @param tokensForLP Amount of tokens allocated for liquidity pools
    struct TokenAllocation {
        uint256 tokensForContributors;
        uint256 tokensForLP;
    }

    /// @notice Pool addresses and state for a launch
    /// @param memeKubPair Address of the token-KUB pair
    /// @param memePonderPair Address of the token-PONDER pair
    struct PoolInfo {
        address memeKubPair;
        address memePonderPair;
    }

    /// @notice Main launch info struct combining all launch data
    /// @param base Basic launch information
    /// @param contributions Contribution tracking
    /// @param allocation Token allocation information
    /// @param pools Pool addresses
    /// @param contributors Mapping of contributor addresses to their contribution info
    struct LaunchInfo {
        LaunchBaseInfo base;
        ContributionState contributions;
        TokenAllocation allocation;
        PoolInfo pools;
        mapping(address => ContributorInfo) contributors;
    }

    /// @notice Tracks individual contributor information
    /// @param kubContributed Amount of KUB contributed
    /// @param ponderContributed Amount of PONDER contributed
    /// @param ponderValue KUB value of PONDER contribution
    /// @param tokensReceived Amount of tokens received
    struct ContributorInfo {
        uint256 kubContributed;
        uint256 ponderContributed;
        uint256 ponderValue;
        uint256 tokensReceived;
    }

    /// @notice Input parameters for launch creation
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param imageURI The URI for the token's image
    struct LaunchParams {
        string name;
        string symbol;
        string imageURI;
    }

    /// @notice Internal state for handling contributions
    /// @param contribution Amount being contributed
    /// @param tokensToDistribute Amount of tokens to distribute
    /// @param refund Amount to refund if any
    struct ContributionResult {
        uint256 contribution;
        uint256 tokensToDistribute;
        uint256 refund;
    }

    /// @notice Configuration for pool creation
    /// @param kubAmount Amount of KUB for pool
    /// @param tokenAmount Amount of tokens for pool
    /// @param ponderAmount Amount of PONDER for pool
    struct PoolConfig {
        uint256 kubAmount;
        uint256 tokenAmount;
        uint256 ponderAmount;
    }

    /// @notice State for handling launch finalization
    /// @param tokenAddress Address of the token being launched
    /// @param kubAmount Amount of KUB for finalization
    /// @param ponderAmount Amount of PONDER for finalization
    /// @param tokenAmount Amount of tokens for finalization
    struct FinalizationState {
        address tokenAddress;
        uint256 kubAmount;
        uint256 ponderAmount;
        uint256 tokenAmount;
    }

    /// @notice Custom errors with descriptive names
    error LaunchNotFound();                  /// Launch ID doesn't exist
    error AlreadyLaunched();                 /// Launch has already completed
    error ImageRequired();                   /// Image URI is required
    error InvalidTokenParams();              /// Token parameters are invalid
    error Unauthorized();                    /// Caller is not authorized
    error LPStillLocked();                   /// LP tokens are still locked
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
    error ZeroAddress();
}
