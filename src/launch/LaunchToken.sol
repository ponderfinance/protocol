// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/PonderERC20.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderRouter.sol";
import "../interfaces/IERC20.sol";
import "../core/PonderToken.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract LaunchToken is PonderERC20, ReentrancyGuard {
    /// @notice Core protocol addresses
    address public launcher;
    address public pendingLauncher;
    IPonderFactory public immutable factory;
    IPonderRouter public immutable router;
    PonderToken public immutable ponder;

    /// @notice Trading state
    bool public transfersEnabled;

    /// @notice Creator vesting configuration
    address public creator;
    uint256 public vestingStart;
    uint256 public vestingEnd;
    uint256 public totalVestedAmount;
    uint256 public vestedClaimed;
    uint256 public lastClaimTime;

    /// @notice Pool addresses
    address public kubPair;      // Primary KUB pair
    address public ponderPair;   // Secondary PONDER pair

    /// @notice Protocol constants
    uint256 public constant TOTAL_SUPPLY = 555_555_555 ether;
    uint256 public constant VESTING_DURATION = 180 days;
    uint256 public constant MIN_CLAIM_INTERVAL = 1 hours;

    /// @notice Vesting initialization status
    bool private _vestingInitialized;

    /// @notice Custom errors
    error TransfersDisabled();
    error Unauthorized();
    error InsufficientAllowance();
    error NoTokensAvailable();
    error VestingNotStarted();
    error VestingNotInitialized();
    error VestingAlreadyInitialized();
    error InvalidCreator();
    error InvalidAmount();
    error ExcessiveAmount();
    error InsufficientLauncherBalance();
    error PairAlreadySet();
    error ClaimTooFrequent();
    error ZeroAddress();
    error NotPendingLauncher();

    /// @notice Events
    event VestingInitialized(address indexed creator, uint256 amount, uint256 startTime, uint256 endTime);
    event TokensClaimed(address indexed creator, uint256 amount);
    event TransfersEnabled();
    event PairsSet(address kubPair, address ponderPair);
    event NewPendingLauncher(address indexed previousPending, address indexed newPending);
    event LauncherTransferred(address indexed previousLauncher, address indexed newLauncher);


    constructor(
        string memory _name,
        string memory _symbol,
        address _launcher,
        address _factory,
        address payable _router,
        address _ponder
    ) PonderERC20(_name, _symbol) {
        if (_launcher == address(0)) revert ZeroAddress();
        launcher = _launcher;
        factory = IPonderFactory(_factory);
        router = IPonderRouter(_router);
        ponder = PonderToken(_ponder);
        _mint(_launcher, TOTAL_SUPPLY);
    }

    function setupVesting(address _creator, uint256 _amount) external {
        // Authorization check
        if (msg.sender != launcher) revert Unauthorized();

        // State checks
        if (_vestingInitialized) revert VestingAlreadyInitialized();
        if (_creator == address(0)) revert InvalidCreator();
        if (_amount == 0) revert InvalidAmount();

        // Amount validation - check total supply first
        if (_amount > TOTAL_SUPPLY) revert ExcessiveAmount();
        if (_amount > balanceOf(launcher)) revert InsufficientLauncherBalance();

        // State updates
        creator = _creator;
        totalVestedAmount = _amount;
        vestingStart = block.timestamp;
        vestingEnd = block.timestamp + VESTING_DURATION;

        // Set initialized flag last (CEI pattern)
        _vestingInitialized = true;

        emit VestingInitialized(_creator, _amount, vestingStart, vestingEnd);
    }

    function isVestingInitialized() external view returns (bool) {
        return _vestingInitialized;
    }

    function claimVestedTokens() external nonReentrant {
        if (!_vestingInitialized) revert VestingNotInitialized();
        if (msg.sender != creator) revert Unauthorized();
        if (block.timestamp < vestingStart) revert VestingNotStarted();
        if (block.timestamp < lastClaimTime + MIN_CLAIM_INTERVAL) revert ClaimTooFrequent();

        uint256 claimableAmount = _calculateVestedAmount();
        if (claimableAmount == 0) revert NoTokensAvailable();
        if (balanceOf(launcher) < claimableAmount) revert InsufficientLauncherBalance();

        // Update state before transfer (CEI pattern)
        lastClaimTime = block.timestamp;
        vestedClaimed += claimableAmount;

        // Perform transfer last
        _transfer(launcher, creator, claimableAmount);

        emit TokensClaimed(creator, claimableAmount);
    }

    function _calculateVestedAmount() internal view returns (uint256) {
        if (block.timestamp < vestingStart) return 0;

        // Calculate elapsed time with cap
        uint256 elapsed = block.timestamp - vestingStart;
        if (elapsed > VESTING_DURATION) {
            elapsed = VESTING_DURATION;
        }

        // Calculate linearly vested amount with high precision
        uint256 totalVestedNow = (totalVestedAmount * elapsed) / VESTING_DURATION;

        // If we've claimed this much or more, nothing to claim
        if (totalVestedNow <= vestedClaimed) return 0;

        // Calculate claimable amount
        uint256 claimable = totalVestedNow - vestedClaimed;

        // Final safety check against remaining amount
        uint256 remaining = totalVestedAmount - vestedClaimed;
        return claimable > remaining ? remaining : claimable;
    }

    function isLaunchToken() external pure returns (bool) {
        return true;
    }

    function setPairs(address _kubPair, address _ponderPair) external {
        if (msg.sender != launcher) revert Unauthorized();
        if (kubPair != address(0) || ponderPair != address(0)) revert PairAlreadySet();
        kubPair = _kubPair;
        ponderPair = _ponderPair;
        emit PairsSet(_kubPair, _ponderPair);
    }

    function enableTransfers() external {
        if (msg.sender != launcher) revert Unauthorized();
        transfersEnabled = true;
        emit TransfersEnabled();
    }


    function transfer(address to, uint256 value) external override returns (bool) {
        // Allow transfers if:
        // 1. Transfers are enabled, OR
        // 2. Sender is launcher, OR
        // 3. Recipient is launcher (for refunds)
        if (!transfersEnabled && msg.sender != launcher && to != launcher) {
            revert TransfersDisabled();
        }
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        // Allow transfers if:
        // 1. Transfers are enabled, OR
        // 2. From is launcher, OR
        // 3. Recipient is launcher (for refunds)
        if (!transfersEnabled && from != launcher && to != launcher) {
            revert TransfersDisabled();
        }

        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            _approve(from, msg.sender, currentAllowance - value);
        }

        _transfer(from, to, value);
        return true;
    }

    /// @notice Initiates transfer of launcher role to a new address
    /// @param newLauncher The address that will become the new launcher
    function transferLauncher(address newLauncher) external {
        if (msg.sender != launcher) revert Unauthorized();
        if (newLauncher == address(0)) revert ZeroAddress();

        address oldPending = pendingLauncher;
        pendingLauncher = newLauncher;

        emit NewPendingLauncher(oldPending, newLauncher);
    }

    /// @notice Accepts the launcher role
    /// @dev Can only be called by pendingLauncher
    function acceptLauncher() external {
        if (msg.sender != pendingLauncher) revert NotPendingLauncher();

        address oldLauncher = launcher;
        address newLauncher = msg.sender;

        // Update state first
        launcher = newLauncher;
        pendingLauncher = address(0);

        // Transfer any remaining balance to new launcher
        uint256 remainingBalance = balanceOf(oldLauncher);
        if (remainingBalance > 0) {
            _transfer(oldLauncher, newLauncher, remainingBalance);
        }

        emit LauncherTransferred(oldLauncher, newLauncher);
    }

    function getVestingInfo() external view returns (
        uint256 total,
        uint256 claimed,
        uint256 available,
        uint256 start,
        uint256 end
    ) {
        return (
            totalVestedAmount,
            vestedClaimed,
            _calculateVestedAmount(),
            vestingStart,
            vestingEnd
        );
    }

}
