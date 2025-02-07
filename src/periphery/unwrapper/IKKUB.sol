// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    KKUB TOKEN INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IKKUB
/// @notice Interface for KUB Chain's wrapped KUB (KKUB) token
/// @dev Defines core KKUB functionality including wrapping,
///      unwrapping, transfers, and KYC verification
interface IKKUB {
    /*//////////////////////////////////////////////////////////////
                        WRAPPING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits native KUB for KKUB tokens
    /// @dev Wraps native KUB sent with transaction
    /// @dev Amount of KUB to wrap must be included in msg.value
    function deposit() external payable;

    /// @notice Withdraws native KUB by burning KKUB
    /// @dev Converts KKUB back to native KUB
    /// @param amount Quantity of KKUB to unwrap
    /// @dev Reverts if:
    ///      - Caller has insufficient balance
    ///      - Transfer of native KUB fails
    function withdraw(uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                        TOKEN OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers KKUB to another address
    /// @dev Standard ERC20 transfer
    /// @param to Recipient address
    /// @param value Amount of KKUB to transfer
    /// @return success True if transfer succeeds
    /// @dev Reverts if:
    ///      - Recipient is zero address
    ///      - Caller has insufficient balance
    function transfer(address to, uint256 value) external returns (bool success);

    /// @notice Transfers KKUB between addresses
    /// @dev Standard ERC20 transferFrom
    /// @param from Source address
    /// @param to Recipient address
    /// @param value Amount of KKUB to transfer
    /// @return success True if transfer succeeds
    /// @dev Reverts if:
    ///      - Caller has insufficient allowance
    ///      - Source has insufficient balance
    ///      - Recipient is zero address
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool success);

    /*//////////////////////////////////////////////////////////////
                        KYC VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks address blacklist status
    /// @dev Used for compliance verification
    /// @param addr Address to verify
    /// @return True if address is blacklisted
    function blacklist(address addr) external view returns (bool);

    /// @notice Retrieves address KYC level
    /// @dev Used for compliance verification
    /// @param addr Address to check
    /// @return KYC level of the address
    function kycsLevel(address addr) external view returns (uint256);
}
