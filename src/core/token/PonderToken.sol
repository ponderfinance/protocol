// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderERC20 } from "./PonderERC20.sol";
import { PonderTokenStorage } from "./storage/PonderTokenStorage.sol";
import { IPonderToken } from "./IPonderToken.sol";
import { PonderTokenTypes } from "./types/PonderTokenTypes.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER TOKEN CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title PonderToken
/// @author taayyohh
/// @notice Main implementation of Ponder protocol's token
/// @dev ERC20 token with team vesting and governance features
///      Manages token distribution, vesting, and access control
contract PonderToken is PonderERC20, PonderTokenStorage, IPonderToken {
    using PonderTokenTypes for *;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Contract deployment timestamp
    /// @dev Used for vesting and minting calculations
    /// @dev Immutable to prevent manipulation
    uint256 private immutable _DEPLOYMENT_TIME;


    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys and initializes the token contract
    /// @dev Sets up initial allocations and vesting schedule
    /// @param teamReserveAddr Recipient of team allocation
    /// @param marketingAddr Recipient of marketing allocation
    /// @param launcherAddr Protocol launcher address
    /// @custom:security Launcher can be zero address initially
    constructor(
        address teamReserveAddr,
        address marketingAddr,
        address launcherAddr
    ) PonderERC20("Koi", "KOI") {
        if (teamReserveAddr == address(0) || marketingAddr == address(0)) {
            revert PonderTokenTypes.ZeroAddress();
        }
        // Launcher is intentionally allowed to be zero address in constructor
        // slither-disable-next-line missing-zero-check
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

    /*//////////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates currently vested team tokens
    /// @dev Linear vesting over VESTING_DURATION
    /// @dev Accounts for already claimed tokens
    /// @return Amount of tokens currently available to claim
    function _calculateVestedAmount() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - _teamVestingStart;
        if (timeElapsed > PonderTokenTypes.VESTING_DURATION) {
            timeElapsed = PonderTokenTypes.VESTING_DURATION;
        }

        uint256 totalVested = (PonderTokenTypes.TEAM_ALLOCATION * timeElapsed) / PonderTokenTypes.VESTING_DURATION;
        return totalVested > _teamTokensClaimed ? totalVested - _teamTokensClaimed : 0;
    }

    /*//////////////////////////////////////////////////////////////
                       TOKEN OPERATIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Claims vested team tokens
    /// @dev Only callable by team reserve address
    /// @dev Mints tokens according to vesting schedule
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

    /// @notice Mints new tokens to specified address
    /// @dev Only callable by minter before MINTING_END
    /// @dev Enforces maximum supply constraint
    /// @param to Address to receive minted tokens
    /// @param amount Quantity of tokens to mint
    /// @dev Reverts if minting period ended or supply cap reached
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

    /// @notice Burns tokens from caller's balance
    /// @dev Only callable by launcher or owner
    /// @dev Has minimum and maximum burn constraints
    /// @param amount Quantity of tokens to burn
    /// @dev Reverts if amount < 1000 or > 1% of total supply
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


    /*//////////////////////////////////////////////////////////////
                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates minting privileges
    /// @dev Restricted to owner
    /// @dev Cannot be zero address
    /// @param minter_ New address to receive minting rights
    /// @dev Emits MinterUpdated event
    function setMinter(address minter_) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (minter_ == address(0)) revert PonderTokenTypes.ZeroAddress();

        address oldMinter = _minter;
        _minter = minter_;
        emit PonderTokenTypes.MinterUpdated(oldMinter, minter_);
    }

    /// @notice Updates launcher address
    /// @dev Restricted to owner
    /// @dev Cannot be zero address
    /// @param launcher_ New launcher address
    /// @dev Emits LauncherUpdated event
    function setLauncher(address launcher_) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (launcher_ == address(0)) revert PonderTokenTypes.ZeroAddress();

        address oldLauncher = _launcher;
        _launcher = launcher_;
        emit PonderTokenTypes.LauncherUpdated(oldLauncher, launcher_);
    }

    /// @notice Initiates ownership transfer
    /// @dev First step of two-step ownership transfer
    /// @dev Sets pending owner for acceptance
    /// @param newOwner Address to receive ownership
    /// @dev Emits OwnershipTransferStarted event
    function transferOwnership(address newOwner) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (newOwner == address(0)) revert PonderTokenTypes.ZeroAddress();

        _pendingOwner = newOwner;
        emit PonderTokenTypes.OwnershipTransferStarted(_owner, newOwner);
    }

    /// @notice Completes ownership transfer
    /// @dev Second step of two-step transfer
    /// @dev Only callable by pending owner
    function acceptOwnership() external {
        if (msg.sender != _pendingOwner) revert PonderTokenTypes.Forbidden();

        address oldOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);
        emit PonderTokenTypes.OwnershipTransferred(oldOwner, _owner);
    }


    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS - STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current minter address
    /// @return Address with minting privileges
    function minter() external view returns (address) {
        return _minter;
    }

    /// @notice Current owner address
    /// @return Address with admin privileges
    function owner() external view returns (address) {
        return _owner;
    }

    /// @notice Address in ownership transfer
    /// @return Pending owner awaiting acceptance
    function pendingOwner() external view returns (address) {
        return _pendingOwner;
    }

    /// @notice Team allocation recipient
    /// @return Address receiving vested tokens
    function teamReserve() external view returns (address) {
        return _teamReserve;
    }

    /// @notice Marketing wallet address
    /// @return Address for marketing funds
    function marketing() external view returns (address) {
        return _marketing;
    }

    /// @notice Protocol launcher address
    /// @return Address with launcher privileges
    function launcher() external view returns (address) {
        return _launcher;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS - ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Total tokens burned
    /// @return Cumulative burned amount
    function totalBurned() external view returns (uint256) {
        return _totalBurned;
    }

    /// @notice Vested team tokens claimed
    /// @return Amount of claimed allocation
    function teamTokensClaimed() external view returns (uint256) {
        return _teamTokensClaimed;
    }

    /// @notice Team vesting start time
    /// @return Vesting schedule start
    function teamVestingStart() external view returns (uint256) {
        return _teamVestingStart;
    }

    /// @notice Contract deployment time
    /// @return Deployment timestamp
    function deploymentTime() external view returns (uint256) {
        return _DEPLOYMENT_TIME;
    }

    /// @notice Remaining team allocation
    /// @return Unclaimed team tokens
    function getReservedForTeam() external view returns (uint256) {
        return _reservedForTeam;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS - CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum token supply
    /// @return Total supply cap
    function maximumSupply() external pure returns (uint256) {
        return PonderTokenTypes.MAXIMUM_SUPPLY;
    }

    /// @notice Minting period duration
    /// @return Time until minting disabled
    function mintingEnd() external pure returns (uint256) {
        return PonderTokenTypes.MINTING_END;
    }

    /// @notice Total team allocation
    /// @return Team token amount
    function teamAllocation() external pure returns (uint256) {
        return PonderTokenTypes.TEAM_ALLOCATION;
    }

    /// @notice Vesting schedule length
    /// @return Vesting duration
    function vestingDuration() external pure returns (uint256) {
        return PonderTokenTypes.VESTING_DURATION;
    }
}
