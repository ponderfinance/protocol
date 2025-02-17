// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FiveFiveFiveLauncherTypes } from "./types/FiveFiveFiveLauncherTypes.sol";

/*//////////////////////////////////////////////////////////////
                    LAUNCHER INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IFiveFiveFiveLauncher
/// @author taayyohh
/// @notice Interface for the 555 token launch platform
/// @dev Facilitates token launches with dual contribution options:
///      - KUB (native token)
///      - PONDER (platform token)
interface IFiveFiveFiveLauncher {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new token launch is created
    /// @param launchId Unique identifier for the launch
    /// @param token Address of the launched token contract
    /// @param creator Address that created the launch
    /// @param imageURI URI of the token's image
    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);

    /// @notice Emitted when KUB is contributed to a launch
    /// @param launchId Identifier of the launch
    /// @param contributor Address making the contribution
    /// @param amount Amount of KUB contributed (in wei)
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);

    /// @notice Emitted when PONDER is contributed to a launch
    /// @param launchId Identifier of the launch
    /// @param contributor Address making the contribution
    /// @param amount Amount of PONDER contributed
    /// @param kubValue KUB value of the PONDER contribution
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);

    /// @notice Emitted when launch tokens are distributed
    /// @param launchId Identifier of the launch
    /// @param recipient Address receiving the tokens
    /// @param amount Number of tokens distributed
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a launch reaches completion
    /// @param launchId Identifier of the launch
    /// @param kubRaised Total KUB raised in the launch
    /// @param ponderRaised Total PONDER raised in the launch
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);

    /// @notice Emitted when creator withdraws LP tokens
    /// @param launchId Identifier of the launch
    /// @param creator Address of the launch creator
    /// @param timestamp Time of withdrawal
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 timestamp);

    /// @notice Emitted when PONDER tokens are burned
    /// @param launchId Identifier of the launch
    /// @param amount Amount of PONDER tokens burned
    event PonderBurned(uint256 indexed launchId, uint256 amount);

    /// @notice Emitted when both KUB and PONDER pools are created
    /// @param launchId Identifier of the launch
    /// @param memeKubPair Address of the token-KUB pair
    /// @param memePonderPair Address of the token-PONDER pair
    /// @param kubLiquidity Amount of KUB added as liquidity
    /// @param ponderLiquidity Amount of PONDER added as liquidity
    event DualPoolsCreated(
        uint256 indexed launchId,
        address memeKubPair,
        address memePonderPair,
        uint256 kubLiquidity,
        uint256 ponderLiquidity
    );

    /// @notice Emitted when PONDER pool creation is skipped
    /// @param launchId Identifier of the launch
    /// @param ponderAmount Amount of PONDER that would have been used
    /// @param ponderValueInKub KUB value of the PONDER amount
    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);

    /// @notice Emitted when a refund is processed
    /// @param user Address receiving the refund
    /// @param kubAmount Amount of KUB refunded
    /// @param ponderAmount Amount of PONDER refunded
    /// @param tokenAmount Amount of tokens refunded
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);

    /// @notice Emitted when a launch is cancelled
    /// @param launchId Identifier of the launch
    /// @param creator Address of the launch creator
    /// @param kubCollected Total KUB collected before cancellation
    /// @param ponderCollected Total PONDER collected before cancellation
    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );

    /*//////////////////////////////////////////////////////////////
                        STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new token launch
    /// @param params Struct containing launch parameters
    /// @return launchId Unique identifier for the new launch
    /// @dev Deploys new token contract and initializes launch state
    function createLaunch(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) external returns (uint256 launchId);

    /// @notice Allows users to contribute KUB to a launch
    /// @param launchId Identifier of the launch to contribute to
    /// @dev Payable function accepting KUB contributions
    function contributeKUB(uint256 launchId) external payable;

    /// @notice Allows users to contribute PONDER to a launch
    /// @param launchId Identifier of the launch to contribute to
    /// @param amount Amount of PONDER to contribute
    /// @dev Requires PONDER token approval
    function contributePONDER(uint256 launchId, uint256 amount) external;

    /// @notice Allows contributors to claim refunds
    /// @param launchId Identifier of the launch
    /// @dev Available for failed or cancelled launches
    function claimRefund(uint256 launchId) external;

    /// @notice Allows creator to cancel their launch
    /// @param launchId Identifier of the launch to cancel
    /// @dev Only available before launch completion
    function cancelLaunch(uint256 launchId) external;

    /// @notice Allows creator to withdraw LP tokens
    /// @param launchId Identifier of the launch
    /// @dev Only available after lock period ends
    function withdrawLP(uint256 launchId) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets contributor information for a launch
    /// @param launchId Identifier of the launch
    /// @param contributor Address of the contributor
    /// @return kubContributed Amount of KUB contributed
    /// @return ponderContributed Amount of PONDER contributed
    /// @return ponderValue KUB value of PONDER contribution
    /// @return tokensReceived Amount of launch tokens received
    function getContributorInfo(uint256 launchId, address contributor) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    );

    /// @notice Gets contribution totals for a launch
    /// @param launchId Identifier of the launch
    /// @return kubCollected Total KUB collected
    /// @return ponderCollected Total PONDER collected
    /// @return ponderValueCollected KUB value of PONDER collected
    /// @return totalValue Combined value of all contributions
    function getContributionInfo(uint256 launchId) external view returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    );

    /// @notice Gets pool information for a launch
    /// @param launchId Identifier of the launch
    /// @return memeKubPair Address of token-KUB pair
    /// @return memePonderPair Address of token-PONDER pair
    /// @return hasSecondaryPool Whether PONDER pool exists
    function getPoolInfo(uint256 launchId) external view returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    );

    /// @notice Gets basic launch information
    /// @param launchId Identifier of the launch
    /// @return tokenAddress Address of the launched token
    /// @return name Name of the token
    /// @return symbol Symbol of the token
    /// @return imageURI URI of the token's image
    /// @return kubRaised Amount of KUB raised
    /// @return launched Whether launch is completed
    /// @return lpUnlockTime When LP tokens can be withdrawn
    function getLaunchInfo(uint256 launchId) external view returns (
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageURI,
        uint256 kubRaised,
        bool launched,
        uint256 lpUnlockTime
    );

    /// @notice Gets minimum contribution requirements
    /// @return minKub Minimum KUB contribution
    /// @return minPonder Minimum PONDER contribution
    /// @return minPoolLiquidity Minimum pool liquidity
    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    );

    /// @notice Gets remaining raise capacity
    /// @param launchId Identifier of the launch
    /// @return remainingTotal Total value that can still be raised
    /// @return remainingPonderValue Maximum additional PONDER value
    function getRemainingToRaise(uint256 launchId) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    );

    /// @notice Get launch deadline timestamp
    /// @dev Returns the raw uint40 deadline value from storage
    /// @param launchId Identifier of the launch
    /// @return deadline Timestamp when the launch period ends
    function getLaunchDeadline(uint256 launchId) external view returns (uint40 deadline);

    /*//////////////////////////////////////////////////////////////
                         CUSTOM ERRORS
 //////////////////////////////////////////////////////////////*/

    // Launch State Errors
    error LaunchNotFound();              /// @dev Launch ID does not exist
    error AlreadyLaunched();            /// @dev Launch already completed
    error LaunchStillActive();          /// @dev Launch period not ended
    error LaunchSucceeded();            /// @dev Launch met target raise
    error LaunchDeadlinePassed();       /// @dev Launch period expired
    error LaunchBeingFinalized();       /// @dev Launch in finalization
    error LaunchNotCancellable();       /// @dev Cannot cancel launch

    // Validation Errors
    error ImageRequired();              /// @dev Missing token image
    error InvalidTokenParams();         /// @dev Invalid name/symbol
    error TokenNameExists();            /// @dev Name already used
    error TokenSymbolExists();          /// @dev Symbol already used
    error InsufficientLPTokens();       /// @dev Not enough LP tokens
    error PairNotFound();               /// @dev LP Pair does not exist

    // Token Operation Errors
    error TokenApprovalRequired();      /// @dev Missing token approval
    error TokenTransferFailed();        /// @dev Token transfer failed
    error ApprovalFailed();             /// @dev Token approval failed

    // Price Related Errors
    error StalePrice();                 /// @dev Price data too old
    error ExcessivePriceDeviation();    /// @dev Price outside bounds
    error InsufficientPriceHistory();   /// @dev Missing price data
    error PriceOutOfBounds();           /// @dev Price manipulation check

    // Contribution Errors
    error ExcessiveContribution();      /// @dev Exceeds max contribution
    error InsufficientPoolLiquidity();  /// @dev Below min liquidity
    error InsufficientLiquidity();      /// @dev Not enough liquidity
    error ContributionTooSmall();       /// @dev Below min contribution

    // General Errors
    error Unauthorized();               /// @dev Missing permissions
    error ZeroAddress();                /// @dev Invalid zero address
    error InsufficientBalance();        /// @dev Not enough balance
    error NoContributionToRefund();     /// @dev No refund available
    error RefundFailed();               /// @dev Refund transfer failed
    error ContributorTokensOverflow();  /// @dev Uint128 overflow
    error LPTokensOverflow();           /// @dev Uint128 overflow
}
