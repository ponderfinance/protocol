// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER MASTERCHEF INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderMasterChef
/// @author taayyohh
/// @notice Interface for Ponder protocol's farming rewards system
/// @dev Defines the external interface for the MasterChef contract including all functions and events
interface IPonderMasterChef {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total number of registered farming pools
    /// @dev Used to iterate over pools or validate pool IDs
    /// @return Number of pools currently in the system
    function poolLength() external view returns (uint256);

    /// @notice Calculate user's unclaimed rewards
    /// @dev Calculates pending PONDER tokens for a given user in a specific pool
    /// @param _pid Pool ID to check rewards for
    /// @param _user Address of the user to check
    /// @return Unclaimed PONDER tokens available to harvest
    function pendingPonder(uint256 _pid, address _user) external view returns (uint256);

    /// @notice Get pool information
    /// @dev Returns all data for a farm pool
    /// @param _pid Pool ID to query
    /// @return lpToken Address of LP token
    /// @return allocPoint Pool's share of PONDER emissions
    /// @return lastRewardTime Last reward distribution timestamp
    /// @return accPonderPerShare Accumulated PONDER per share, scaled by 1e12
    /// @return totalStaked Total LP tokens staked
    /// @return totalWeightedShares Total boosted share amount
    /// @return depositFeeBP Deposit fee in basis points (1 BP = 0.01%)
    /// @return boostMultiplier Maximum boost multiplier for this pool
    function poolInfo(uint256 _pid) external view returns (
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardTime,
        uint256 accPonderPerShare,
        uint256 totalStaked,
        uint256 totalWeightedShares,
        uint16 depositFeeBP,
        uint16 boostMultiplier
    );


    /*//////////////////////////////////////////////////////////////
                        POOL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new farming pool
    /// @dev Adds new LP token pool with specified parameters
    /// @param _allocPoint Pool's share of PONDER emissions
    /// @param _lpToken Address of LP token to stake
    /// @param _depositFeeBP Deposit fee in basis points (1 BP = 0.01%)
    /// @param _boostMultiplier Maximum boost multiplier allowed for this pool
    function add(
        uint256 _allocPoint,
        address _lpToken,
        uint16 _depositFeeBP,
        uint16 _boostMultiplier
    ) external;

    /// @notice Modify pool allocation
    /// @dev Updates a pool's share of PONDER emissions
    /// @param _pid Pool ID to modify
    /// @param _allocPoint New allocation point value
    /// @param _withUpdate Whether to update all pools
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    /*//////////////////////////////////////////////////////////////
                        USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stake LP tokens
    /// @dev Deposits LP tokens into specified farming pool
    /// @param _pid Pool ID to stake in
    /// @param _amount Amount of LP tokens to stake
    function deposit(uint256 _pid, uint256 _amount) external;

    /// @notice Withdraw LP tokens
    /// @dev Removes LP tokens from specified farming pool
    /// @param _pid Pool ID to withdraw from
    /// @param _amount Amount of LP tokens to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external;

    /// @notice Emergency withdrawal
    /// @dev Allows withdrawal without reward collection
    /// @param _pid Pool ID to withdraw from
    function emergencyWithdraw(uint256 _pid) external;

    /*//////////////////////////////////////////////////////////////
                        BOOST MECHANICS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stake PONDER for boost
    /// @dev Locks PONDER tokens to increase farming multiplier
    /// @param _pid Pool ID to boost
    /// @param _amount Amount of PONDER to stake
    function boostStake(uint256 _pid, uint256 _amount) external;

    /// @notice Remove PONDER boost
    /// @dev Withdraws PONDER tokens used for boost
    /// @param _pid Pool ID to remove boost from
    /// @param _amount Amount of PONDER to unstake
    function boostUnstake(uint256 _pid, uint256 _amount) external;

    /// @notice Update pool rewards
    /// @dev Updates reward variables for specified pool
    /// @param _pid Pool ID to update
    function updatePool(uint256 _pid) external;

    /*//////////////////////////////////////////////////////////////
                        BOOST CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate potential boost multiplier
    /// @dev Preview boost multiplier for given stake amounts
    /// @param _pid Pool ID to calculate for
    /// @param ponderStaked Amount of PONDER to stake
    /// @param lpAmount Amount of LP tokens staked
    /// @return Expected boost multiplier scaled by BASE_MULTIPLIER
    function previewBoostMultiplier(
        uint256 _pid,
        uint256 ponderStaked,
        uint256 lpAmount
    ) external view returns (uint256);

    /// @notice Calculate required PONDER for boost
    /// @dev Determines PONDER needed for desired multiplier
    /// @param lpAmount Amount of LP tokens staked
    /// @param targetMultiplier Desired boost multiplier
    /// @return Amount of PONDER tokens needed
    function getRequiredPonderForBoost(
        uint256 lpAmount,
        uint256 targetMultiplier
    ) external pure returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update fee recipient
    /// @dev Sets new address for collecting deposit fees
    /// @param _teamReserve New fee collector address
    function setTeamReserve(address _teamReserve) external;

    /// @notice Modify emission rate
    /// @dev Updates PONDER tokens distributed per second
    /// @param _ponderPerSecond New emission rate
    function setPonderPerSecond(uint256 _ponderPerSecond) external;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get basis points constant
    /// @dev 100% = 10000 basis points
    function basisPoints() external pure returns (uint256);

    /// @notice Get base multiplier
    /// @dev 1x = 10000
    function baseMultiplier() external pure returns (uint256);

    /// @notice Get minimum boost multiplier
    /// @dev 2x = 20000
    function minBoostMultiplier() external pure returns (uint256);

    /// @notice Get boost threshold
    /// @dev 10% = 1000 basis points
    function boostThresholdPercent() external pure returns (uint256);

    /// @notice Get maximum boost
    /// @dev 100% = 10000 basis points
    function maxExtraBoostPercent() external pure returns (uint256);

    /// @notice Get maximum allocation
    /// @dev Prevents pool manipulation
    function maxAllocPoint() external pure returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        STATE GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get user's pool position
    /// @dev Retrieves all staking information for a user
    /// @param _pid Pool ID to query
    /// @param _user Address of the user
    /// @return amount LP tokens staked
    /// @return rewardDebt Reward debt for calculations
    /// @return ponderStaked PONDER staked for boost
    /// @return weightedShares Boosted share amount
    function userInfo(uint256 _pid, address _user) external view returns (
        uint256 amount,
        uint256 rewardDebt,
        uint256 ponderStaked,
        uint256 weightedShares
    );

    /// @notice Get fee collector
    /// @dev Returns current team reserve address
    function teamReserve() external view returns (address);

    /// @notice Get emission rate
    /// @dev Returns current PONDER per second
    function ponderPerSecond() external view returns (uint256);

    /// @notice Get total allocation
    /// @dev Returns sum of all pool weights
    function totalAllocPoint() external view returns (uint256);

    /// @notice Get contract owner
    /// @dev Returns current admin address
    function owner() external view returns (address);

    /// @notice Get start timestamp
    /// @dev Returns farming activation time
    function startTime() external view returns (uint256);

    /// @notice Get activation status
    /// @dev Returns if farming has started
    function farmingStarted() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice LP token deposit
    /// @param user Depositor address
    /// @param pid Pool receiving deposit
    /// @param amount Tokens deposited
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice LP token withdrawal
    /// @param user Withdrawer address
    /// @param pid Pool withdrawn from
    /// @param amount Tokens withdrawn
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice Emergency LP withdrawal
    /// @param user Withdrawer address
    /// @param pid Pool withdrawn from
    /// @param amount Tokens withdrawn
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice PONDER boost stake
    /// @param user Staker address
    /// @param pid Pool being boosted
    /// @param amount PONDER staked
    event BoostStake(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice PONDER boost unstake
    /// @param user Unstaker address
    /// @param pid Pool boost removed from
    /// @param amount PONDER unstaked
    event BoostUnstake(address indexed user, uint256 indexed pid, uint256 amount);

    /// @notice New pool creation
    /// @param pid Pool identifier
    /// @param lpToken LP token address
    /// @param allocPoint Reward allocation
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);

    /// @notice Pool allocation update
    /// @param pid Pool identifier
    /// @param allocPoint New allocation
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);

    /// @notice Fee collector update
    /// @param oldTeamReserve Previous collector
    /// @param newTeamReserve New collector
    event TeamReserveUpdated(address indexed oldTeamReserve, address indexed newTeamReserve);

    /// @notice Emission rate update
    /// @param newPonderPerSecond New rate
    event PonderPerSecondUpdated(uint256 newPonderPerSecond);

    /// @notice User boost shares update
    /// @param pid Pool identifier
    /// @param user User address
    /// @param newShares Updated shares
    /// @param totalShares Pool total shares
    event WeightedSharesUpdated(
        uint256 indexed pid,
        address indexed user,
        uint256 newShares,
        uint256 totalShares
    );

    /// @notice Pool total shares update
    /// @param pid Pool identifier
    /// @param totalWeightedShares New total
    event PoolWeightedSharesUpdated(uint256 indexed pid, uint256 totalWeightedShares);

    /// @notice Ownership transfer initiated
    /// @param previousOwner Current owner
    /// @param newOwner Pending owner
    event OwnershipTransferInitiated(address indexed previousOwner, address indexed newOwner);

    /// @notice Ownership transfer completed
    /// @param previousOwner Previous owner
    /// @param newOwner New owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}
