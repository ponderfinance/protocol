// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ILaunchToken } from "./ILaunchToken.sol";
import { LaunchTokenTypes } from "./types/LaunchTokenTypes.sol";
import { IPonderFactory} from "../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../periphery/router/IPonderRouter.sol";
import { PonderToken } from "../core/token/PonderToken.sol";
import { PonderERC20 } from "../core/token/PonderERC20.sol";

/// @title LaunchToken
/// @notice Implements a token with vesting, trading restrictions, and fee mechanisms
/// @dev Inherits from PonderERC20 and implements ILaunchToken interface
contract LaunchToken is ILaunchToken, PonderERC20, ReentrancyGuard {
    using LaunchTokenTypes for *;

    /// @notice Core protocol immutable addresses
    IPonderFactory public immutable FACTORY;
    IPonderRouter public immutable ROUTER;
    PonderToken public immutable PONDER;

    /// @notice Protocol control addresses
    address public launcher;
    address public pendingLauncher;

    /// @notice Trading state
    bool public transfersEnabled;

    /// @notice Creator vesting configuration
    address public creator;
    uint256 public vestingStart;
    uint256 public vestingEnd;
    uint256 public totalVestedAmount;
    uint256 public vestedClaimed;
    uint256 public lastClaimTime;
    uint256 public tradingEnabledAt;
    uint256 public maxTxAmount;
    bool public tradingRestricted = true;

    /// @notice Pool addresses
    address public kubPair;      // Primary KUB pair
    address public ponderPair;   // Secondary PONDER pair

    /// @notice Vesting initialization status
    bool public vestingInitialized;

    /// @notice Initializes the launch token with core protocol addresses
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _launcher Address of initial launcher
    /// @param _factory Address of factory contract
    /// @param _router Address of router contract
    /// @param _ponder Address of PONDER token
    constructor(
        string memory _name,
        string memory _symbol,
        address _launcher,
        address _factory,
        address payable _router,
        address _ponder
    ) PonderERC20(_name, _symbol) {
        if (_launcher == address(0)) revert LaunchTokenTypes.ZeroAddress();
        if (_factory == address(0)) revert LaunchTokenTypes.ZeroAddress();
        if (_router == address(0)) revert LaunchTokenTypes.ZeroAddress();
        if (_ponder == address(0)) revert LaunchTokenTypes.ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = PonderToken(_ponder);
        launcher = _launcher;
        _mint(_launcher, LaunchTokenTypes.TOTAL_SUPPLY);
    }

    /// @notice Manages token transfers with trading restrictions and fee handling
    /// @dev Overrides PonderERC20._update
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Transfer amount
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // Skip checks for minting
        if (from == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // Skip checks for launcher operations during setup
        if ((from == launcher || to == launcher) && !transfersEnabled) {
            super._update(from, to, amount);
            return;
        }

        // Check if transfers are enabled for non-launcher operations
        if (!transfersEnabled) {
            revert LaunchTokenTypes.TransfersDisabled();
        }

        // Apply trading restrictions during initial period
        // - Trading restriction period is much longer than possible manipulation window
        // - Additional protections like maxTxAmount are in place
        // - Short-term manipulation doesn't significantly impact trading restrictions
        // slither-disable-next-line block-timestamp
        if (block.timestamp < tradingEnabledAt + LaunchTokenTypes.TRADING_RESTRICTION_PERIOD) {
            // Check max transaction amount
            if (amount > maxTxAmount) {
                revert LaunchTokenTypes.MaxTransferExceeded();
            }

            // Check for contracts trading in either direction
            if (to.code.length > 0 || from.code.length > 0) {
                // Check if this is our pair address
                if (to == kubPair || to == ponderPair ||
                from == kubPair || from == ponderPair) {
                    super._update(from, to, amount);
                    return;
                }

                // Check if this is a pair being created
                address kubPairCheck = FACTORY.getPair(address(this), address(ROUTER.kkub()));
                address ponderPairCheck = FACTORY.getPair(address(this), address(PONDER));

                if (to != address(ROUTER) &&
                to != address(FACTORY) &&
                to != kubPairCheck &&
                to != ponderPairCheck &&
                from != address(ROUTER) &&
                from != address(FACTORY) &&
                from != kubPairCheck &&
                    from != ponderPairCheck) {
                    revert LaunchTokenTypes.ContractBuyingRestricted();
                }
            }
        }

        super._update(from, to, amount);
    }

    /// @notice Sets up vesting schedule for token creator
    /// @param _creator Address of token creator
    /// @param _amount Amount of tokens to vest
    function setupVesting(address _creator, uint256 _amount) external {
        if (msg.sender != launcher) revert LaunchTokenTypes.Unauthorized();
        if (vestingInitialized) revert LaunchTokenTypes.VestingAlreadyInitialized();
        if (_creator == address(0)) revert LaunchTokenTypes.InvalidCreator();
        if (_amount == 0) revert LaunchTokenTypes.InvalidAmount();

        // Authorization check
        if (msg.sender != launcher) revert LaunchTokenTypes.Unauthorized();

        // State checks
        if (vestingInitialized) revert LaunchTokenTypes.VestingAlreadyInitialized();
        if (_creator == address(0)) revert LaunchTokenTypes.InvalidCreator();
        if (_amount == 0) revert LaunchTokenTypes.InvalidAmount();

        // Amount validation
        if (_amount > LaunchTokenTypes.TOTAL_SUPPLY) revert LaunchTokenTypes.ExcessiveAmount();
        if (_amount > balanceOf(launcher)) revert LaunchTokenTypes.InsufficientLauncherBalance();

        // State updates
        creator = _creator;
        totalVestedAmount = _amount;
        vestingStart = block.timestamp;
        vestingEnd = block.timestamp + LaunchTokenTypes.VESTING_DURATION;

        // Set initialized flag last (CEI pattern)
        vestingInitialized = true;

        emit VestingInitialized(_creator, _amount, vestingStart, vestingEnd);
    }

    /// @notice Returns vesting initialization status
    function isVestingInitialized() external view returns (bool) {
        return vestingInitialized;
    }

    /// @notice Allows creator to claim vested tokens
    function claimVestedTokens() external nonReentrant {
        if (!vestingInitialized) revert LaunchTokenTypes.VestingNotInitialized();
        if (msg.sender != creator) revert LaunchTokenTypes.Unauthorized();
        if (block.timestamp < vestingStart) revert LaunchTokenTypes.VestingNotStarted();
        if (block.timestamp < lastClaimTime + LaunchTokenTypes.MIN_CLAIM_INTERVAL) {
            revert LaunchTokenTypes.ClaimTooFrequent();
        }

        uint256 claimableAmount = _calculateVestedAmount();
        if (claimableAmount <= 0) revert LaunchTokenTypes.NoTokensAvailable();
        if (balanceOf(launcher) < claimableAmount) revert LaunchTokenTypes.InsufficientLauncherBalance();

        // Update state before transfer (CEI pattern)
        lastClaimTime = block.timestamp;
        vestedClaimed += claimableAmount;

        // Use internal _transfer
        _transfer(launcher, creator, claimableAmount);

        emit TokensClaimed(creator, claimableAmount);
    }

    /// @notice Calculates amount of tokens vested and available for claim
    /// @return Amount of tokens available to claim
    function _calculateVestedAmount() internal view returns (uint256) {
        if (block.timestamp < vestingStart) return 0;

        // Calculate elapsed time with cap
        uint256 elapsed = block.timestamp - vestingStart;
        if (elapsed > LaunchTokenTypes.VESTING_DURATION) {
            elapsed = LaunchTokenTypes.VESTING_DURATION;
        }

        // Calculate linearly vested amount with high precision
        uint256 totalVestedNow = (totalVestedAmount * elapsed) / LaunchTokenTypes.VESTING_DURATION;

        // If we've claimed this much or more, nothing to claim
        if (totalVestedNow <= vestedClaimed) return 0;

        // Calculate claimable amount
        uint256 claimable = totalVestedNow - vestedClaimed;

        // Final safety check against remaining amount
        uint256 remaining = totalVestedAmount - vestedClaimed;
        return claimable > remaining ? remaining : claimable;
    }

    /// @notice Verification function for launch token
    function isLaunchToken() external pure returns (bool) {
        return true;
    }

    /// @notice Sets the trading pairs for the token
    /// @param kubPair_ Address of the KUB pair
    /// @param ponderPair_ Address of the PONDER pair
    function setPairs(address kubPair_, address ponderPair_) external {
        if (msg.sender != launcher) revert LaunchTokenTypes.Unauthorized();
        if (kubPair != address(0) || ponderPair != address(0)) revert LaunchTokenTypes.PairAlreadySet();
        if (kubPair_ == address(0)) revert LaunchTokenTypes.ZeroAddress();

        kubPair = kubPair_;
        ponderPair = ponderPair_;

        emit PairsSet(kubPair_, ponderPair_);
    }

    /// @notice Enables token transfers and sets initial trading parameters
    function enableTransfers() external {
        if (msg.sender != launcher) revert LaunchTokenTypes.Unauthorized();

        transfersEnabled = true;
        tradingEnabledAt = block.timestamp;
        maxTxAmount = LaunchTokenTypes.TOTAL_SUPPLY / 200; // 0.5% max transaction limit

        emit TransfersEnabled();
    }

    /// @notice Sets the maximum transaction amount
    /// @param maxTxAmount_ New maximum transaction amount
    function setMaxTxAmount(uint256 maxTxAmount_) external {
        if (msg.sender != launcher) revert LaunchTokenTypes.Unauthorized();

        // - Restriction period is much longer than manipulation window
        // - Only callable by launcher address
        // - No direct economic impact from timing
        // slither-disable-next-line block-timestamp
        if (block.timestamp < tradingEnabledAt + LaunchTokenTypes.TRADING_RESTRICTION_PERIOD) {
            revert LaunchTokenTypes.TradingRestricted();
        }

        uint256 oldMaxTxAmount = maxTxAmount;
        maxTxAmount = maxTxAmount_;

        emit MaxTxAmountUpdated(oldMaxTxAmount, maxTxAmount_);
    }

    /// @notice Initiates launcher transfer process
    /// @param newLauncher Address of the new launcher
    function transferLauncher(address newLauncher) external {
        if (msg.sender != launcher) revert LaunchTokenTypes.Unauthorized();
        if (newLauncher == address(0)) revert LaunchTokenTypes.ZeroAddress();

        address oldPending = pendingLauncher;
        pendingLauncher = newLauncher;

        emit NewPendingLauncher(oldPending, newLauncher);
    }

    /// @notice Completes launcher transfer process
    /// @custom:security No zero-address check needed for pendingLauncher as it's validated in transferLauncher
    function acceptLauncher() external {
        if (msg.sender != pendingLauncher) revert LaunchTokenTypes.NotPendingLauncher();

        address oldLauncher = launcher;
        address newLauncher = msg.sender;

        // slither-disable-next-line missing-zero-check
        launcher = newLauncher;
        pendingLauncher = address(0); // Intentionally zeroing out

        // Transfer any remaining balance using internal _transfer
        uint256 remainingBalance = balanceOf(oldLauncher);
        if (remainingBalance > 0) {
            _transfer(oldLauncher, newLauncher, remainingBalance);
        }

        emit LauncherTransferred(oldLauncher, newLauncher);
    }

    /// @notice Returns current vesting information
    /// @return total Total amount being vested
    /// @return claimed Amount already claimed
    /// @return available Amount currently available to claim
    /// @return start Vesting start timestamp
    /// @return end Vesting end timestamp
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
