// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IPonderMasterChef
 * @notice Interface for the PonderMasterChef staking and farming contract
 * @dev Defines all external functions and events for the MasterChef system
 */
interface IPonderMasterChef {
    /**
     * @notice Returns the number of pools in the system
     * @return Number of registered staking pools
     */
    function poolLength() external view returns (uint256);

    /**
     * @notice Calculate pending PONDER rewards for a user in a pool
     * @param _pid Pool ID to check
     * @param _user Address of the user
     * @return Amount of PONDER tokens pending as rewards
     */
    function pendingPonder(uint256 _pid, address _user) external view returns (uint256);

    /**
     * @notice Add a new LP token pool
     * @param _allocPoint Allocation points assigned to the pool
     * @param _lpToken LP token contract address
     * @param _depositFeeBP Deposit fee in basis points
     * @param _boostMultiplier Maximum boost multiplier for the pool
     */
    function add(
        uint256 _allocPoint,
        address _lpToken,
        uint16 _depositFeeBP,
        uint16 _boostMultiplier
    ) external;

    /**
     * @notice Update allocation points of an existing pool
     * @param _pid Pool ID to update
     * @param _allocPoint New allocation points for the pool
     * @param _withUpdate Whether to update all pools
     */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    /**
     * @notice Stake LP tokens in a pool
     * @param _pid Pool ID to stake in
     * @param _amount Amount of LP tokens to stake
     */
    function deposit(uint256 _pid, uint256 _amount) external;

    /**
     * @notice Withdraw LP tokens from a pool
     * @param _pid Pool ID to withdraw from
     * @param _amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 _pid, uint256 _amount) external;

    /**
     * @notice Emergency withdraw LP tokens without caring about rewards
     * @param _pid Pool ID to withdraw from
     */
    function emergencyWithdraw(uint256 _pid) external;

    /**
     * @notice Stake PONDER tokens to boost rewards in a pool
     * @param _pid Pool ID to boost
     * @param _amount Amount of PONDER to stake for boost
     */
    function boostStake(uint256 _pid, uint256 _amount) external;

    /**
     * @notice Unstake PONDER tokens used for boost
     * @param _pid Pool ID to remove boost from
     * @param _amount Amount of PONDER to unstake
     */
    function boostUnstake(uint256 _pid, uint256 _amount) external;

    /**
    * @notice Update reward variables of the given pool
     * @param _pid Pool ID to update
     */
    function updatePool(uint256 _pid) external;

    // Utility View Functions

    /**
     * @notice Preview boost multiplier for given stake amounts
     * @param _pid Pool ID to check
     * @param ponderStaked Amount of PONDER to stake
     * @param lpAmount Amount of LP tokens staked
     * @return Expected boost multiplier
     */
    function previewBoostMultiplier(
        uint256 _pid,
        uint256 ponderStaked,
        uint256 lpAmount
    ) external view returns (uint256);

    /**
     * @notice Calculate required PONDER stake for desired boost
     * @param lpAmount Amount of LP tokens staked
     * @param targetMultiplier Desired boost multiplier
     * @return Amount of PONDER tokens needed
     */
    function getRequiredPonderForBoost(
        uint256 lpAmount,
        uint256 targetMultiplier
    ) external pure returns (uint256);

    // Admin Functions

    /**
     * @notice Update team reserve address that receives fees
     * @param _teamReserve New team reserve address
     */
    function setTeamReserve(address _teamReserve) external;

    /**
     * @notice Update PONDER emission rate
     * @param _ponderPerSecond New PONDER tokens per second
     */
    function setPonderPerSecond(uint256 _ponderPerSecond) external;

    /**
   * @notice Base points for percentage calculations (100% = 10000)
     */
    function basisPoints() external pure returns (uint256);

    /**
     * @notice Base multiplier for boost calculations (1x = 10000)
     */
    function baseMultiplier() external pure returns (uint256);

    /**
     * @notice Minimum boost multiplier (2x = 20000)
     */
    function minBoostMultiplier() external pure returns (uint256);

    /**
     * @notice Required PONDER stake relative to LP value (10%)
     */
    function boostThresholdPercent() external pure returns (uint256);

    /**
     * @notice Maximum additional boost percentage (100%)
     */
    function maxExtraBoostPercent() external pure returns (uint256);

    /**
     * @notice Maximum allocation points per pool
     */
    function maxAllocPoint() external pure returns (uint256);

    /**
     * @notice Get user information for a specific pool
     * @param _pid Pool ID to query
     * @param _user Address of the user
     * @return amount Amount of LP tokens staked
     * @return rewardDebt User's reward debt
     * @return ponderStaked Amount of PONDER staked for boost
     * @return weightedShares User's boosted share amount
     */
    function userInfo(uint256 _pid, address _user) external view returns (
        uint256 amount,
        uint256 rewardDebt,
        uint256 ponderStaked,
        uint256 weightedShares
    );

    /**
     * @notice Get the current team reserve address
     * @return Address that receives deposit fees
     */
    function teamReserve() external view returns (address);

    /**
     * @notice Get the current PONDER emission rate
     * @return Tokens emitted per second
     */
    function ponderPerSecond() external view returns (uint256);

    /**
     * @notice Get the total allocation points across all pools
     * @return Sum of all pool allocation points
     */
    function totalAllocPoint() external view returns (uint256);

    /**
     * @notice Get the owner address
     * @return Address of the contract owner
     */
    function owner() external view returns (address);

    /**
     * @notice Get the start time of farming
     * @return Timestamp when farming started
     */
    function startTime() external view returns (uint256);

    /**
     * @notice Check if farming has started
     * @return True if farming has been initialized
     */
    function farmingStarted() external view returns (bool);

    // Events

    /**
     * @notice Emitted when tokens are deposited
     * @param user Address of the depositor
     * @param pid ID of the pool
     * @param amount Amount of tokens deposited
     */
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Emitted when tokens are withdrawn
     * @param user Address of the withdrawer
     * @param pid ID of the pool
     * @param amount Amount of tokens withdrawn
     */
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Emitted during emergency withdrawal
     * @param user Address of the withdrawer
     * @param pid ID of the pool
     * @param amount Amount of tokens withdrawn
     */
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Emitted when PONDER is staked for boost
     * @param user Address of the staker
     * @param pid ID of the pool
     * @param amount Amount of PONDER staked
     */
    event BoostStake(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Emitted when PONDER boost stake is withdrawn
     * @param user Address of the withdrawer
     * @param pid ID of the pool
     * @param amount Amount of PONDER withdrawn
     */
    event BoostUnstake(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Emitted when a new pool is added
     * @param pid ID of the new pool
     * @param lpToken Address of the LP token
     * @param allocPoint Allocation points assigned
     */
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);

    /**
     * @notice Emitted when a pool's allocation points are updated
     * @param pid ID of the updated pool
     * @param allocPoint New allocation points
     */
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);

    /**
     * @notice Emitted when team reserve address is updated
     * @param oldTeamReserve Previous team reserve address
     * @param newTeamReserve New team reserve address
     */
    event TeamReserveUpdated(address indexed oldTeamReserve, address indexed newTeamReserve);

    /**
     * @notice Emitted when PONDER per second rate is updated
     * @param newPonderPerSecond New tokens per second
     */
    event PonderPerSecondUpdated(uint256 newPonderPerSecond);

    /**
     * @notice Emitted when a user's weighted shares are updated
     * @param pid ID of the pool
     * @param user Address of the user
     * @param newShares New weighted shares amount
     * @param totalShares New total shares in pool
     */
    event WeightedSharesUpdated(
        uint256 indexed pid,
        address indexed user,
        uint256 newShares,
        uint256 totalShares
    );

    /**
     * @notice Emitted when a pool's total weighted shares changes
     * @param pid ID of the pool
     * @param totalWeightedShares New total weighted shares
     */
    event PoolWeightedSharesUpdated(uint256 indexed pid, uint256 totalWeightedShares);
}
