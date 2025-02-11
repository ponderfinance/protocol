// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderStaking } from "./IPonderStaking.sol";
import { IPonderToken } from "../token/IPonderToken.sol";

import { PonderStakingStorage } from "./storage/PonderStakingStorage.sol";
import { PonderStakingTypes } from "./types/PonderStakingTypes.sol";
import { PonderERC20 } from "../token/PonderERC20.sol";
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
contract PonderStaking is IPonderStaking, PonderStakingStorage, PonderERC20("Staked KOI", "xKOI") {
    /*//////////////////////////////////////////////////////////////
                            DEPENDENCIES
    //////////////////////////////////////////////////////////////*/
    using PonderStakingTypes for *;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                         IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice PONDER token contract reference
    /// @dev Immutable after deployment
    /// @dev Users stake this token to receive xPONDER
    IERC20 public immutable PONDER;

    /// @notice Protocol router for performing swaps
    /// @dev Immutable after deployment
    /// @dev Used for protocol fee collection and distribution
    IPonderRouter public immutable ROUTER;

    /// @notice Protocol factory contract reference
    /// @dev Immutable after deployment
    /// @dev Used for pair creation and management
    IPonderFactory public immutable FACTORY;

    /// @notice Initializes the staking contract
    /// @dev Sets up immutable contract references and initial state
    /// @param _ponder Address of PONDER token contract
    /// @param _router Address of protocol router
    /// @param _factory Address of protocol factory
    constructor(
        address _ponder,
        address _router,
        address _factory
    ) {
        if (_ponder == address(0) || _router == address(0) || _factory == address(0))
            revert PonderStakingTypes.ZeroAddress();

        PONDER = IERC20(_ponder);
        ROUTER = IPonderRouter(_router);
        FACTORY = IPonderFactory(_factory);
        owner = msg.sender;
        lastRebaseTime = block.timestamp;
        DEPLOYMENT_TIME = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
     //////////////////////////////////////////////////////////////*/

    /// @notice Returns minimum PONDER required for first stake
    /// @dev Constant value defined in PonderStakingTypes
    /// @return Minimum amount in PONDER tokens (18 decimals)
    function minimumFirstStake() external pure returns (uint256) {
        return PonderStakingTypes.MINIMUM_FIRST_STAKE;
    }

    /*//////////////////////////////////////////////////////////////
                       STAKING OPERATIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Stakes PONDER tokens for xPONDER shares
    /// @dev Mints shares proportional to current share price to msg.sender
    /// @dev First stake requires minimum amount and sets initial ratio
    /// @param amount Amount of PONDER to stake
    /// @param recipient Address to receive the xPONDER shares
    /// @return shares Amount of xPONDER shares minted
    function enter(uint256 amount, address recipient) external returns (uint256 shares) {
        // Checks
        if (amount == 0) revert PonderStakingTypes.InvalidAmount();
        if (recipient == address(0)) revert PonderStakingTypes.ZeroAddress();

        uint256 totalPonder = PONDER.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        // Calculate shares
        if (totalShares == 0) {
            if (amount < PonderStakingTypes.MINIMUM_FIRST_STAKE)
                revert PonderStakingTypes.InsufficientFirstStake();
            shares = amount;
        } else {
            shares = (amount * totalShares) / totalPonder;
        }

        // Effects
        _mint(recipient, shares);

        // Interactions
        PONDER.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(recipient, amount, shares);
    }


    /// @notice Withdraws PONDER by burning xPONDER shares
    /// @dev Burns shares and returns proportional PONDER amount
    /// @dev Enforces minimum withdrawal amount
    /// @param shares Amount of xPONDER to burn
    /// @return amount Amount of PONDER tokens returned
    function leave(uint256 shares) external returns (uint256 amount) {
        if (msg.sender == IPonderToken(address(PONDER)).teamReserve()) {
            if (block.timestamp < DEPLOYMENT_TIME + PonderStakingTypes.TEAM_LOCK_DURATION) {
                revert PonderStakingTypes.TeamStakingLocked();
            }
        }

        // Checks
        if (shares == 0) revert PonderStakingTypes.InvalidAmount();
        if (shares > balanceOf(msg.sender)) revert PonderStakingTypes.InvalidSharesAmount();

        uint256 totalShares = totalSupply();
        uint256 totalPonderBefore = PONDER.balanceOf(address(this));
        amount = (shares * totalPonderBefore) / totalShares;

        if (amount < PonderStakingTypes.MINIMUM_WITHDRAW)
            revert PonderStakingTypes.MinimumSharesRequired();

        // Effects
        _burn(msg.sender, shares);

        // Emit event before external interaction
        emit Withdrawn(msg.sender, amount, shares);

        PONDER.safeTransfer(msg.sender, amount);
    }

    /// @notice Distributes accumulated protocol fees
    /// @dev Updates share price based on current PONDER balance
    /// @dev Can only be called after REBASE_DELAY has passed
    function rebase() external {
        if (block.timestamp < lastRebaseTime + PonderStakingTypes.REBASE_DELAY)
            revert PonderStakingTypes.RebaseTooFrequent();

        uint256 totalPonderBalance = PONDER.balanceOf(address(this));
        lastRebaseTime = block.timestamp;

        emit RebasePerformed(totalSupply(), totalPonderBalance);
    }

    /*//////////////////////////////////////////////////////////////
                        CONVERSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates PONDER tokens for xPONDER amount
    /// @dev Uses current share price from total supply and balance
    /// @param shares Amount of xPONDER to calculate for
    /// @return Amount of PONDER tokens that would be received
    function getPonderAmount(uint256 shares) external view returns (uint256) {
        uint256 totalShares = totalSupply();

        // Strict equality required: Special case for initial stake
        // slither-disable-next-line dangerous-strict-equalities
        if (totalShares == 0) return shares;

        return (shares * PONDER.balanceOf(address(this))) / totalShares;
    }

    /// @notice Calculates xPONDER shares for PONDER amount
    /// @dev Uses current share price from total supply and balance
    /// @param amount Amount of PONDER to calculate for
    /// @return Amount of xPONDER shares that would be minted
    function getSharesAmount(uint256 amount) external view returns (uint256) {
        uint256 totalShares = totalSupply();

        // Strict equality required: Special case for initial stake
        // slither-disable-next-line dangerous-strict-equalities
        if (totalShares == 0) return amount;

        return (amount * totalShares) / PONDER.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates two-step ownership transfer
    /// @dev Sets pending owner, requires acceptance
    /// @param newOwner Address of proposed new owner
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert PonderStakingTypes.ZeroAddress();

        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }


    /// @notice Completes ownership transfer process
    /// @dev Can only be called by pending owner
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert PonderStakingTypes.NotPendingOwner();

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, owner);
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to contract owner
    /// @dev Reverts if caller is not current owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert PonderStakingTypes.NotOwner();
        _;
    }
}
