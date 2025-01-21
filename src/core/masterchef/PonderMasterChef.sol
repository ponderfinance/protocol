// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPonderMasterChef } from "./IPonderMasterChef.sol";
import { PonderMasterChefStorage } from "./storage/PonderMasterChefStorage.sol";
import { PonderMasterChefTypes } from "./types/PonderMasterChefTypes.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PonderToken } from "../token/PonderToken.sol";

/**
 * @title PonderMasterChef
 * @notice Implementation of the PonderMasterChef staking and farming system
 * @dev Manages LP staking, PONDER emissions, and boost mechanics
 */
contract PonderMasterChef is IPonderMasterChef, PonderMasterChefStorage {
    using PonderMasterChefTypes for *;

    // Immutable state variables
    /// @notice The PONDER token contract
    PonderToken public immutable PONDER;

    /// @notice Factory contract for validating LP tokens
    IPonderFactory public immutable FACTORY;

    /**
     * @notice Initializes the MasterChef contract
     * @param _ponder PONDER token contract address
     * @param _factory Factory contract for LP token validation
     * @param _teamReserve_ Address to receive deposit fees
     * @param _ponderPerSecond_ Initial PONDER tokens per second
     */
    constructor(
        PonderToken _ponder,
        IPonderFactory _factory,
        address _teamReserve_,
        uint256 _ponderPerSecond_
    ) {
        if (_teamReserve_ == address(0)) revert PonderMasterChefTypes.ZeroAddress();
        PONDER = _ponder;
        FACTORY = _factory;
        _teamReserve = _teamReserve_;
        _ponderPerSecond = _ponderPerSecond_;
        _owner = msg.sender;
    }

    /**
     * @notice Restricts function to the contract owner
     */
    modifier onlyOwner {
        if (msg.sender != _owner) revert PonderMasterChefTypes.Forbidden();
        _;
    }

    // State Variable Getters

    /// @inheritdoc IPonderMasterChef
    function basisPoints() external pure returns (uint256) {
        return PonderMasterChefTypes.BASIS_POINTS;
    }

    /// @inheritdoc IPonderMasterChef
    function baseMultiplier() external pure returns (uint256) {
        return PonderMasterChefTypes.BASE_MULTIPLIER;
    }

    /// @inheritdoc IPonderMasterChef
    function minBoostMultiplier() external pure returns (uint256) {
        return PonderMasterChefTypes.MIN_BOOST_MULTIPLIER;
    }

    /// @inheritdoc IPonderMasterChef
    function boostThresholdPercent() external pure returns (uint256) {
        return PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT;
    }

    /// @inheritdoc IPonderMasterChef
    function maxExtraBoostPercent() external pure returns (uint256) {
        return PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT;
    }

    /// @inheritdoc IPonderMasterChef
    function maxAllocPoint() external pure returns (uint256) {
        return PonderMasterChefTypes.MAX_ALLOC_POINT;
    }


    /// @inheritdoc IPonderMasterChef
    function userInfo(uint256 _pid, address _user) external view returns (
        uint256 amount,
        uint256 rewardDebt,
        uint256 ponderStaked,
        uint256 weightedShares
    ) {
        PonderMasterChefTypes.UserInfo storage info = _userInfo[_pid][_user];
        return (info.amount, info.rewardDebt, info.ponderStaked, info.weightedShares);
    }

    /// @inheritdoc IPonderMasterChef
    function teamReserve() external view returns (address) {
        return _teamReserve;
    }

    /// @inheritdoc IPonderMasterChef
    function ponderPerSecond() external view returns (uint256) {
        return _ponderPerSecond;
    }

    /// @inheritdoc IPonderMasterChef
    function totalAllocPoint() external view returns (uint256) {
        return _totalAllocPoint;
    }

    /// @inheritdoc IPonderMasterChef
    function owner() external view returns (address) {
        return _owner;
    }

    /// @inheritdoc IPonderMasterChef
    function startTime() external view returns (uint256) {
        return _startTime;
    }

    /// @inheritdoc IPonderMasterChef
    function farmingStarted() external view returns (bool) {
        return _farmingStarted;
    }

    // View Functions

    /// @inheritdoc IPonderMasterChef
    function poolLength() external view returns (uint256) {
        return _poolInfo.length;
    }

    /// @inheritdoc IPonderMasterChef
    function pendingPonder(uint256 _pid, address _user) external view returns (uint256) {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();

        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][_user];

        uint256 accPonderPerShare = pool.accPonderPerShare;
        uint256 lpSupply = pool.totalWeightedShares;

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0 && _farmingStarted) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            uint256 ponderReward = (timeElapsed * _ponderPerSecond * pool.allocPoint) / _totalAllocPoint;

            uint256 remainingMintableForAccrual = PONDER.maximumSupply() - PONDER.totalSupply();
            if (ponderReward > remainingMintableForAccrual) {
                ponderReward = remainingMintableForAccrual;
            }

            accPonderPerShare = accPonderPerShare + ((ponderReward * 1e12) / lpSupply);
        }

        uint256 pending = user.weightedShares > 0 ?
            ((user.weightedShares * accPonderPerShare) / 1e12) - user.rewardDebt :
            0;

        uint256 remainingMintableForPending = PONDER.maximumSupply() - PONDER.totalSupply();
        if (pending > remainingMintableForPending) {
            pending = remainingMintableForPending;
        }

        if (block.timestamp > PONDER.deploymentTime() + PONDER.mintingEnd()) {
            pending = 0;
        }

        return pending;
    }

    /// @inheritdoc IPonderMasterChef
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
        uint256 baseRequired = (
            lpAmount * PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT
        ) / PonderMasterChefTypes.BASIS_POINTS;
        uint256 additionalRequired = (baseRequired * extraBoost) / PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT;

        return baseRequired + additionalRequired;
    }

    /// @inheritdoc IPonderMasterChef
    function previewBoostMultiplier(
        uint256 _pid,
        uint256 ponderStaked,
        uint256 lpAmount
    ) external view returns (uint256) {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        return _calculateBoostMultiplier(
            ponderStaked,
            lpAmount,
            _poolInfo[_pid].boostMultiplier
        );
    }

    // Pool Management Functions

    /// @inheritdoc IPonderMasterChef
    function add(
        uint256 _allocPoint,
        address _lpToken,
        uint16 _depositFeeBP,
        uint16 _boostMultiplier
    ) external onlyOwner {
        if (_lpToken == address(0)) revert PonderMasterChefTypes.ZeroAddress();
        if (_allocPoint > PonderMasterChefTypes.MAX_ALLOC_POINT)  {
            revert PonderMasterChefTypes.ExcessiveAllocation();
        }
        if (_depositFeeBP > 1000) revert PonderMasterChefTypes.ExcessiveDepositFee();
        if (_boostMultiplier < PonderMasterChefTypes.MIN_BOOST_MULTIPLIER) {
            revert PonderMasterChefTypes.InvalidBoostMultiplier();
        }

        if (_boostMultiplier > 50000) revert PonderMasterChefTypes.InvalidBoostMultiplier();

        // Check for duplicate pools
        uint256 length = _poolInfo.length;
        for (uint256 pid; pid < length; ++pid) {
            if (_poolInfo[pid].lpToken == _lpToken) revert PonderMasterChefTypes.DuplicatePool();
        }

        _massUpdatePools();

        // Validate LP token is from our factory
        address token0 = IPonderPair(_lpToken).token0();
        address token1 = IPonderPair(_lpToken).token1();
        if (FACTORY.getPair(token0, token1) != _lpToken) revert PonderMasterChefTypes.InvalidPair();

        uint256 lastRewardTime = _farmingStarted ? block.timestamp : 0;
        _totalAllocPoint += _allocPoint;

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

        emit PoolAdded(_poolInfo.length - 1, _lpToken, _allocPoint);
    }

    /// @inheritdoc IPonderMasterChef
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();

        if (_withUpdate) {
            _massUpdatePools();
        }

        _totalAllocPoint = _totalAllocPoint - _poolInfo[_pid].allocPoint + _allocPoint;
        _poolInfo[_pid].allocPoint = _allocPoint;

        emit PoolUpdated(_pid, _allocPoint);
    }

    // Pool Update Functions

    /**
     * @notice Update reward variables for all pools
     * @dev Be careful of gas spending
     */
    function _massUpdatePools() internal {
        uint256 length = _poolInfo.length;
        for (uint256 pid; pid < length; ++pid) {
            _updatePool(pid);
        }
    }


    /// @inheritdoc IPonderMasterChef
    function updatePool(uint256 _pid) external {
        _updatePool(_pid);
    }

    /**
     * @notice Update reward variables of the given pool
     * @param _pid Pool ID to update
     */
    function _updatePool(uint256 _pid) internal {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];

        if (!_farmingStarted) {
            return;
        }

        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;

        if (pool.totalWeightedShares == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 ponderReward = (timeElapsed * _ponderPerSecond * pool.allocPoint) / _totalAllocPoint;

        pool.accPonderPerShare += (ponderReward * 1e12) / pool.totalWeightedShares;
        pool.lastRewardTime = block.timestamp;

        PONDER.mint(address(this), ponderReward);
    }

    // User Interaction Functions

    /// @inheritdoc IPonderMasterChef
    function deposit(uint256 _pid, uint256 _amount) external {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        if (!_farmingStarted && _amount > 0) {
            _startTime = block.timestamp;
            _farmingStarted = true;
        }

        _updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;
            if (pending > 0) {
                _safePonderTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            uint256 beforeBalance = IERC20(pool.lpToken).balanceOf(address(this));
            IERC20(pool.lpToken).transferFrom(msg.sender, address(this), _amount);
            uint256 afterBalance = IERC20(pool.lpToken).balanceOf(address(this));
            uint256 actualAmount = afterBalance - beforeBalance;

            if (actualAmount == 0) revert PonderMasterChefTypes.NoTokensTransferred();

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (actualAmount * pool.depositFeeBP) / PonderMasterChefTypes.BASIS_POINTS;
                IERC20(pool.lpToken).transfer(_teamReserve, depositFee);
                actualAmount = actualAmount - depositFee;
            }

            user.amount += actualAmount;
            pool.totalStaked += actualAmount;
        }

        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @inheritdoc IPonderMasterChef
    function withdraw(uint256 _pid, uint256 _amount) external {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        if (user.amount < _amount) revert PonderMasterChefTypes.InsufficientAmount();

        _updatePool(_pid);

        uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
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

    /// @inheritdoc IPonderMasterChef
    function emergencyWithdraw(uint256 _pid) external {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

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

    /// @inheritdoc IPonderMasterChef
    function boostStake(uint256 _pid, uint256 _amount) external {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        if (_amount == 0) revert PonderMasterChefTypes.ZeroAmount();

        PonderMasterChefTypes.PoolInfo storage pool = _poolInfo[_pid];
        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];

        if (user.amount == 0) revert PonderMasterChefTypes.InsufficientAmount();

        uint256 maxPonderStake = getRequiredPonderForBoost(user.amount, pool.boostMultiplier);
        if (user.ponderStaked + _amount > maxPonderStake) revert PonderMasterChefTypes.BoostTooHigh();

        uint256 beforeBalance = PONDER.balanceOf(address(this));
        if (!PONDER.transferFrom(msg.sender, address(this), _amount)) {
            revert PonderMasterChefTypes.TransferFailed();
        }

        uint256 actualAmount = PONDER.balanceOf(address(this)) - beforeBalance;
        if (actualAmount == 0) revert PonderMasterChefTypes.ZeroAmount();
        if (actualAmount != _amount) revert PonderMasterChefTypes.InvalidAmount();

        _updatePool(_pid);
        uint256 pending = (user.weightedShares * pool.accPonderPerShare / 1e12) - user.rewardDebt;
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
        }

        user.ponderStaked += actualAmount;
        _updateUserWeightedShares(_pid, msg.sender);

        if (user.weightedShares > user.amount * pool.boostMultiplier / PonderMasterChefTypes.BASE_MULTIPLIER) {
            revert PonderMasterChefTypes.BoostTooHigh();
        }

        user.rewardDebt = (user.weightedShares * pool.accPonderPerShare) / 1e12;

        emit BoostStake(msg.sender, _pid, actualAmount);
    }

    /// @inheritdoc IPonderMasterChef
    function boostUnstake(uint256 _pid, uint256 _amount) external {
        if (_pid >= _poolInfo.length) revert PonderMasterChefTypes.InvalidPool();
        if (_amount == 0) revert PonderMasterChefTypes.ZeroAmount();

        PonderMasterChefTypes.UserInfo storage user = _userInfo[_pid][msg.sender];
        if (user.ponderStaked < _amount) revert PonderMasterChefTypes.InsufficientAmount();

        _updatePool(_pid);

        uint256 pending = (user.weightedShares * _poolInfo[_pid].accPonderPerShare / 1e12) - user.rewardDebt;
        if (pending > 0) {
            _safePonderTransfer(msg.sender, pending);
        }

        user.ponderStaked -= _amount;
        PONDER.transfer(msg.sender, _amount);

        _updateUserWeightedShares(_pid, msg.sender);
        user.rewardDebt = (user.weightedShares * _poolInfo[_pid].accPonderPerShare) / 1e12;

        emit BoostUnstake(msg.sender, _pid, _amount);
    }

    // Internal Helper Functions

    /**
     * @notice Update user's weighted shares in pool
     * @param _pid Pool ID
     * @param _user User address
     */
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

    /**
     * @notice Calculate boost multiplier based on PONDER stake relative to LP value
     * @param ponderStaked Amount of PONDER staked for boost
     * @param lpAmount Amount of LP tokens staked
     * @param maxBoost Maximum boost multiplier allowed for the pool
     * @return Boost multiplier (10000 = 1x)
     */
    function _calculateBoostMultiplier(
        uint256 ponderStaked,
        uint256 lpAmount,
        uint256 maxBoost
    ) internal pure returns (uint256) {
        if (ponderStaked == 0 || lpAmount == 0) {
            return PonderMasterChefTypes.BASE_MULTIPLIER;
        }

        uint256 requiredPonder = (
            lpAmount * PonderMasterChefTypes.BOOST_THRESHOLD_PERCENT
        ) / PonderMasterChefTypes.BASIS_POINTS;

        if (ponderStaked < requiredPonder) {
            return PonderMasterChefTypes.BASE_MULTIPLIER;
        }

        uint256 excessPonder = ponderStaked - requiredPonder;
        uint256 extraBoost = (excessPonder * PonderMasterChefTypes.MAX_EXTRA_BOOST_PERCENT) / requiredPonder;
        uint256 totalBoost = PonderMasterChefTypes.MIN_BOOST_MULTIPLIER + extraBoost;

        return totalBoost > maxBoost ? maxBoost : totalBoost;
    }

    /**
     * @notice Safe PONDER transfer function that gracefully handles insufficient balances
     * @param _to Address to receive PONDER
     * @param _amount Amount of PONDER to transfer
     */
    function _safePonderTransfer(address _to, uint256 _amount) internal {
        uint256 ponderBalance = PONDER.balanceOf(address(this));
        if (_amount > ponderBalance) {
            PONDER.transfer(_to, ponderBalance);
        } else {
            PONDER.transfer(_to, _amount);
        }
    }

    // Admin Functions

    /// @inheritdoc IPonderMasterChef
    function setTeamReserve(address _newTeamReserve) external onlyOwner {
        if (_newTeamReserve == address(0)) revert PonderMasterChefTypes.ZeroAddress();
        address oldTeamReserve = _teamReserve;
        _teamReserve = _newTeamReserve;
        emit TeamReserveUpdated(oldTeamReserve, _newTeamReserve);
    }

    /// @inheritdoc IPonderMasterChef
    function setPonderPerSecond(uint256 _newPonderPerSecond) external onlyOwner {
        _massUpdatePools();
        _ponderPerSecond = _newPonderPerSecond;
        emit PonderPerSecondUpdated(_ponderPerSecond);
    }
}
