// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderStaking } from "./IPonderStaking.sol";
import { IPonderToken } from "../token/IPonderToken.sol";

import { PonderStakingStorage } from "./storage/PonderStakingStorage.sol";
import { PonderStakingTypes } from "./types/PonderStakingTypes.sol";
import { PonderKAP20 } from "../token/PonderKAP20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER STAKING CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title PonderStaking
/// @author taayyohh
/// @notice Implementation of Ponder protocol's staking mechanism
/// @dev Handles staking of PONDER tokens for xPONDER shares
///      Implements rebase mechanism to distribute protocol fees
///      Inherits storage layout and ERC20 functionality
contract PonderStaking is IPonderStaking, PonderStakingStorage, PonderKAP20("Staked KOI", "xKOI") {
    using PonderStakingTypes for *;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                         IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice PONDER token contract reference
    IERC20 public immutable PONDER;

    /// @notice Protocol router for performing swaps
    IPonderRouter public immutable ROUTER;

    /// @notice Protocol factory contract reference
    IPonderFactory public immutable FACTORY;

    /// @notice Initializes the staking contract
    /// @param _ponder Address of PONDER token contract
    /// @param _router Address of protocol router
    /// @param _factory Address of protocol factory
    constructor(
        address _ponder,
        address _router,
        address _factory
    ) {
        if (_ponder == address(0) || _router == address(0) || _factory == address(0))
            revert PonderKAP20.ZeroAddress();

        PONDER = IERC20(_ponder);
        ROUTER = IPonderRouter(_router);
        FACTORY = IPonderFactory(_factory);
        stakingOwner = msg.sender;
        lastRebaseTime = block.timestamp;
        DEPLOYMENT_TIME = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                       STAKING OPERATIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Stakes PONDER tokens for xPONDER shares
    /// @param amount Amount of PONDER to stake
    /// @param recipient Address to receive the xPONDER shares
    /// @return shares Amount of xPONDER shares minted
    function enter(uint256 amount, address recipient) external returns (uint256 shares) {
        // Checks
        if (amount == 0) revert IPonderStaking.InvalidAmount();
        if (recipient == address(0)) revert PonderKAP20.ZeroAddress();

        uint256 totalPonder = PONDER.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        // Calculate shares and initialize fee debt
        if (totalShares == 0) {
            if (amount < PonderStakingTypes.MINIMUM_FIRST_STAKE)
                revert IPonderStaking.InsufficientFirstStake();
            shares = amount;
        } else {
            // Maintain precision by checking which order of operations is safe
            uint256 scaledAmount = amount * PonderStakingTypes.FEE_PRECISION;
            if (scaledAmount / PonderStakingTypes.FEE_PRECISION != amount) {
                // If scaling would overflow, fall back to original calculation
                shares = (amount * totalShares) / totalPonder;
            } else {
                // Scale up, multiply, then scale down for more precision
                shares = (scaledAmount * totalShares) / (totalPonder * PonderStakingTypes.FEE_PRECISION);
            }
        }

        // Calculate fee debt - use same scaling approach for consistency
        uint256 scaledShares = shares * PonderStakingTypes.FEE_PRECISION;
        if (scaledShares / PonderStakingTypes.FEE_PRECISION != shares) {
            // If scaling would overflow, use original calculation
            userFeeDebt[recipient] = (shares * accumulatedFeesPerShare) / PonderStakingTypes.FEE_PRECISION;
        } else {
            // Scale up for precision, then scale down
            userFeeDebt[recipient] = (scaledShares * accumulatedFeesPerShare)
                / (PonderStakingTypes.FEE_PRECISION * PonderStakingTypes.FEE_PRECISION);
        }

        // Effects
        _mint(recipient, shares);
        totalDepositedPonder += amount;

        // Interactions
        PONDER.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(recipient, amount, shares);
    }

    /// @notice Withdraws PONDER by burning xPONDER shares
    /// @param shares Amount of xPONDER to burn
    /// @return amount Amount of PONDER tokens returned
    function leave(uint256 shares) external returns (uint256 amount) {
        if (msg.sender == IPonderToken(address(PONDER)).teamReserve()) {
            if (block.timestamp < DEPLOYMENT_TIME + PonderStakingTypes.TEAM_LOCK_DURATION) {
                revert IPonderStaking.TeamStakingLocked();
            }
        }

        // CHECKS
        if (shares == 0) revert IPonderStaking.InvalidAmount();
        if (shares > balanceOf(msg.sender)) revert IPonderStaking.InvalidSharesAmount();

        // Calculate base withdrawal amount
        uint256 totalShares = totalSupply();
        amount = (shares * PONDER.balanceOf(address(this))) / totalShares;

        if (amount < PonderStakingTypes.MINIMUM_WITHDRAW)
            revert IPonderStaking.MinimumSharesRequired();

        // Handle pending fees before burn
        uint256 pendingFees = _getPendingFees(msg.sender, shares);

        // EFFECTS - Update all state variables before transfers
        userFeeDebt[msg.sender] = ((balanceOf(msg.sender) - shares) * accumulatedFeesPerShare)
            / PonderStakingTypes.FEE_PRECISION;

        _burn(msg.sender, shares);
        totalDepositedPonder -= amount;

        if (pendingFees > 0) {
            totalUnclaimedFees -= pendingFees;
        }

        emit Withdrawn(msg.sender, amount, shares);

        // INTERACTIONS - External calls last
        // Transfer base amount
        PONDER.safeTransfer(msg.sender, amount);

        // Handle fee transfer if applicable
        if (pendingFees > 0) {
            PONDER.safeTransfer(msg.sender, pendingFees);
            emit FeesClaimed(msg.sender, pendingFees);
        }
    }

    /// @notice Claims accumulated protocol fees without unstaking
    /// @return amount Amount of PONDER fees claimed
    function claimFees() external returns (uint256 amount) {
        // Calculate claimable amount
        amount = _getPendingFees(msg.sender, balanceOf(msg.sender));
        if (amount == 0) revert IPonderStaking.NoFeesToClaim();
        if (amount < PonderStakingTypes.MINIMUM_FEE_CLAIM) revert IPonderStaking.InsufficientFeeAmount();

        // Effects - Update fee debt
        userFeeDebt[msg.sender] = (balanceOf(msg.sender) * accumulatedFeesPerShare)
            / PonderStakingTypes.FEE_PRECISION;
        totalUnclaimedFees -= amount;

        emit FeesClaimed(msg.sender, amount);

        // Interactions
        PONDER.safeTransfer(msg.sender, amount);
    }

    /// @notice Distributes accumulated protocol fees
    /// @dev Updates share price based on current PONDER balance
    function rebase() external {
        if (block.timestamp < lastRebaseTime + PonderStakingTypes.REBASE_DELAY)
            revert IPonderStaking.RebaseTooFrequent();

        uint256 totalPonderBalance = PONDER.balanceOf(address(this));
        uint256 currentTotalShares = totalSupply();

        if (currentTotalShares > 0) {
            uint256 newFees = totalPonderBalance - totalUnclaimedFees - totalDepositedPonder;
            if (newFees > 0) {
                // Use e18 precision for fee calculations to match token decimals
                uint256 feesPerShare = (newFees * 1e18) / currentTotalShares;
                accumulatedFeesPerShare += feesPerShare;
                totalUnclaimedFees += newFees;
                emit FeesDistributed(newFees, accumulatedFeesPerShare);
            }
        }

        lastRebaseTime = block.timestamp;
        emit RebasePerformed(currentTotalShares, totalPonderBalance);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets pending protocol fees for an address
    /// @param user Address to check pending fees for
    /// @return Amount of PONDER fees available to claim
    function getPendingFees(address user) external view returns (uint256) {
        return _getPendingFees(user, balanceOf(user));
    }

    /// @notice Gets accumulated fees per share
    /// @return Current accumulated fees per share value
    function getAccumulatedFeesPerShare() external view returns (uint256) {
        return accumulatedFeesPerShare;
    }

    /// @notice Calculates PONDER tokens for xPONDER amount
    /// @param shares Amount of xPONDER to calculate for
    /// @return Amount of PONDER tokens that would be received
    function getPonderAmount(uint256 shares) external view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return shares;
        return (shares * PONDER.balanceOf(address(this))) / totalShares;
    }

    /// @notice Calculates xPONDER shares for PONDER amount
    /// @param amount Amount of PONDER to calculate for
    /// @return Amount of xPONDER shares that would be minted
    function getSharesAmount(uint256 amount) external view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return amount;
        return (amount * totalShares) / PONDER.balanceOf(address(this));
    }

    /// @notice Returns minimum PONDER required for first stake
    /// @return Minimum amount in PONDER tokens
    function minimumFirstStake() external pure returns (uint256) {
        return PonderStakingTypes.MINIMUM_FIRST_STAKE;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates pending fees for a user
    /// @param user Address to calculate fees for
    /// @param shares Amount of shares to calculate fees for
    /// @return Pending fees for the user
    function _getPendingFees(address user, uint256 shares) internal view returns (uint256) {
        if (shares == 0) return 0;

        uint256 accumulated = (shares * accumulatedFeesPerShare) / 1e18;
        uint256 debt = userFeeDebt[user];

        return accumulated > debt ? accumulated - debt : 0;
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates two-step ownership transfer
    /// @param newOwner Address of proposed new owner
    function transferOwnership(address newOwner) public override(IPonderStaking, PonderKAP20) onlyOwner {
        if (newOwner == address(0)) revert PonderKAP20.ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(stakingOwner, newOwner);
    }

    /// @notice Completes ownership transfer process
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert IPonderStaking.NotPendingOwner();
        address oldOwner = stakingOwner;
        stakingOwner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, stakingOwner);
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to contract owner
    modifier onlyOwner() override {
        if (msg.sender != stakingOwner) revert PonderKAP20.NotOwner();
        _;
    }
}
