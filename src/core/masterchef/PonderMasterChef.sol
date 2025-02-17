// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IPonderMasterChef } from "./IPonderMasterChef.sol";
import { PonderMasterChefStorage } from "./storage/PonderMasterChefStorage.sol";
import { PonderMasterChefTypes } from "./types/PonderMasterChefTypes.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PonderToken } from "../token/PonderToken.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER MASTERCHEF CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title PonderMasterChef
/// @author taayyohh
/// @notice Implementation of Ponder protocol's farming rewards system
/// @dev Manages LP token staking, PONDER emissions, and boost mechanics
contract PonderMasterChef is IPonderMasterChef, PonderMasterChefStorage, ReentrancyGuard {
    using PonderMasterChefTypes for *;


    /*//////////////////////////////////////////////////////////////
                        IMMUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The PONDER token contract
    /// @dev Immutable reference to the PONDER token for rewards
    PonderToken public immutable PONDER;

    /// @notice Factory contract for validating LP tokens
    /// @dev Immutable reference to verify LP tokens are from our protocol
    IPonderFactory public immutable FACTORY;


    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the MasterChef contract
    /// @dev Sets up initial protocol parameters and ownership
    /// @param _ponder PONDER token contract address
    /// @param _factory Factory contract for LP token validation
    /// @param _teamReserve_ Address to receive deposit fees
    /// @param _ponderPerSecond_ Initial PONDER tokens per second
    constructor(
        PonderToken _ponder,
        IPonderFactory _factory,
        address _teamReserve_,
        uint256 _ponderPerSecond_
    ) {
        if (_teamReserve_ == address(0)) revert IPonderMasterChef.ZeroAddress();
        PONDER = _ponder;
        FACTORY = _factory;
        _teamReserve = _teamReserve_;
        _ponderPerSecond = _ponderPerSecond_;
        _owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                     ACCESS CONTROL
     //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to the contract owner
    /// @dev Reverts if caller is not the owner
    modifier onlyOwner {
        if (msg.sender != _owner) revert IPonderMasterChef.Forbidden();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    STATE VARIABLE GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get basis points constant
    /// @dev 100% = 10000 basis points
    /// @return Basis points denominator for percentage calculation
    function basisPoints() external pure returns (uint256) {
        return PonderMasterChefTypes.BASIS_POINTS;
    }

    /// @notice Get base multiplier
    /// @dev 1x = 10000
    /// @return Base value for boost multiplier calculations
    function baseMultiplier() external pure returns (uint256) {
        return PonderMasterChefTypes.BASE_MULTIPLIER;
    }

    /// @notice Get minimum boost multiplier
    /// @dev 2x = 20000
    /// @return Minimum boost multiplier allowed
    function minBoostMultiplier() external pure returns (uint256) {
        return PonderMasterChefTypes.MIN_BOOST_MULTIPLIER;
    }

    /// @notice Get boost threshold percentage
    /// @dev 10% = 1000 basis points
    /// @return Required PONDER/LP ratio for boost
    function boostThresholdPercent() external pure returns (uint256) {
        return PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT;
    }

    /// @notice Get maximum extra boost
    /// @dev 100% = 10000 basis points
    /// @return Maximum additional boost percentage
    function maxExtraBoostPercent() external pure returns (uint256) {
        return PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT;
    }

    /// @notice Get maximum allocation points
    /// @dev Prevents pool manipulation
    /// @return Maximum allocation points per pool
    function maxAllocPoint() external pure returns (uint256) {
        return PonderMasterChefTypes.MAX_ALLOC_POINT;
    }

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
    ) {
        PonderMasterChefTypes.UserInfo storage info = _userInfo[_pid][_user];
        return (info.amount, info.rewardDebt, info.ponderStaked, info.weightedShares);
    }

    /// @notice Get fee collector
    /// @dev Returns current team reserve address
    /// @return Address receiving deposit fees
    function teamReserve() external view returns (address) {
        return _teamReserve;
    }

    /// @notice Get emission rate
    /// @dev Returns current PONDER per second
    /// @return PONDER tokens emitted per second
    function ponderPerSecond() external view returns (uint256) {
        return _ponderPerSecond;
    }

    /// @notice Get total allocation
    /// @dev Returns sum of all pool weights
    /// @return Total allocation points across pools
    function totalAllocPoint() external view returns (uint256) {
        return _totalAllocPoint;
    }

    /// @notice Get contract owner
    /// @dev Returns current admin address
    /// @return Address of contract owner
    function owner() external view returns (address) {
        return _owner;
    }

    /// @notice Get start timestamp
    /// @dev Returns farming activation time
    /// @return Unix timestamp when farming started
    function startTime() external view returns (uint256) {
        return _startTime;
    }

    /// @notice Get activation status
    /// @dev Returns if farming has started
    /// @return True if farming is active
    function farmingStarted() external view returns (bool) {
        return _farmingStarted;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get total number of registered farming pools
    /// @dev Used to iterate over pools or validate pool IDs
    /// @return Number of pools currently in the system
    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }

    /// @notice Calculate user's unclaimed rewards
    /// @dev Calculates pending PONDER tokens for a given user in a specific pool
    /// @dev Uses checked math and preserves precision by:
    ///      1. Doing multiplications before divisions
    ///      2. Using intermediate variables to prevent overflow
    ///      3. Applying scale factors optimally
    /// @param _pid Pool ID to check rewards for
    /// @param _user Address of the user to check
    /// @return pending Amount of unclaimed PONDER tokens available
    function pendingPonder(uint256 _pid, address _user) external view returns (uint256 pending) {
        // CHECKS
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();

        // Load storage pointers
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][_user];

        // Get current accumulated PONDER per share
        uint256 accPonderPerShare = pool.accPonderPerShare;
        uint256 lpSupply = pool.totalWeightedShares;

        // Calculate new rewards if time has passed and pool has stakes
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0 && _farmingStarted) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;

            // Calculate intermediate values to prevent overflow
            // First calculate (timeElapsed * _ponderPerSecond) to get total PONDER emission
            uint256 totalEmission;
            unchecked {
            // This multiplication is safe as timeElapsed is bounded by block times
            // and _ponderPerSecond is admin-controlled
                totalEmission = timeElapsed * _ponderPerSecond;
            }

            // Then calculate pool's share while preserving precision
            uint256 poolReward;
            if (totalEmission > type(uint256).max / pool.allocPoint) {
                // If multiplication would overflow, divide first
                poolReward = totalEmission / _totalAllocPoint * pool.allocPoint;
            } else {
                // Otherwise multiply first for better precision
                poolReward = (totalEmission * pool.allocPoint) / _totalAllocPoint;
            }

            // Check against remaining supply before scaling
            uint256 remainingSupply = PONDER.maximumSupply() - PONDER.totalSupply();
            if (poolReward > remainingSupply) {
                poolReward = remainingSupply;
            }

            // Scale by 1e12 while checking for overflow
            uint256 scaledReward;
            if (poolReward > type(uint256).max / 1e12) {
                // If scaling would overflow, divide lpSupply first
                scaledReward = poolReward / lpSupply * 1e12;
            } else {
                // Otherwise multiply by 1e12 first for better precision
                scaledReward = (poolReward * 1e12) / lpSupply;
            }

            // Update accumulated PONDER per share
            // Use unchecked for gas optimization as we know it won't overflow
            // due to previous checks
            unchecked {
                accPonderPerShare = accPonderPerShare + scaledReward;
            }
        }

        // Calculate pending rewards with safe math
        if (user.weightedShares > 0) {
            // First multiply to preserve precision
            uint256 rewardDebt = user.rewardDebt;
            uint256 totalReward;

            if (user.weightedShares > type(uint256).max / accPonderPerShare) {
                // If multiplication would overflow, divide first
                totalReward = user.weightedShares / 1e12 * accPonderPerShare;
            } else {
                // Otherwise multiply first for better precision
                totalReward = (user.weightedShares * accPonderPerShare) / 1e12;
            }

            // Ensure totalReward >= rewardDebt to prevent underflow
            pending = totalReward >= rewardDebt ? totalReward - rewardDebt : 0;
        } else {
            pending = 0;
        }

        // Final supply check
        uint256 remainingSupply = PONDER.maximumSupply() - PONDER.totalSupply();
        if (pending > remainingSupply) {
            pending = remainingSupply;
        }
    }

    /// @notice Calculate required PONDER stake for desired boost
    /// @dev Pure function to compute PONDER needed for target multiplier
    /// @param lpAmount Amount of LP tokens staked
    /// @param targetMultiplier Desired boost multiplier
    /// @return Amount of PONDER tokens needed for boost
    function getRequiredPonderForBoost(
        uint256 lpAmount,
        uint256 targetMultiplier
    ) public pure returns (uint256) {
        if (targetMultiplier <= PonderMasterChefTypes.BASE_MULTIPLIER) {
            return 0;
        }
        if (targetMultiplier < PonderMasterChefTypes.MIN_BOOST_MULTIPLIER) {
            return (lpAmount * PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT) / PonderMasterChefTypes.BASIS_POINTS;
        }

        uint256 extraBoost = targetMultiplier - PonderMasterChefTypes.MIN_BOOST_MULTIPLIER;

        // Perform all multiplications first, then single division at end to minimize precision loss
        uint256 numerator =
            lpAmount *
            PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT *
            (PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT + extraBoost);

        uint256 denominator = PonderMasterChefTypes.BASIS_POINTS * PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT;

        return numerator / denominator;
    }

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
    ) {
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        return (
            pool.lpToken,
            pool.allocPoint,
            pool.lastRewardTime,
            pool.accPonderPerShare,
            pool.totalStaked,
            pool.totalWeightedShares,
            pool.depositFeeBP,
            pool.boostMultiplier
        );
    }


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
    ) external view returns (uint256) {
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        return _calculateBoostMultiplier(
            ponderStaked,
            lpAmount,
            _poolInfo[_pid].boostMultiplier
        );
    }

    /*//////////////////////////////////////////////////////////////
                    POOL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new farming pool
    /// @dev Adds new LP token pool with specified parameters
    /// @dev Validates LP token and prevents duplicate pools
    /// @param _allocPoint Pool's share of PONDER emissions
    /// @param _lpToken Address of LP token to stake
    /// @param _depositFeeBP Deposit fee in basis points (1 BP = 0.01%)
    /// @param _boostMultiplier Maximum boost multiplier allowed for this pool
    function add(
        uint256 _allocPoint,
        address _lpToken,
        uint16 _depositFeeBP,
        uint16 _boostMultiplier
    ) external onlyOwner {
        // Checks
        if (_lpToken == address(0)) revert IPonderMasterChef.ZeroAddress();
        if (_allocPoint > PonderMasterChefTypes.MAX_ALLOC_POINT)  {
            revert IPonderMasterChef.ExcessiveAllocation();
        }
        if (_depositFeeBP > 1000) revert IPonderMasterChef.ExcessiveDepositFee();
        if (_boostMultiplier < PonderMasterChefTypes.MIN_BOOST_MULTIPLIER) {
            revert IPonderMasterChef.InvalidBoostMultiplier();
        }
        if (_boostMultiplier > 50000) revert IPonderMasterChef.InvalidBoostMultiplier();

        // Check for duplicate pools
        uint256 length = _poolInfo.length;
        for (uint256 pid; pid < length; ++pid) {
            if (_poolInfo[pid].lpToken == _lpToken) revert IPonderMasterChef.DuplicatePool();
        }

        // Validate LP token is from our factory
        address token0 = IPonderPair(_lpToken).token0();
        address token1 = IPonderPair(_lpToken).token1();
        if (FACTORY.getPair(token0, token1) != _lpToken) revert IPonderMasterChef.InvalidPair();

        // Update pools first before changing allocation points to ensure proper reward distribution
        _massUpdatePools();

        // Calculate last reward time
        uint256 lastRewardTime = _farmingStarted ? block.timestamp : 0;

        // Effects
        _poolInfo.push(PonderMasterChefTypes.PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accPonderPerShare: 0,
            totalStaked: 0,
            totalWeightedShares: 0,
            depositFeeBP: _depositFeeBP,
            boostMultiplier: _boostMultiplier
        }));

        // Update total allocation points after adding pool
        _totalAllocPoint += _allocPoint;

        emit PoolAdded(_poolInfo.length - 1, _lpToken, _allocPoint);
    }

    /// @notice Modify pool allocation
    /// @dev Updates a pool's share of PONDER emissions
    /// @param _pid Pool ID to modify
    /// @param _allocPoint New allocation point value
    /// @param _withUpdate Whether to update all pools
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();

        // Effects: Update state variables before external calls
        _totalAllocPoint = _totalAllocPoint - _poolInfo[_pid].allocPoint + _allocPoint;
        _poolInfo[_pid].allocPoint = _allocPoint;

        // Interactions: External calls last
        if (_withUpdate) {
            _massUpdatePools();
        }

        emit PoolUpdated(_pid, _allocPoint);
    }

    /*//////////////////////////////////////////////////////////////
                    POOL UPDATES
    //////////////////////////////////////////////////////////////*/

    /// @notice Update reward variables for all pools
    /// @dev Be careful of gas spending!
    function _massUpdatePools() internal {
        uint256 length = _poolInfo.length;
        for (uint256 pid; pid < length; ++pid) {
            _updatePool(pid);
        }
    }


    /// @notice Update reward variables of the given pool
    /// @dev External wrapper for _updatePool
    /// @param _pid Pool ID to update
    function updatePool(uint256 _pid) external {
        _updatePool(_pid);
    }

    /// @notice Internal pool update logic
    /// @dev Updates reward variables and mints PONDER rewards
    /// @param _pid Pool ID to update
    function _updatePool(uint256 _pid) internal {
        // CHECKS
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        if (!_farmingStarted) return;

        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) return;
        if (pool.totalWeightedShares == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        // Calculate all values before state changes
        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 ponderBalance = PONDER.balanceOf(address(this));
        uint256 ponderReward = (timeElapsed * _ponderPerSecond * pool.allocPoint) / _totalAllocPoint;
        if (ponderReward > ponderBalance) {
            ponderReward = ponderBalance;
        }

        uint256 rewardShare = (timeElapsed * _ponderPerSecond * pool.allocPoint * 1e12)
            / (_totalAllocPoint * pool.totalWeightedShares);

        // EFFECTS
        pool.accPonderPerShare += rewardShare;
        pool.lastRewardTime = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                    USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stake LP tokens
    /// @dev Deposits LP tokens into specified farming pool
    /// @dev Handles deposit fees and boost calculations
    /// @param _pid Pool ID to stake in
    /// @param _amount Amount of LP tokens to stake
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        // CHECKS
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        // Calculate initial state
        uint256 pending = user.amount > 0
            ? (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt
            : 0;

        // Record balances before transfer
        uint256 beforeBalance = IERC20(pool.lpToken).balanceOf(address(this));

        // EFFECTS - Update all state before transfers
        if (_amount > 0 && !_farmingStarted) {
            _startTime = block.timestamp;
            _farmingStarted = true;
        }

        _updatePool(_pid);

        // Calculate deposit fee
        (uint256 depositFee, uint256 actualAmount) = _calculateDepositFee(_amount, pool.depositFeeBP);

        if (actualAmount > 0) {
            // Update state
            user.amount += actualAmount;
            pool.totalStaked += actualAmount;
            _updateUserWeightedShares(_pid, msg.sender);
        }

        // Update reward debt
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        // INTERACTIONS - External calls last
        if (_amount > 0) {
            // Transfer LP tokens
            if (!IERC20(pool.lpToken).transferFrom(msg.sender, address(this), _amount)) {
                revert IPonderMasterChef.TransferFailed();
            }

            // Verify received amount
            uint256 afterBalance = IERC20(pool.lpToken).balanceOf(address(this));
            uint256 receivedAmount = afterBalance - beforeBalance;
            if (receivedAmount == 0) revert IPonderMasterChef.NoTokensTransferred();
            if (receivedAmount != _amount) revert IPonderMasterChef.InvalidAmount();

            // Handle deposit fee
            if (depositFee > 0) {
                if (!IERC20(pool.lpToken).transfer(_teamReserve, depositFee)) {
                    revert IPonderMasterChef.TransferFailed();
                }
            }
        }

        // Handle pending rewards last
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw LP tokens
    /// @dev Removes LP tokens from specified farming pool
    /// @dev Updates boost and handles pending rewards
    /// @param _pid Pool ID to withdraw from
    /// @param _amount Amount of LP tokens to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        // CHECKS
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];
        if (user.amount < _amount) revert IPonderMasterChef.InsufficientAmount();

        // Calculate pending rewards before any state changes
        uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;

        // EFFECTS - Update pool state first
        _updatePool(_pid);

        // EFFECTS - Update user and pool state
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
        }

        // EFFECTS - Update weighted shares and reward debt
        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        // INTERACTIONS - Handle token transfers after all state updates
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
        }

        if (_amount > 0) {
            if (!IERC20(pool.lpToken).transfer(msg.sender, _amount)) {
                revert IPonderMasterChef.TransferFailed();
            }
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }


    /// @notice Emergency withdrawal
    /// @dev Allows withdrawal without reward collection
    /// @param _pid Pool ID to withdraw from
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        pool.totalWeightedShares -= user.weightedShares;
        pool.totalStaked -= amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.ponderStaked = 0;
        user.weightedShares = 0;

        if (!IERC20(pool.lpToken).transfer(msg.sender, amount)) {
            revert IPonderMasterChef.TransferFailed();
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }


    /*//////////////////////////////////////////////////////////////
                    BOOST MECHANICS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stake PONDER for boost
    /// @dev Locks PONDER tokens to increase farming multiplier
    /// @param _pid Pool ID to boost
    /// @param _amount Amount of PONDER to stake
    function boostStake(uint256 _pid, uint256 _amount) external nonReentrant {
        // CHECKS
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        if (_amount == 0) revert IPonderMasterChef.ZeroAmount();

        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        if (user.amount == 0) revert IPonderMasterChef.InsufficientAmount();

        // Check boost limits before any state changes
        uint256 maxPonderStake = getRequiredPonderForBoost(user.amount, pool.boostMultiplier);
        if (user.ponderStaked + _amount > maxPonderStake) revert IPonderMasterChef.BoostTooHigh();

        // Calculate pending rewards before any state changes
        _updatePool(_pid);
        uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;

        // Record initial balance for validation
        uint256 beforeBalance = PONDER.balanceOf(address(this));

        // EFFECTS - Update stake amounts
        user.ponderStaked += _amount;

        // Update weighted shares and validate boost
        _updateUserWeightedShares(_pid, msg.sender);
        if (user.weightedShares > user.amount * pool.boostMultiplier / PonderMasterChefTypes.BASE_MULTIPLIER) {
            revert IPonderMasterChef.BoostTooHigh();
        }

        // Update reward debt
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        // INTERACTIONS - Handle token transfers after all state updates
        if (!PONDER.transferFrom(msg.sender, address(this), _amount)) {
            revert IPonderMasterChef.TransferFailed();
        }

        // Validate transfer amount
        uint256 actualAmount = PONDER.balanceOf(address(this)) - beforeBalance;
        if (actualAmount <= 0) revert IPonderMasterChef.ZeroAmount();
        if (actualAmount != _amount) revert IPonderMasterChef.InvalidAmount();

        // Handle pending rewards
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
        }

        emit BoostStake(msg.sender, _pid, actualAmount);
    }

    //// @notice Remove PONDER boost
    /// @dev Withdraws PONDER tokens used for boost
    /// @param _pid Pool ID to remove boost from
    /// @param _amount Amount of PONDER to unstake
    function boostUnstake(uint256 _pid, uint256 _amount) external nonReentrant {
        // CHECKS
        if (_pid >= _poolInfo.length) revert IPonderMasterChef.InvalidPool();
        if (_amount == 0) revert IPonderMasterChef.ZeroAmount();

        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        if (user.ponderStaked < _amount) revert IPonderMasterChef.InsufficientAmount();

        // Calculate pending rewards before any state changes
        _updatePool(_pid);
        uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;

        // Record initial PONDER balance for validation
        uint256 initialBalance = PONDER.balanceOf(address(this));

        // EFFECTS - Update state variables
        user.ponderStaked -= _amount;

        // Update weighted shares
        _updateUserWeightedShares(_pid, msg.sender);

        // Update reward debt
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        // INTERACTIONS - Handle token transfers after all state updates
        // First handle pending rewards if any
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
        }

        // Then handle the unstaked PONDER tokens
        if (!PONDER.transfer(msg.sender, _amount)) {
            revert IPonderMasterChef.TransferFailed();
        }

        // Validate final balance
        uint256 finalBalance = PONDER.balanceOf(address(this));
        if (initialBalance - finalBalance != _amount) {
            revert IPonderMasterChef.InvalidAmount();
        }

        emit BoostUnstake(msg.sender, _pid, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                   INTERNAL HELPERS
   //////////////////////////////////////////////////////////////*/

    /// @notice Calculate deposit fee and actual deposit amount
    /// @dev Uses BASIS_POINTS denominator (10000) for fee calculation
    /// @param amount The total amount being deposited
    /// @param depositFeeBP The deposit fee in basis points
    /// @return depositFee The calculated fee amount
    /// @return actualAmount The remaining amount after fee
    function _calculateDepositFee(
        uint256 amount,
        uint16 depositFeeBP
    ) internal pure returns (uint256, uint256) {
        uint256 depositFee;
        uint256 actualAmount;

        if (depositFeeBP > 0) {
            depositFee = (amount * depositFeeBP) / PonderMasterChefTypes.BASIS_POINTS;
            actualAmount = amount - depositFee;
        } else {
            depositFee = 0;
            actualAmount = amount;
        }

        return (depositFee, actualAmount);
    }

    /// @notice Handle LP token deposit
    /// @dev Processes deposit including fee collection
    /// @param pool The pool info storage pointer
    /// @param amount The amount to deposit
    /// @return actualAmount The actual amount staked after fees
    function _handleDeposit(
        PonderMasterChefTypes.PoolInfo storage pool,
        uint256 amount
    ) internal returns (uint256) {
        if (amount == 0) return 0;

        uint256 beforeBalance = IERC20(pool.lpToken).balanceOf(address(this));

        // Transfer tokens
        if (!IERC20(pool.lpToken).transferFrom(msg.sender, address(this), amount)) {
            revert IPonderMasterChef.TransferFailed();
        }

        uint256 afterBalance = IERC20(pool.lpToken).balanceOf(address(this));
        uint256 receivedAmount = afterBalance - beforeBalance;
        if (receivedAmount == 0) revert IPonderMasterChef.NoTokensTransferred();

        // Handle deposit fee
        (uint256 depositFee, uint256 actualAmount) = _calculateDepositFee(receivedAmount, pool.depositFeeBP);

        if (depositFee > 0) {
            if (!IERC20(pool.lpToken).transfer(_teamReserve, depositFee)) {
                revert IPonderMasterChef.TransferFailed();
            }
        }

        return actualAmount;
    }


    /// @notice Update user's weighted shares
    /// @dev Recalculates boost and updates pool totals
    /// @param _pid Pool ID to update
    /// @param _user User address to update
    function _updateUserWeightedShares(uint256 _pid, address _user) internal {
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][_user];

        uint256 oldWeightedShares = user.weightedShares;
        uint256 newWeightedShares = user.amount;

        if (user.ponderStaked > 0) {
            uint256 boost = _calculateBoostMultiplier(
                user.ponderStaked,
                user.amount,
                pool.boostMultiplier
            );
            if (boost > pool.boostMultiplier) {
                boost = pool.boostMultiplier;
            }
            newWeightedShares = (user.amount * boost) / PonderMasterChefTypes.BASE_MULTIPLIER;
        }

        if (oldWeightedShares != newWeightedShares) {
            pool.totalWeightedShares = pool.totalWeightedShares - oldWeightedShares + newWeightedShares;
            user.weightedShares = newWeightedShares;
            emit WeightedSharesUpdated(_pid, _user, newWeightedShares, pool.totalWeightedShares);
            emit PoolWeightedSharesUpdated(_pid, pool.totalWeightedShares);
        }
    }

    /// @notice Calculate boost multiplier
    /// @dev Determines boost based on PONDER/LP ratio
    /// @param ponderStaked Amount of PONDER staked
    /// @param lpAmount Amount of LP tokens staked
    /// @param maxBoost Maximum allowed boost
    /// @return Boost multiplier (10000 = 1x)
    function _calculateBoostMultiplier(
        uint256 ponderStaked,
        uint256 lpAmount,
        uint256 maxBoost
    ) internal pure returns (uint256) {
        if (ponderStaked == 0 || lpAmount == 0) {
            return PonderMasterChefTypes.BASE_MULTIPLIER;
        }

        // Calculate required PONDER in single operation
        uint256 requiredPonder = (lpAmount * PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT) /
                        PonderMasterChefTypes.BASIS_POINTS;

        if (ponderStaked < requiredPonder) {
            return PonderMasterChefTypes.BASE_MULTIPLIER;
        }

        uint256 excessPonder = ponderStaked - requiredPonder;

        // Combine calculations to avoid multiplication after division
        uint256 extraBoost = (excessPonder * PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT) / requiredPonder;
        uint256 totalBoost = PonderMasterChefTypes.MIN_BOOST_MULTIPLIER + extraBoost;

        return totalBoost > maxBoost ? maxBoost : totalBoost;
    }

    /// @notice Safe PONDER transfer
    /// @dev Handles insufficient balances gracefully
    /// @param _to Recipient address
    /// @param _amount Amount to transfer
    function _safePonderTransfer(address _to, uint256 _amount) internal {
        uint256 ponderBalance = PONDER.balanceOf(address(this));
        if (_amount > ponderBalance) {
            if (!PONDER.transfer(_to, ponderBalance)) {
                revert IPonderMasterChef.TransferFailed();
            }
        } else {
            if (!PONDER.transfer(_to, _amount)) {
                revert IPonderMasterChef.TransferFailed();
            }
        }
    }


    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    /// @notice Update fee recipient
    /// @dev Sets new address for collecting deposit fees
    /// @param _newTeamReserve New fee collector address
    function setTeamReserve(address _newTeamReserve) external onlyOwner {
        if (_newTeamReserve == address(0)) revert IPonderMasterChef.ZeroAddress();
        address oldTeamReserve = _teamReserve;
        _teamReserve = _newTeamReserve;
        emit TeamReserveUpdated(oldTeamReserve, _newTeamReserve);
    }

    /// @notice Modify emission rate
    /// @dev Updates PONDER tokens distributed per second
    /// @param _newPonderPerSecond New emission rate
    function setPonderPerSecond(uint256 _newPonderPerSecond) external onlyOwner {
        // Effects: Update state variables before external calls
        _ponderPerSecond = _newPonderPerSecond;

        // Interactions: External calls last
        _massUpdatePools();

        emit PonderPerSecondUpdated(_ponderPerSecond);
    }


    /// @notice Initialize ownership transfer
    /// @dev Starts two-step ownership transfer
    /// @param newOwner Address of the new owner
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert IPonderMasterChef.ZeroAddress();
        _pendingOwner = newOwner;
        emit OwnershipTransferInitiated(_owner, newOwner);
    }

    /// @notice Complete ownership transfer
    /// @dev Finalizes two-step ownership transfer
    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert IPonderMasterChef.Forbidden();
        address oldOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, _owner);
    }
}
