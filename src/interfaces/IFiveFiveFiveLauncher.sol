// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IFiveFiveFiveLauncher
/// @notice Interface for the 555 token launch platform
interface IFiveFiveFiveLauncher {
    /// @notice Emitted when a new launch is created
    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);
    /// @notice Emitted when a contribution is made
    event Contributed(uint256 indexed launchId, address indexed contributor, uint256 amount);
    /// @notice Emitted when a contribution is made
    event PonderBurned(uint256 indexed launchId, uint256 burnAmount);
    /// @notice Emitted when a contribution is made
    event PonderContributed(uint256 indexed launchId, address indexed contributor, uint256 amount);
    /// @notice Emitted when a launch is finalized
    event LaunchFinalized(uint256 indexed launchId, uint256 lpAmount, uint256 creatorFee, uint256 protocolFee);
    /// @notice Emitted when LP tokens are withdrawn
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 amount);
    /// @notice Emitted when transfers are enabled for a token
    event TransfersEnabled(uint256 indexed launchId, address indexed tokenAddress);
    /// @notice Emitted when tokens are minted
    event TokenMinted(uint256 indexed launchId, address indexed tokenAddress, uint256 amount);
    /// @notice Emitted when liquidity is added
    event LiquidityAdded(uint256 indexed launchId, uint256 ethAmount, uint256 tokenAmount);
    /// @notice Emitted when a launch is completed
    event LaunchCompleted(uint256 indexed launchId, uint256 totalRaised, uint256 totalSold);
    /// @notice Emitted when protocol fee is paid
    event ProtocolFeePaid(uint256 indexed launchId, uint256 amount);
    /// @notice Emitted when creator fee is paid
    event CreatorFeePaid(uint256 indexed launchId, address indexed creator, uint256 amount);
    /// @notice Emitted when tokens are purchased
    event TokenPurchased(uint256 indexed launchId, address indexed buyer, uint256 ponderAmount, uint256 tokenAmount);

    /// @notice Creates a new token launch
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param imageURI URI for token image
    /// @return launchId Unique identifier for the launch
    function createLaunch(
        string memory name,
        string memory symbol,
        string memory imageURI
    ) external returns (uint256 launchId);

    /// @notice Allows users to contribute PONDER to a launch
    /// @param launchId The ID of the launch to contribute to
    /// @param amount The amount of ponder to contribute
    function contribute(uint256 launchId, uint256 amount) external;

    /// @notice Allows creator to withdraw LP tokens after lock period
    /// @param launchId The ID of the launch to withdraw from
    function withdrawLP(uint256 launchId) external;

    /// @notice Gets all information about a specific launch
    /// @param launchId The ID of the launch to query
    /// @return tokenAddress The address of the launched token
    /// @return name The name of the token
    /// @return symbol The symbol of the token
    /// @return imageURI The URI of the token's image
    /// @return totalRaised The total amount raised
    /// @return launched Whether the launch has been completed
    /// @return lpUnlockTime The timestamp when LP tokens can be withdrawn
    function getLaunchInfo(uint256 launchId) external view returns (
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageURI,
        uint256 totalRaised,
        bool launched,
        uint256 lpUnlockTime
    );
}
