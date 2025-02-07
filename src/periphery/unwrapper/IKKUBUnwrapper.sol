// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    KKUB UNWRAPPER INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IKKUBUnwrapper
/// @author Original author: [Insert author name]
/// @notice Interface defining functionality for unwrapping KKUB tokens to ETH
/// @dev This interface outlines core unwrapping operations and administrative functions
///      All amounts are handled in wei (1e18) precision
///      Implements emergency controls and rate limiting for safety
interface IKKUBUnwrapper {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when KKUB tokens are successfully unwrapped to ETH
    /// @dev Logs both recipient and amount for transaction tracking
    /// @param recipient Address receiving the unwrapped ETH
    /// @param amount Amount of KKUB unwrapped, in wei (1e18)
    event UnwrappedKKUB(address indexed recipient, uint256 amount);

    /// @notice Emitted during emergency ETH withdrawal
    /// @dev Provides audit trail for emergency operations
    /// @param amount Amount of ETH withdrawn, in wei (1e18)
    /// @param timestamp Block timestamp when withdrawal occurred
    event EmergencyWithdraw(uint256 amount, uint256 timestamp);

    /// @notice Emitted when withdrawal rate limit period is reset
    /// @dev Used for monitoring rate limit adjustments
    event WithdrawalLimitReset();

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the address of the KKUB token contract
    /// @dev This address is immutable after contract deployment
    /// @return Address of the KKUB ERC20 token contract
    function kkub() external view returns (address);

    /// @notice Gets the amount of ETH currently locked in pending unwrap operations
    /// @dev Used to track ETH reserved for ongoing unwrapping processes
    /// @return Current locked ETH balance in wei (1e18)
    function getLockedBalance() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Core function to unwrap KKUB tokens to ETH
    /// @dev Requires prior approval of KKUB tokens
    /// @dev Emits UnwrappedKKUB event on success
    /// @param amount Amount of KKUB to unwrap, in wei (1e18)
    /// @param recipient Destination address for unwrapped ETH
    /// @return success True if unwrapping succeeds, false otherwise
    function unwrapKKUB(uint256 amount, address recipient) external returns (bool);

    /*//////////////////////////////////////////////////////////////
                    ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency function to withdraw excess ETH from contract
    /// @dev Restricted to admin/owner
    /// @dev Emits EmergencyWithdraw event
    function emergencyWithdraw() external;

    /// @notice Resets the withdrawal rate limit counter
    /// @dev Restricted to admin/owner
    /// @dev Emits WithdrawalLimitReset event
    function resetWithdrawalLimit() external;

    /// @notice Pauses all unwrapping operations
    /// @dev Restricted to admin/owner
    /// @dev Critical for emergency response
    function pause() external;

    /// @notice Resumes unwrapping operations after pause
    /// @dev Restricted to admin/owner
    /// @dev Reverts contract to normal operation state
    function unpause() external;
}
