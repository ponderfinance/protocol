// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderERC20 } from "./PonderERC20.sol";
import { PonderTokenStorage } from "./storage/PonderTokenStorage.sol";
import { IPonderToken } from "./IPonderToken.sol";
import { IPonderStaking } from "../staking/IPonderStaking.sol";
import { PonderTokenTypes } from "./types/PonderTokenTypes.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER TOKEN CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title PonderTokens
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

    /// @notice Flag for if team locked staking has been initialized
    bool private _stakingInitialized;


    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys and initializes the token contract
    /// @dev Sets up initial allocations and team staking
    /// @param teamReserve_ Recipient of team allocation
    /// @param launcher_ Protocol launcher address
    /// @param staking_ Ponder Staking contract
    /// @custom:security Team allocation is force-staked for 2 years
    constructor(
        address teamReserve_,
        address launcher_,
        address staking_
    ) PonderERC20("Koi", "KOI") {
        if (teamReserve_ == address(0)) {
            revert PonderTokenTypes.ZeroAddress();
        }

        // Set core contract parameters
        _owner = msg.sender;
        _DEPLOYMENT_TIME = block.timestamp;
        _teamReserve = teamReserve_;
        _launcher = launcher_;
        _staking = IPonderStaking(staking_);

        // Mint team allocation to this contract for force-staking
        _mint(address(this), PonderTokenTypes.TEAM_ALLOCATION);

        // Mint initial liquidity allocation to launcher for pool creation
        _mint(launcher_, PonderTokenTypes.INITIAL_LIQUIDITY);
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


    /// @notice Mints new tokens
    /// @dev Only callable by minter (MasterChef)
    /// @param to Address to receive minted tokens
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external {
        if (msg.sender != _minter) revert PonderTokenTypes.Forbidden();
        if (totalSupply() + amount > PonderTokenTypes.MAXIMUM_SUPPLY) revert PonderTokenTypes.SupplyExceeded();

        _mint(to, amount);
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

    /// @notice Initializes staking of team allocation
    /// @dev Can only be called once after staking contract is properly set
    function initializeStaking() external {
        // Ensure caller is owner
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        // Ensure not already initialized
        if (_stakingInitialized) revert PonderTokenTypes.AlreadyInitialized();
        // Ensure staking contract is set
        if (address(_staking) == address(0)) revert PonderTokenTypes.ZeroAddress();

        // Approve staking contract
        _approve(address(this), address(_staking), PonderTokenTypes.TEAM_ALLOCATION);

        // Enter staking with team allocation
        _staking.enter(PonderTokenTypes.TEAM_ALLOCATION, _teamReserve);

        _stakingInitialized = true;
    }

    /// @notice Sets the staking contract address
    /// @dev Can only be called once by owner to set the final staking address
    /// @dev Initial staking address must be address(1) to allow this update
    /// @param newStaking Address of the PonderStaking contract
    function setStaking(address newStaking) external {
        if (msg.sender != _owner) revert PonderTokenTypes.Forbidden();
        if (newStaking == address(0)) revert PonderTokenTypes.ZeroAddress();
        if (address(_staking) != address(1)) revert PonderTokenTypes.AlreadyInitialized();
        _staking = IPonderStaking(newStaking);
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

    /// @notice Contract deployment time
    /// @return Deployment timestamp
    function deploymentTime() external view returns (uint256) {
        return _DEPLOYMENT_TIME;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS - CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum token supply
    /// @return Total supply cap
    function maximumSupply() external pure returns (uint256) {
        return PonderTokenTypes.MAXIMUM_SUPPLY;
    }

    /// @notice Total team allocation
    /// @return Team token amount
    function teamAllocation() external pure returns (uint256) {
        return PonderTokenTypes.TEAM_ALLOCATION;
    }

    /// @notice Get the staking contract address
    /// @dev Override for public state variable to meet interface requirements
    /// @dev Converts IPonderStaking instance to address type
    /// @return Address of protocol's xKOI staking contract
    function staking() public view override returns (address) {
        return address(_staking);
    }
}
