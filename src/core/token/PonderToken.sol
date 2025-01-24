// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { PonderERC20 } from "./PonderERC20.sol";
import { PonderTokenStorage } from "./storage/PonderTokenStorage.sol";
import { IPonderToken } from "./IPonderToken.sol";
import { PonderTokenTypes } from "./types/PonderTokenTypes.sol";

/**
 * @title PonderToken
 * @notice Implementation of the PonderToken contract
 * @dev Implements ERC20 token with team vesting and governance functionality
 */
contract PonderToken is PonderERC20, PonderTokenStorage, IPonderToken {
    using PonderTokenTypes for *;

    /// @notice Timestamp when token was deployed
    /// @dev Used as reference point for time-based calculations
    uint256 private immutable _DEPLOYMENT_TIME;

    /**
     * @notice Contract constructor
     * @param teamReserveAddr Address for team token allocation
     * @param marketingAddr Address for marketing allocation
     * @param launcherAddr Initial launcher address
     */
    constructor(
        address teamReserveAddr,
        address marketingAddr,
        address launcherAddr
    ) PonderERC20("Koi", "KOI") {
        if (teamReserveAddr == address(0) || marketingAddr == address(0)) {
            revert PonderTokenTypes.ZeroAddress();
        }

        _launcher = launcherAddr;
        _owner = msg.sender;
        _DEPLOYMENT_TIME = block.timestamp;
        _teamReserve = teamReserveAddr;
        _marketing = marketingAddr;
        _teamVestingStart = block.timestamp;
        _teamVestingEnd = block.timestamp + PonderTokenTypes.VESTING_DURATION;

        // Initialize reserved amount for team
        _reservedForTeam = PonderTokenTypes.TEAM_ALLOCATION;

        // Initial distributions
        _mint(_owner, 200_000_000e18);
        _mint(_marketing, 150_000_000e18);
    }

    /**
     * @notice Calculate currently vested amount of team tokens
     * @return Amount of tokens vested based on current timestamp
     */
    function _calculateVestedAmount() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - _teamVestingStart;
        if (timeElapsed > PonderTokenTypes.VESTING_DURATION) {
            timeElapsed = PonderTokenTypes.VESTING_DURATION;
        }

        uint256 totalVested = (PonderTokenTypes.TEAM_ALLOCATION * timeElapsed) / PonderTokenTypes.VESTING_DURATION;
        return totalVested > _teamTokensClaimed ? totalVested - _teamTokensClaimed : 0;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function claimTeamTokens() external {
        if (msg.sender != _teamReserve) revert PonderTokenTypes.Forbidden();
        if (block.timestamp < _teamVestingStart) revert PonderTokenTypes.VestingNotStarted();

        uint256 vestedAmount = _calculateVestedAmount();
        if (vestedAmount <= 0) revert PonderTokenTypes.NoTokensAvailable();

        _reservedForTeam -= vestedAmount;
        _teamTokensClaimed += vestedAmount;

        _mint(_teamReserve, vestedAmount);

        emit PonderTokenTypes.TeamTokensClaimed(vestedAmount);
    }

    /**
     * @inheritdoc IPonderToken
     */
    function mint(address to, uint256 amount) external {
        if (msg.sender != _minter) revert PonderTokenTypes.Forbidden();
        if (block.timestamp > _DEPLOYMENT_TIME + PonderTokenTypes.MINTING_END) {
            revert PonderTokenTypes.MintingDisabled();
        }
        if (totalSupply() + amount + _reservedForTeam > PonderTokenTypes.MAXIMUM_SUPPLY) {
            revert PonderTokenTypes.SupplyExceeded();
        }
        _mint(to, amount);
    }

    /**
     * @inheritdoc IPonderToken
     */
    function setMinter(address minter_) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (minter_ == address(0)) revert PonderTokenTypes.ZeroAddress();

        address oldMinter = _minter;
        _minter = minter_;
        emit PonderTokenTypes.MinterUpdated(oldMinter, minter_);
    }

    /**
     * @inheritdoc IPonderToken
     */
    function setLauncher(address launcher_) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (launcher_ == address(0)) revert PonderTokenTypes.ZeroAddress();

        address oldLauncher = _launcher;
        _launcher = launcher_;
        emit PonderTokenTypes.LauncherUpdated(oldLauncher, launcher_);
    }

    /**
     * @inheritdoc IPonderToken
     */
    function transferOwnership(address newOwner) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (newOwner == address(0)) revert PonderTokenTypes.ZeroAddress();

        _pendingOwner = newOwner;
        emit PonderTokenTypes.OwnershipTransferStarted(_owner, newOwner);
    }

    /**
     * @inheritdoc IPonderToken
     */
    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert PonderTokenTypes.Forbidden();

        address oldOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit PonderTokenTypes.OwnershipTransferred(oldOwner, _owner);
    }

    /**
     * @inheritdoc IPonderToken
     */
    function burn(uint256 amount) external {
        if (msg.sender != _launcher && msg.sender != _owner) {
            revert PonderTokenTypes.OnlyLauncherOrOwner();
        }
        if (amount < 1000) revert PonderTokenTypes.BurnAmountTooSmall();
        if (amount > totalSupply() / 100) revert PonderTokenTypes.BurnAmountTooLarge();
        if (balanceOf(msg.sender) < amount) revert PonderTokenTypes.InsufficientBalance();

        _burn(msg.sender, amount);
        _totalBurned += amount;

        emit PonderTokenTypes.TokensBurned(msg.sender, amount);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IPonderToken
     */
    function minter() external view returns (address) {
        return _minter;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function teamReserve() external view returns (address) {
        return _teamReserve;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function marketing() external view returns (address) {
        return _marketing;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function launcher() external view returns (address) {
        return _launcher;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function totalBurned() external view returns (uint256) {
        return _totalBurned;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function teamTokensClaimed() external view returns (uint256) {
        return _teamTokensClaimed;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function teamVestingStart() external view returns (uint256) {
        return _teamVestingStart;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function deploymentTime() external view returns (uint256) {
        return _DEPLOYMENT_TIME;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function getReservedForTeam() external view returns (uint256) {
        return _reservedForTeam;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function maximumSupply() external pure returns (uint256) {
        return PonderTokenTypes.MAXIMUM_SUPPLY;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function mintingEnd() external pure returns (uint256) {
        return PonderTokenTypes.MINTING_END;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function teamAllocation() external pure returns (uint256) {
        return PonderTokenTypes.TEAM_ALLOCATION;
    }

    /**
     * @inheritdoc IPonderToken
     */
    function vestingDuration() external pure returns (uint256) {
        return PonderTokenTypes.VESTING_DURATION;
    }
}
