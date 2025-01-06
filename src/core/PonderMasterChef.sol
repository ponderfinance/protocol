// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPonderMasterChef.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderPair.sol";
import "../interfaces/IERC20.sol";
import "./PonderToken.sol";

/**
* @title PonderMasterChef
* @notice Manages token farming rewards and boost mechanics for Ponder Protocol
* @dev Distributes PONDER tokens to liquidity providers based on weighted shares
*      Total emissions remain fixed regardless of boosts applied
*/
contract PonderMasterChef is IPonderMasterChef {
    /// @notice The PONDER token contract
    PonderToken public immutable ponder;

    /// @notice DEX factory for validating LP tokens
    IPonderFactory public immutable factory;

    /// @notice PONDER tokens created per second (fixed rate)
    uint256 public ponderPerSecond;

    /// @notice Info of each pool
    PoolInfo[] public poolInfo;

    /// @notice Info of each user that stakes LP tokens, by pid
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Total allocation points across all pools
    uint256 public totalAllocPoint;

    /// @notice Start time of rewards distribution
    uint256 public immutable startTime;

    /// @notice Treasury address for deposit fees
    address public treasury;

    /// @notice Contract owner address
    address public owner;

    /// @notice Pending owner for 2-step transfer
    address public pendingOwner;

    /// @notice Basis points for percentage calculations (100% = 10000)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Base multiplier (1x = 10000)
    uint256 public constant BASE_MULTIPLIER = 10000;

    /// @notice Minimum boost multiplier (2x = 20000)
    uint256 public constant MIN_BOOST_MULTIPLIER = 20000;

    /// @notice Required PONDER stake relative to LP value (10%)
    uint256 public constant BOOST_THRESHOLD_PERCENT = 1000;

    /// @notice Maximum additional boost percentage (100%)
    uint256 public constant MAX_EXTRA_BOOST_PERCENT = 10000;

    /// @notice Custom errors
    error InvalidBoostMultiplier();
    error ExcessiveDepositFee();
    error Forbidden();
    error InvalidPool();
    error InvalidPair();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientAmount();
    error BoostTooHigh();

    /// @notice Events for weighted shares tracking
    event WeightedSharesUpdated(uint256 indexed pid, address indexed user, uint256 newShares, uint256 totalShares);
    event PoolWeightedSharesUpdated(uint256 indexed pid, uint256 totalWeightedShares);

    modifier onlyOwner {
        if (msg.sender != owner) revert Forbidden();
        _;
    }

    /**
     * @notice Constructor initializes PonderMasterChef contract
    * @param _ponder PONDER token contract address
    * @param _factory Factory contract address
    * @param _treasury Treasury address to receive deposit fees
    * @param _ponderPerSecond PONDER tokens minted per second
    * @param _startTime Start time for rewards distribution
    */
    constructor(
        PonderToken _ponder,
        IPonderFactory _factory,
        address _treasury,
        uint256 _ponderPerSecond,
        uint256 _startTime
    ) {
        if (_treasury == address(0)) revert ZeroAddress();
        ponder = _ponder;
        factory = _factory;
        treasury = _treasury;
        ponderPerSecond = _ponderPerSecond;
        startTime = _startTime;
        owner = msg.sender;
    }

    /**
     * @notice Returns the number of pools
    * @return The total number of pools
    */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice View function to see pending PONDER rewards for an address
    * @param _pid Pool ID
    * @param _user Address of the user
    * @return pending Amount of PONDER rewards pending
    */
    function pendingPonder(uint256 _pid, address _user)
    external
    view
    returns (uint256 pending)
    {
        if (_pid >= poolInfo.length) revert InvalidPool();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accPonderPerShare = pool.accPonderPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalWeightedShares != 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            uint256 ponderReward = (timeElapsed * ponderPerSecond * pool.allocPoint) / totalAllocPoint;
            accPonderPerShare += (ponderReward * 1e12) / pool.totalWeightedShares;
        }

        pending = (user.weightedShares * accPonderPerShare / 1e12) - user.rewardDebt;
    }

    /**
     * @notice Add a new LP pool
    * @param _allocPoint Allocation points for the new pool
    * @param _lpToken Address of the LP token contract
    * @param _depositFeeBP Deposit fee in basis points
    * @param _boostMultiplier Maximum boost multiplier for the pool
    * @param _withUpdate Whether to update all pools
    */
    function add(
        uint256 _allocPoint,
        address _lpToken,
        uint16 _depositFeeBP,
        uint16 _boostMultiplier,
        bool _withUpdate
    ) external onlyOwner {
        if (_depositFeeBP > 1000) revert ExcessiveDepositFee();
        if (_boostMultiplier < MIN_BOOST_MULTIPLIER) revert InvalidBoostMultiplier();
        if (_boostMultiplier > 50000) revert InvalidBoostMultiplier();

        if (_withUpdate) {
            massUpdatePools();
        }

        // Validate LP token is from our factory
        address token0 = IPonderPair(_lpToken).token0();
        address token1 = IPonderPair(_lpToken).token1();
        if (factory.getPair(token0, token1) != _lpToken) revert InvalidPair();

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint += _allocPoint;

        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accPonderPerShare: 0,
            totalStaked: 0,
            totalWeightedShares: 0,
            depositFeeBP: _depositFeeBP,
            boostMultiplier: _boostMultiplier
        }));

        emit PoolAdded(poolInfo.length - 1, _lpToken, _allocPoint);
    }

    /**
     * @notice Update reward variables for all pools
    * @dev Be careful of gas spending
    */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @notice Update reward variables of the given pool
    * @param _pid Pool ID to update
    */
    function updatePool(uint256 _pid) public {
        if (_pid >= poolInfo.length) revert InvalidPool();
        PoolInfo storage pool = poolInfo[_pid];

        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.totalWeightedShares == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 ponderReward = (timeElapsed * ponderPerSecond * pool.allocPoint) / totalAllocPoint;

        ponder.mint(address(this), ponderReward);
        pool.accPonderPerShare += (ponderReward * 1e12) / pool.totalWeightedShares;
        pool.lastRewardTime = block.timestamp;
    }

    /**
     * @notice Update pool allocation points
    * @param _pid Pool ID to update
    * @param _allocPoint New allocation points
    * @param _withUpdate Whether to update all pools
    */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (_pid >= poolInfo.length) revert InvalidPool();

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;

        emit PoolUpdated(_pid, _allocPoint);
    }

    /**
     * @notice Update user's weighted shares in pool
    * @param _pid Pool ID
    * @param _user User address
    */
    function _updateUserWeightedShares(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 oldWeightedShares = user.weightedShares;
        uint256 newWeightedShares = user.amount;

        if (user.ponderStaked > 0) {
            uint256 boost = calculateBoostMultiplier(
                user.ponderStaked,
                user.amount,
                pool.boostMultiplier
            );
            if (boost > BASE_MULTIPLIER) {
                newWeightedShares = (user.amount * boost) / BASE_MULTIPLIER;
            }
        }

        if (oldWeightedShares != newWeightedShares) {
            pool.totalWeightedShares = pool.totalWeightedShares - oldWeightedShares + newWeightedShares;
            user.weightedShares = newWeightedShares;

            emit WeightedSharesUpdated(_pid, _user, newWeightedShares, pool.totalWeightedShares);
            emit PoolWeightedSharesUpdated(_pid, pool.totalWeightedShares);
        }
    }

    /**
     * @notice Deposit LP tokens to earn PONDER rewards
    * @param _pid Pool ID
    * @param _amount Amount of LP tokens to deposit
    */
    function deposit(uint256 _pid, uint256 _amount) external {
        if (_pid >= poolInfo.length) revert InvalidPool();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;
            if (pending > 0) {
                safePonderTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            uint256 beforeBalance = IERC20(pool.lpToken).balanceOf(address(this));
            IERC20(pool.lpToken).transferFrom(msg.sender, address(this), _amount);
            uint256 afterBalance = IERC20(pool.lpToken).balanceOf(address(this));
            _amount = afterBalance - beforeBalance;

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (_amount * pool.depositFeeBP) / BASIS_POINTS;
                IERC20(pool.lpToken).transfer(treasury, depositFee);
                _amount = _amount - depositFee;
            }

            user.amount += _amount;
            pool.totalStaked += _amount;
        }

        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @notice Withdraw LP tokens
    * @param _pid Pool ID
    * @param _amount Amount of LP tokens to withdraw
    */
    function withdraw(uint256 _pid, uint256 _amount) external {
        if (_pid >= poolInfo.length) revert InvalidPool();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount < _amount) revert InsufficientAmount();

        updatePool(_pid);

        uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safePonderTransfer(msg.sender, pending);
        }

        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
            IERC20(pool.lpToken).transfer(msg.sender, _amount);
        }

        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     * @notice Emergency withdraw LP tokens without caring about rewards
    * @param _pid Pool ID
    */
    function emergencyWithdraw(uint256 _pid) external {
        if (_pid >= poolInfo.length) revert InvalidPool();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        pool.totalWeightedShares -= user.weightedShares;
        pool.totalStaked -= amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.ponderStaked = 0;
        user.weightedShares = 0;

        IERC20(pool.lpToken).transfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /**
     * @notice Stake PONDER tokens to boost rewards
    * @param _pid Pool ID
    * @param _amount Amount of PONDER to stake
    */
    function boostStake(uint256 _pid, uint256 _amount) external {
if (_pid >= poolInfo.length) revert InvalidPool();
if (_amount == 0) revert ZeroAmount();
UserInfo storage user = userInfo[_pid][msg.sender];

updatePool(_pid);

uint256 pending = (user.weightedShares * poolInfo[_pid].accPonderPerShare / 1e12) - user.rewardDebt;
if (pending > 0) {
    safePonderTransfer(msg.sender, pending);
}

        ponder.transferFrom(msg.sender, address(this), _amount);
        user.ponderStaked += _amount;

        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * poolInfo[_pid].accPonderPerShare) / 1e12;

        emit BoostStake(msg.sender, _pid, _amount);
    }

    /**
     * @notice Unstake PONDER tokens used for boost
     * @param _pid Pool ID
     * @param _amount Amount of PONDER to unstake
     */
    function boostUnstake(uint256 _pid, uint256 _amount) external {
        if (_pid >= poolInfo.length) revert InvalidPool();
        if (_amount == 0) revert ZeroAmount();
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.ponderStaked < _amount) revert InsufficientAmount();

        updatePool(_pid);

        uint256 pending = (user.weightedShares * poolInfo[_pid].accPonderPerShare / 1e12) - user.rewardDebt;
        if (pending > 0) {
            safePonderTransfer(msg.sender, pending);
        }

        user.ponderStaked -= _amount;
        ponder.transfer(msg.sender, _amount);

        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * poolInfo[_pid].accPonderPerShare) / 1e12;

        emit BoostUnstake(msg.sender, _pid, _amount);
    }

    /**
     * @notice Safe PONDER transfer function, just in case if rounding error causes pool to not have enough PONDER
     * @param _to Address to receive PONDER
     * @param _amount Amount of PONDER to transfer
     */
    function safePonderTransfer(address _to, uint256 _amount) internal {
        uint256 ponderBalance = ponder.balanceOf(address(this));
        if (_amount > ponderBalance) {
            ponder.transfer(_to, ponderBalance);
        } else {
            ponder.transfer(_to, _amount);
        }
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Calculate boost multiplier based on PONDER stake relative to LP value
     * @param ponderStaked Amount of PONDER staked for boost
     * @param lpAmount Amount of LP tokens staked
     * @param maxBoost Maximum boost multiplier allowed for the pool
     * @return Boost multiplier (10000 = 1x)
     */
    function calculateBoostMultiplier(
        uint256 ponderStaked,
        uint256 lpAmount,
        uint256 maxBoost
    ) public pure returns (uint256) {
        if (ponderStaked == 0 || lpAmount == 0) {
            return BASE_MULTIPLIER;
        }

        uint256 requiredPonder = (lpAmount * BOOST_THRESHOLD_PERCENT) / BASIS_POINTS;

        if (ponderStaked < requiredPonder) {
            return BASE_MULTIPLIER;
        }

        uint256 excessPonder = ponderStaked - requiredPonder;
        uint256 extraBoost = (excessPonder * MAX_EXTRA_BOOST_PERCENT) / requiredPonder;
        uint256 totalBoost = MIN_BOOST_MULTIPLIER + extraBoost;

        return totalBoost > maxBoost ? maxBoost : totalBoost;
    }

    /**
     * @notice Calculate required PONDER stake for desired boost multiplier
     * @param lpAmount Amount of LP tokens staked
     * @param targetMultiplier Desired boost multiplier
     * @return Required PONDER stake amount
     */
    function getRequiredPonderForBoost(
        uint256 lpAmount,
        uint256 targetMultiplier
    ) external pure returns (uint256) {
        if (targetMultiplier <= BASE_MULTIPLIER) {
            return 0;
        }
        if (targetMultiplier < MIN_BOOST_MULTIPLIER) {
            return (lpAmount * BOOST_THRESHOLD_PERCENT) / BASIS_POINTS;
        }

        uint256 extraBoost = targetMultiplier - MIN_BOOST_MULTIPLIER;
        uint256 baseRequired = (lpAmount * BOOST_THRESHOLD_PERCENT) / BASIS_POINTS;
        uint256 additionalRequired = (baseRequired * extraBoost) / MAX_EXTRA_BOOST_PERCENT;

        return baseRequired + additionalRequired;
    }

    /**
     * @notice Preview boost multiplier for given stake amounts
     * @param _pid Pool ID
     * @param ponderStaked Amount of PONDER to stake
     * @param lpAmount Amount of LP tokens staked
     * @return Predicted boost multiplier
     */
    function previewBoostMultiplier(
        uint256 _pid,
        uint256 ponderStaked,
        uint256 lpAmount
    ) external view returns (uint256) {
        if (_pid >= poolInfo.length) revert InvalidPool();
        return calculateBoostMultiplier(
            ponderStaked,
            lpAmount,
            poolInfo[_pid].boostMultiplier
        );
    }

    /**
     * @notice Update PONDER emission rate
     * @param _ponderPerSecond New PONDER tokens created per second
     */
    function setPonderPerSecond(uint256 _ponderPerSecond) external onlyOwner {
        massUpdatePools();
        ponderPerSecond = _ponderPerSecond;
        emit PonderPerSecondUpdated(ponderPerSecond);
    }
}
