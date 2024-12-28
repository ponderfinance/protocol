// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/PonderERC20.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderRouter.sol";
import "../interfaces/IERC20.sol";
import "../core/PonderToken.sol";

contract LaunchToken is PonderERC20 {
    /// @notice Core protocol addresses
    address public immutable launcher;
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

    /// @notice Pool addresses
    address public kubPair;      // Primary KUB pair
    address public ponderPair;   // Secondary PONDER pair

    /// @notice Protocol constants
    uint256 public constant TOTAL_SUPPLY = 555_555_555 ether;
    uint256 public constant VESTING_DURATION = 180 days;

    /// @notice Fee constants (used by PonderPair)
    uint256 public constant FEE_DENOMINATOR = 10000;

    // KUB pair fees (0.3% total)
    uint256 public constant KUB_PROTOCOL_FEE = 20;   // 0.2% to protocol
    uint256 public constant KUB_CREATOR_FEE = 10;    // 0.1% to creator

    // PONDER pair fees (0.3% total)
    uint256 public constant PONDER_PROTOCOL_FEE = 15;  // 0.15% to protocol
    uint256 public constant PONDER_CREATOR_FEE = 15;   // 0.15% to creator


    /// @notice Events
    event VestingInitialized(address indexed creator, uint256 amount, uint256 startTime, uint256 endTime);
    event TokensClaimed(address indexed creator, uint256 amount);
    event TransfersEnabled();
    event PairsSet(address kubPair, address ponderPair);

    /// @notice Custom errors
    error TransfersDisabled();
    error Unauthorized();
    error InsufficientAllowance();
    error NoTokensAvailable();
    error VestingNotStarted();
    error PairAlreadySet();

    constructor(
        string memory _name,
        string memory _symbol,
        address _launcher,
        address _factory,
        address payable _router,
        address _ponder
    ) PonderERC20(_name, _symbol) {
        launcher = _launcher;
        factory = IPonderFactory(_factory);
        router = IPonderRouter(_router);
        ponder = PonderToken(_ponder);

        // Mint entire supply to launcher
        _mint(_launcher, TOTAL_SUPPLY);
    }

    function isLaunchToken() external pure returns (bool) {
        return true;
    }

    function setupVesting(address _creator, uint256 _amount) external {
        if (msg.sender != launcher) revert Unauthorized();
        creator = _creator;
        totalVestedAmount = _amount;
        vestingStart = block.timestamp;
        vestingEnd = block.timestamp + VESTING_DURATION;
        emit VestingInitialized(_creator, _amount, vestingStart, vestingEnd);
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

    function claimVestedTokens() external {
        if (msg.sender != creator) revert Unauthorized();
        if (block.timestamp < vestingStart) revert VestingNotStarted();

        uint256 vestedAmount = _calculateVestedAmount();
        if (vestedAmount == 0) revert NoTokensAvailable();

        vestedClaimed += vestedAmount;
        _transfer(launcher, creator, vestedAmount);

        emit TokensClaimed(creator, vestedAmount);
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

    function _calculateVestedAmount() internal view returns (uint256) {
        if (block.timestamp < vestingStart) return 0;

        uint256 elapsed = block.timestamp - vestingStart;
        if (elapsed > VESTING_DURATION) {
            elapsed = VESTING_DURATION;
        }

        uint256 vestedAmount = (totalVestedAmount * elapsed) / VESTING_DURATION;
        if (vestedAmount <= vestedClaimed) return 0;

        return vestedAmount - vestedClaimed;
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
