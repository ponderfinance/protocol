// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IWETH } from "./IWETH.sol";
import { IKKUB } from "./IKKUB.sol";
import { KKUBUnwrapperTypes } from "./types/KKUBUnwrapperTypes.sol";
import { KKUBUnwrapperStorage } from "./storage/KKUBUnwrapperStorage.sol";
import { IKKUBUnwrapper } from "./IKKUBUnwrapper.sol";

contract KKUBUnwrapper is
    IKKUBUnwrapper,
    KKUBUnwrapperStorage,
    ReentrancyGuard,
    Pausable,
    Ownable2Step
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public immutable KKUB;

    constructor(address _kkub) Ownable(msg.sender) {
        if (_kkub == address(0)) revert KKUBUnwrapperTypes.ZeroAddressNotAllowed();
        KKUB = _kkub;
    }


    /// @notice Get the KKUB token address
    /// @return Address of the KKUB token contract
    function kkub() external view returns (address) {
        return KKUB;
    }


    function transferOwnership(address newOwner) public virtual override(Ownable2Step) {
        if (newOwner == address(0)) revert KKUBUnwrapperTypes.InvalidNewOwner();
        super.transferOwnership(newOwner);
    }

    /// @inheritdoc IKKUBUnwrapper
    function getLockedBalance() external view override returns (uint256) {
        return _lockedBalance;
    }

    /// @inheritdoc IKKUBUnwrapper
    function unwrapKKUB(
        uint256 amount,
        address recipient
    ) external override nonReentrant whenNotPaused returns (bool) {
        // Checks
        if (amount == 0) revert KKUBUnwrapperTypes.ZeroAmount();
        if (recipient == address(0)) revert KKUBUnwrapperTypes.ZeroAddressNotAllowed();

        // Validate KYC and blacklist status
        if (IKKUB(KKUB).kycsLevel(address(this)) <= KKUBUnwrapperTypes.REQUIRED_KYC_LEVEL) {
            revert KKUBUnwrapperTypes.InsufficientKYCLevel();
        }
        if (IKKUB(KKUB).blacklist(recipient)) {
            revert KKUBUnwrapperTypes.BlacklistedAddress();
        }

        // Effects
        _lockedBalance += amount;

        // Interactions
        uint256 initialBalance = address(this).balance;

        // 1. Transfer KKUB tokens
        IERC20(KKUB).safeTransferFrom(msg.sender, address(this), amount);

        // 2. Withdraw from KKUB contract
        IWETH(KKUB).withdraw(amount);

        // Verify withdrawal success
        uint256 ethReceived = address(this).balance - initialBalance;
        if (ethReceived < amount) {
            _lockedBalance -= amount;
            revert KKUBUnwrapperTypes.WithdrawFailed();
        }

        // 3. Transfer ETH to recipient
        // sendValue will revert on failure, no need for additional error handling
        payable(recipient).sendValue(amount);

        _lockedBalance -= amount;
        emit UnwrappedKKUB(recipient, amount);
        return true;
    }


    /// @inheritdoc IKKUBUnwrapper
    function emergencyWithdraw()
    external
    override
    onlyOwner
    nonReentrant
    {
        if (block.timestamp < lastWithdrawalTime + KKUBUnwrapperTypes.WITHDRAWAL_DELAY) {
            revert KKUBUnwrapperTypes.WithdrawalTooFrequent();
        }

        uint256 withdrawableAmount = address(this).balance - _lockedBalance;
        if (withdrawableAmount == 0) revert KKUBUnwrapperTypes.InsufficientBalance();

        if (withdrawableAmount > KKUBUnwrapperTypes.MAX_WITHDRAWAL_AMOUNT) {
            withdrawableAmount = KKUBUnwrapperTypes.MAX_WITHDRAWAL_AMOUNT;
        }

        // Update state before transfer
        lastWithdrawalTime = block.timestamp;
        if (!paused()) {
            _pause();
        }

        // Transfer withdrawable amount
        payable(owner()).sendValue(withdrawableAmount);

        emit EmergencyWithdraw(withdrawableAmount, block.timestamp);
    }

    /// @inheritdoc IKKUBUnwrapper
    function resetWithdrawalLimit() external override {
        if (block.timestamp >= lastWithdrawalTime + KKUBUnwrapperTypes.WITHDRAWAL_DELAY) {
            lastWithdrawalTime = 0;
            emit WithdrawalLimitReset();
        }
    }

    /// @inheritdoc IKKUBUnwrapper
    function pause() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IKKUBUnwrapper
    function unpause() external override onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
