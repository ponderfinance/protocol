// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { FiveFiveFiveLauncherTypes } from "./types/FiveFiveFiveLauncherTypes.sol";

/// @title IFiveFiveFiveLauncher
/// @author taayyohh
/// @notice Interface for the 555 token launch platform that facilitates token launches with KUB and PONDER
interface IFiveFiveFiveLauncher {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new launch is created
    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);

    /// @notice Emitted when KUB is contributed to a launch
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);

    /// @notice Emitted when PONDER is contributed to a launch
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);

    /// @notice Emitted when tokens are distributed to contributors
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a launch is completed
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);

    /// @notice Emitted when LP tokens are withdrawn by the creator
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 timestamp);

    /// @notice Emitted when PONDER tokens are burned
    event PonderBurned(uint256 indexed launchId, uint256 amount);

    /// @notice Emitted when liquidity pools are created
    event DualPoolsCreated(
        uint256 indexed launchId,
        address memeKubPair,
        address memePonderPair,
        uint256 kubLiquidity,
        uint256 ponderLiquidity
    );

    /// @notice Emitted when PONDER pool creation is skipped
    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);

    /// @notice Emitted when a refund is processed
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);

    /// @notice Emitted when a launch is cancelled
    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new token launch
    function createLaunch(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) external returns (uint256 launchId);

    /// @notice Allows users to contribute KUB to a launch
    function contributeKUB(uint256 launchId) external payable;

    /// @notice Allows users to contribute PONDER to a launch
    function contributePONDER(uint256 launchId, uint256 amount) external;

    /// @notice Allows contributors to claim refunds for failed or cancelled launches
    function claimRefund(uint256 launchId) external;

    /// @notice Allows creator to cancel their launch
    function cancelLaunch(uint256 launchId) external;

    /// @notice Allows creator to withdraw LP tokens after lock period
    function withdrawLP(uint256 launchId) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets contributor information for a specific launch
    function getContributorInfo(uint256 launchId, address contributor) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    );

    /// @notice Gets contribution information for a specific launch
    function getContributionInfo(uint256 launchId) external view returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    );

    /// @notice Gets pool information for a specific launch
    function getPoolInfo(uint256 launchId) external view returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    );

    /// @notice Gets launch information
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
    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    );

    /// @notice Gets remaining amount that can be raised
    function getRemainingToRaise(uint256 launchId) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    );
}
