// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FiveFiveFiveLauncherTypes} from "./types/FiveFiveFiveLauncherTypes.sol";

/// @title IFiveFiveFiveLauncher
/// @notice Interface for the 555 token launch platform that facilitates token launches with KUB and PONDER
interface IFiveFiveFiveLauncher is FiveFiveFiveLauncherTypes {
    /// @notice Emitted when a new launch is created
    /// @param launchId The unique identifier for the launch
    /// @param token The address of the created token
    /// @param creator The address of the launch creator
    /// @param imageURI The URI for the token's image
    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);

    /// @notice Emitted when KUB is contributed to a launch
    /// @param launchId The ID of the launch
    /// @param contributor The address of the contributor
    /// @param amount The amount of KUB contributed
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);

    /// @notice Emitted when PONDER is contributed to a launch
    /// @param launchId The ID of the launch
    /// @param contributor The address of the contributor
    /// @param amount The amount of PONDER contributed
    /// @param kubValue The KUB value of the PONDER contribution
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);

    /// @notice Emitted when tokens are distributed to contributors
    /// @param launchId The ID of the launch
    /// @param recipient The address receiving tokens
    /// @param amount The amount of tokens distributed
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a launch is completed
    /// @param launchId The ID of the launch
    /// @param kubRaised The total amount of KUB raised
    /// @param ponderRaised The total amount of PONDER raised
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);

    /// @notice Emitted when LP tokens are withdrawn by the creator
    /// @param launchId The ID of the launch
    /// @param creator The address of the creator
    /// @param timestamp The timestamp of withdrawal
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 timestamp);

    /// @notice Emitted when PONDER tokens are burned
    /// @param launchId The ID of the launch
    /// @param amount The amount of PONDER burned
    event PonderBurned(uint256 indexed launchId, uint256 amount);

    /// @notice Emitted when liquidity pools are created
    /// @param launchId The ID of the launch
    /// @param memeKubPair The address of the token-KUB pair
    /// @param memePonderPair The address of the token-PONDER pair
    /// @param kubLiquidity The amount of KUB added as liquidity
    /// @param ponderLiquidity The amount of PONDER added as liquidity
    event DualPoolsCreated(
        uint256 indexed launchId,
        address memeKubPair,
        address memePonderPair,
        uint256 kubLiquidity,
        uint256 ponderLiquidity
    );

    /// @notice Emitted when PONDER pool creation is skipped
    /// @param launchId The ID of the launch
    /// @param ponderAmount The amount of PONDER that would have been used
    /// @param ponderValueInKub The KUB value of the PONDER amount
    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);

    /// @notice Emitted when a refund is processed
    /// @param user The address receiving the refund
    /// @param kubAmount The amount of KUB refunded
    /// @param ponderAmount The amount of PONDER refunded
    /// @param tokenAmount The amount of tokens returned
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);

    /// @notice Emitted when a launch is cancelled
    /// @param launchId The ID of the launch
    /// @param creator The address of the creator
    /// @param kubCollected The amount of KUB collected before cancellation
    /// @param ponderCollected The amount of PONDER collected before cancellation
    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );

    /// @notice Creates a new token launch
    /// @param params The launch parameters including name, symbol, and imageURI
    /// @return launchId The unique identifier for the launch
    function createLaunch(LaunchParams calldata params) external returns (uint256 launchId);

    /// @notice Allows users to contribute KUB to a launch
    /// @param launchId The ID of the launch to contribute to
    function contributeKUB(uint256 launchId) external payable;

    /// @notice Allows users to contribute PONDER to a launch
    /// @param launchId The ID of the launch to contribute to
    /// @param amount The amount of PONDER to contribute
    function contributePONDER(uint256 launchId, uint256 amount) external;

    /// @notice Allows contributors to claim refunds for failed or cancelled launches
    /// @param launchId The ID of the launch to claim refund from
    function claimRefund(uint256 launchId) external;

    /// @notice Allows creator to cancel their launch
    /// @param launchId The ID of the launch to cancel
    function cancelLaunch(uint256 launchId) external;

    /// @notice Allows creator to withdraw LP tokens after lock period
    /// @param launchId The ID of the launch to withdraw from
    function withdrawLP(uint256 launchId) external;

    /// @notice Gets contributor information for a specific launch
    /// @param launchId The ID of the launch to query
    /// @param contributor The address of the contributor
    /// @return kubContributed Amount of KUB contributed
    /// @return ponderContributed Amount of PONDER contributed
    /// @return ponderValue KUB value of PONDER contribution
    /// @return tokensReceived Amount of tokens received
    function getContributorInfo(uint256 launchId, address contributor) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    );

    /// @notice Gets contribution information for a specific launch
    /// @param launchId The ID of the launch to query
    /// @return kubCollected Total KUB collected
    /// @return ponderCollected Total PONDER collected
    /// @return ponderValueCollected KUB value of PONDER collected
    /// @return totalValue Total value collected in KUB terms
    function getContributionInfo(uint256 launchId) external view returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    );

    /// @notice Gets pool information for a specific launch
    /// @param launchId The ID of the launch to query
    /// @return memeKubPair Address of the token-KUB pair
    /// @return memePonderPair Address of the token-PONDER pair
    /// @return hasSecondaryPool Whether a PONDER pool exists
    function getPoolInfo(uint256 launchId) external view returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    );

    /// @notice Gets launch information
    /// @param launchId The ID of the launch to query
    /// @return tokenAddress The address of the launched token
    /// @return name The name of the token
    /// @return symbol The symbol of the token
    /// @return imageURI The URI of the token's image
    /// @return kubRaised The amount of KUB raised
    /// @return launched Whether the launch has been completed
    /// @return lpUnlockTime The timestamp when LP tokens can be withdrawn
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
    /// @return minPoolLiquidity Minimum pool liquidity required
    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    );

    /// @notice Gets remaining amount that can be raised
    /// @param launchId The ID of the launch to query
    /// @return remainingTotal Total remaining amount that can be raised
    /// @return remainingPonderValue Remaining amount that can be raised in PONDER
    function getRemainingToRaise(uint256 launchId) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    );
}
