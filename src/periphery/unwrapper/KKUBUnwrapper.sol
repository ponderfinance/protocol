// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IKKUB, IKYC } from "./IKKUB.sol";
import { KKUBUnwrapperTypes } from "./types/KKUBUnwrapperTypes.sol";
import { KKUBUnwrapperStorage } from "./storage/KKUBUnwrapperStorage.sol";
import { IKKUBUnwrapper } from "./IKKUBUnwrapper.sol";

/*//////////////////////////////////////////////////////////////
                    KKUB UNWRAPPER CONTRACT
//////////////////////////////////////////////////////////////*/

/// @title KKUBUnwrapper
/// @author taayyohh
/// @notice Facilitates unwrapping of KKUB tokens to native KUB
/// @dev Implements security measures including reentrancy guards,
///      pausability, and two-step ownership transfer
contract KKUBUnwrapper is
    IKKUBUnwrapper,
    KKUBUnwrapperStorage,
    ReentrancyGuard,
    Pausable,
    Ownable2Step
{
    /*//////////////////////////////////////////////////////////////
                            DEPENDENCIES
    //////////////////////////////////////////////////////////////*/

    using SafeERC20 for IERC20;
    using Address for address payable;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice KKUB token contract address
    /// @dev Immutable after deployment
    /// @dev KYC-enabled wrapped KUB token
    address public immutable KKUB;

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the unwrapper contract
    /// @dev Sets up KKUB reference and ownership
    /// @param _kkub Address of KKUB token contract
    constructor(address _kkub) Ownable(msg.sender) {
        if (_kkub == address(0)) revert IKKUBUnwrapper.ZeroAddressNotAllowed();
        KKUB = _kkub;
    }

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves KKUB token address
    /// @return Address of KKUB contract
    function kkub() external view returns (address) {
        return KKUB;
    }

    /// @notice Gets currently locked balance
    /// @return Amount of KUB locked in ongoing operations
    function getLockedBalance() external view override returns (uint256) {
        return _lockedBalance;
    }

    /*//////////////////////////////////////////////////////////////
                        UNWRAPPING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unwraps KKUB tokens to native KUB
    /// @dev Enforces KYC requirements and handles token conversions
    /// @param amount Amount of KKUB to unwrap
    /// @param recipient Address to receive native KUB
    /// @return success True if unwrapping succeeds
    /// @dev Follows CEI pattern and includes multiple security checks
    /// @dev Reverts if:
    ///      - Amount is zero
    ///      - Recipient is zero address
    ///      - Contract KYC level insufficient
    ///      - Recipient is blacklisted
    ///      - Withdrawal from KKUB contract fails
    function unwrapKKUB(
        uint256 amount,
        address recipient
    ) external override nonReentrant whenNotPaused returns (bool) {
        if (amount == 0) revert IKKUBUnwrapper.ZeroAmount();
        if (recipient == address(0)) revert IKKUBUnwrapper.ZeroAddressNotAllowed();

        IKYC kyc = IKKUB(KKUB).kyc();
        if (kyc.kycsLevel(address(this)) <= IKKUB(KKUB).kycsLevel()) {
            revert IKKUBUnwrapper.InsufficientKYCLevel();
        }

        if (IKKUB(KKUB).blacklist(recipient)) {
            revert IKKUBUnwrapper.BlacklistedAddress();
        }

        // Record initial state
        uint256 initialBalance = address(this).balance;

        // EFFECTS - Update all state variables first
        _lockedBalance += amount;

        // INTERACTIONS - External calls after state updates
        // Transfer KKUB tokens
        IERC20(KKUB).safeTransferFrom(msg.sender, address(this), amount);

        // Withdraw from KKUB contract
        IKKUB(KKUB).withdraw(amount);

        // Verify withdrawal success
        uint256 ethReceived = address(this).balance - initialBalance;
        if (ethReceived < amount) {
            revert IKKUBUnwrapper.WithdrawFailed();
        }

        // Update state after successful operations
        _lockedBalance -= amount;

        // Final transfer
        payable(recipient).sendValue(ethReceived);

        emit UnwrappedKKUB(recipient, amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates ownership transfer
    /// @dev Overrides to prevent zero address
    /// @param newOwner Address of proposed owner
    function transferOwnership(address newOwner) public virtual override(Ownable2Step) {
        if (newOwner == address(0)) revert IKKUBUnwrapper.InvalidNewOwner();
        super.transferOwnership(newOwner);
    }

    /// @notice Emergency withdrawal of excess KUB
    /// @dev Restricted to owner with time and amount limits
    /// @dev Automatically pauses contract
    /// @dev Reverts if:
    ///      - Called too soon after last withdrawal
    ///      - No balance available
    ///      - Transfer fails
    function emergencyWithdraw() external override onlyOwner nonReentrant {
        // - Only callable by owner
        // - Has maximum withdrawal amount limits
        // - Withdrawal delay is much longer than possible manipulation window
        // - Additional protections like pausable and nonReentrant are in place
        // slither-disable-next-line timestamp
        if (block.timestamp < lastWithdrawalTime + KKUBUnwrapperTypes.WITHDRAWAL_DELAY) {
            revert IKKUBUnwrapper.WithdrawalTooFrequent();
        }

        uint256 withdrawableAmount = address(this).balance - _lockedBalance;
        if (withdrawableAmount <= 0) revert IKKUBUnwrapper.InsufficientBalance();

        if (withdrawableAmount > KKUBUnwrapperTypes.MAX_WITHDRAWAL_AMOUNT) {
            withdrawableAmount = KKUBUnwrapperTypes.MAX_WITHDRAWAL_AMOUNT;
        }

        lastWithdrawalTime = block.timestamp;
        if (!paused()) {
            _pause();
        }

        payable(owner()).sendValue(withdrawableAmount);

        emit EmergencyWithdraw(withdrawableAmount, block.timestamp);
    }

    /// @notice Resets emergency withdrawal delay
    /// @dev Only after WITHDRAWAL_DELAY has passed
    /// @dev Emits WithdrawalLimitReset event
    function resetWithdrawalLimit() external override {
        // - Only resets delay after significant time has passed
        // - No direct economic impact from timing
        // - Additional function calls still require owner privileges
        // slither-disable-next-line block-timestamp
        if (block.timestamp >= lastWithdrawalTime + KKUBUnwrapperTypes.WITHDRAWAL_DELAY) {
            lastWithdrawalTime = 0;
            emit WithdrawalLimitReset();
        }
    }

    /// @notice Pauses contract operations
    /// @dev Only callable by owner
    function pause() external override onlyOwner {
        _pause();
    }

    /// @notice Unpauses contract operations
    /// @dev Only callable by owner
    function unpause() external override onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                      FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables contract to receive KUB
    /// @dev Required for KKUB unwrapping
    receive() external payable {}
}
