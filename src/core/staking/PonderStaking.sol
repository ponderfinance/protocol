// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderStaking } from "./IPonderStaking.sol";
import { PonderStakingStorage } from "./storage/PonderStakingStorage.sol";
import { PonderStakingTypes } from "./types/PonderStakingTypes.sol";
import { PonderERC20 } from "../token/PonderERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";

/**
 * @title PonderStaking
 * @notice Implementation of PONDER staking with rebase mechanism
 * @dev Users stake PONDER and receive xPONDER, which rebases to capture protocol fees
 */
contract PonderStaking is IPonderStaking, PonderStakingStorage, PonderERC20("Staked Koi", "xKOI") {
    using PonderStakingTypes for *;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The PONDER token contract
    IERC20 public immutable PONDER;

    /// @notice Ponder protocol router for swaps
    IPonderRouter public immutable ROUTER;

    /// @notice Factory contract reference
    IPonderFactory public immutable FACTORY;

    /**
     * @notice Contract constructor
     * @param _ponder Address of the PONDER token contract
     * @param _router Address of the PonderRouter contract
     * @param _factory Address of the PonderFactory contract
     */
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
    }

    /**
 * @inheritdoc IPonderStaking
 */
    function minimumFirstStake() external pure returns (uint256) {
        return PonderStakingTypes.MINIMUM_FIRST_STAKE;
    }

    /**
     * @inheritdoc IPonderStaking
     */
    function enter(uint256 amount) external returns (uint256 shares) {
        // Checks
        if (amount == 0) revert PonderStakingTypes.InvalidAmount();
        uint256 totalPonder = PONDER.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        // Calculate shares
        // Strict equality required: Special case for initial stake
        // slither-disable-next-line dangerous-strict-equalities
        if (totalShares == 0) {
            if (amount < PonderStakingTypes.MINIMUM_FIRST_STAKE)
                revert PonderStakingTypes.InsufficientFirstStake();
            shares = amount;
        } else {
            shares = (amount * totalShares) / totalPonder;
        }

        // Effects
        _mint(msg.sender, shares);

        // Interactions
        PONDER.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, shares);
    }


    /**
     * @inheritdoc IPonderStaking
     */
    function leave(uint256 shares) external returns (uint256 amount) {
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

    /**
     * @inheritdoc IPonderStaking
     */
    function rebase() external {
        if (block.timestamp < lastRebaseTime + PonderStakingTypes.REBASE_DELAY)
            revert PonderStakingTypes.RebaseTooFrequent();

        uint256 totalPonderBalance = PONDER.balanceOf(address(this));
        lastRebaseTime = block.timestamp;

        emit RebasePerformed(totalSupply(), totalPonderBalance);
    }

    /**
     * @inheritdoc IPonderStaking
     */
    function getPonderAmount(uint256 shares) external view returns (uint256) {
        uint256 totalShares = totalSupply();

        // Strict equality required: Special case for initial stake
        // slither-disable-next-line dangerous-strict-equalities
        if (totalShares == 0) return shares;

        return (shares * PONDER.balanceOf(address(this))) / totalShares;
    }

    /**
     * @inheritdoc IPonderStaking
     */
    function getSharesAmount(uint256 amount) external view returns (uint256) {
        uint256 totalShares = totalSupply();

        // Strict equality required: Special case for initial stake
        // slither-disable-next-line dangerous-strict-equalities
        if (totalShares == 0) return amount;

        return (amount * totalShares) / PONDER.balanceOf(address(this));
    }

    /**
     * @inheritdoc IPonderStaking
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert PonderStakingTypes.ZeroAddress();

        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    /**
     * @inheritdoc IPonderStaking
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert PonderStakingTypes.NotPendingOwner();

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, owner);
    }

    /// @notice Modifier for owner-only functions
    modifier onlyOwner() {
        if (msg.sender != owner) revert PonderStakingTypes.NotOwner();
        _;
    }
}
