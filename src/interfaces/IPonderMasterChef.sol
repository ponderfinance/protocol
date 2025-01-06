// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPonderMasterChef {
    /// @notice Struct to track user's position in a pool
    struct UserInfo {
        uint256 amount;           // LP tokens staked
        uint256 rewardDebt;       // Reward debt to handle reward calculations
        uint256 ponderStaked;     // PONDER tokens staked for boost
        uint256 weightedShares;   // User's share weight including boost
    }

    /// @notice Struct to track pool information
    struct PoolInfo {
        address lpToken;           // LP token address
        uint256 allocPoint;        // Pool's share of PONDER emissions
        uint256 lastRewardTime;    // Last time rewards were distributed
        uint256 accPonderPerShare; // Accumulated PONDER per weighted share, times 1e12
        uint256 totalStaked;       // Total LP tokens staked
        uint256 totalWeightedShares; // Total weighted shares (including all boosts)
        uint16 depositFeeBP;       // Deposit fee in basis points
        uint16 boostMultiplier;    // Maximum boost multiplier
    }
    /// @notice Returns the number of pools
    function poolLength() external view returns (uint256);

    /// @notice View function to see pending PONDER rewards
    function pendingPonder(uint256 _pid, address _user) external view returns (uint256);

    /// @notice Add a new LP pool
    function add(uint256 _allocPoint, address _lpToken, uint16 _depositFeeBP, uint16 _boostMultiplier, bool _withUpdate) external;

    /// @notice Update allocation points of a pool
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

    /// @notice Deposit LP tokens to earn PONDER rewards
    function deposit(uint256 _pid, uint256 _amount) external;

    /// @notice Withdraw LP tokens and collect rewards
    function withdraw(uint256 _pid, uint256 _amount) external;

    /// @notice Emergency withdraw LP tokens without caring about rewards
    function emergencyWithdraw(uint256 _pid) external;

    /// @notice Stake PONDER tokens to boost rewards
    function boostStake(uint256 _pid, uint256 _amount) external;

    /// @notice Unstake PONDER tokens used for boost
    function boostUnstake(uint256 _pid, uint256 _amount) external;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event BoostStake(address indexed user, uint256 indexed pid, uint256 amount);
    event BoostUnstake(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event PonderPerSecondUpdated(uint256 newPonderPerSecond);
}
