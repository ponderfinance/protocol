// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    KYC INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IKYC
/// @notice Interface for KUB Chain's KYC verification system
/// @dev Used to check KYC levels of addresses
interface IKYC {
    /// @notice Retrieves the KYC level of a given address
    /// @param _addr Address to check KYC level for
    /// @return KYC level of the specified address
    /// @dev Higher number indicates higher KYC level
    function kycsLevel(address _addr) external view returns (uint256);
}

/*//////////////////////////////////////////////////////////////
                    KKUB TOKEN INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IKKUB
/// @notice Interface for KUB Chain's wrapped KUB (KKUB) token
/// @dev Defines core KKUB functionality including wrapping,
///      unwrapping, transfers, and KYC verification
interface IKKUB {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when tokens are transferred
    /// @param from Source address
    /// @param to Destination address
    /// @param value Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when an approval is set
    /// @param tokenOwner Token owner address
    /// @param spender Approved spender address
    /// @param value Amount of tokens approved
    event Approval(address indexed tokenOwner, address indexed spender, uint256 value);

    /// @notice Emitted when native KUB is deposited
    /// @param dst Destination address receiving KKUB
    /// @param value Amount of KUB deposited
    event Deposit(address indexed dst, uint256 value);

    /// @notice Emitted when KKUB is withdrawn
    /// @param src Source address withdrawing KKUB
    /// @param value Amount of KKUB withdrawn
    event Withdrawal(address indexed src, uint256 value);

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
    ///      - Caller has insufficient KYC level
    ///      - Transfer of native KUB fails
    function withdraw(uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                        TOKEN OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the total token supply
    /// @return Total number of tokens in existence
    function totalSupply() external view returns (uint256);

    /// @notice Gets the balance of a specific address
    /// @param tokenOwner Address to query balance for
    /// @return balance Token balance of the address
    function balanceOf(address tokenOwner) external view returns (uint256 balance);

    /// @notice Gets the allowance granted from owner to spender
    /// @param tokenOwner Address that owns the tokens
    /// @param spender Address approved to spend tokens
    /// @return remaining Number of tokens spender is allowed to transfer
    function allowance(address tokenOwner, address spender) external view returns (uint256 remaining);

    /// @notice Transfers KKUB to another address
    /// @dev Standard ERC20 transfer
    /// @param to Recipient address
    /// @param tokens Amount of KKUB to transfer
    /// @return success True if transfer succeeds
    /// @dev Reverts if:
    ///      - Recipient is blacklisted
    ///      - Caller is blacklisted
    ///      - Caller has insufficient balance
    function transfer(address to, uint256 tokens) external returns (bool success);

    /// @notice Approves an address to spend tokens
    /// @dev Standard ERC20 approve
    /// @param spender Address to approve
    /// @param tokens Amount of tokens to approve
    /// @return success True if approval succeeds
    /// @dev Reverts if:
    ///      - Caller is blacklisted
    ///      - Contract is paused
    function approve(address spender, uint256 tokens) external returns (bool success);

    /// @notice Transfers KKUB between addresses
    /// @dev Standard ERC20 transferFrom
    /// @param from Source address
    /// @param to Recipient address
    /// @param tokens Amount of KKUB to transfer
    /// @return success True if transfer succeeds
    /// @dev Reverts if:
    ///      - Source is blacklisted
    ///      - Recipient is blacklisted
    ///      - Caller has insufficient allowance
    ///      - Source has insufficient balance
    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) external returns (bool success);

    /*//////////////////////////////////////////////////////////////
                        KYC AND COMPLIANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks address blacklist status
    /// @dev Used for compliance verification
    /// @param addr Address to verify
    /// @return True if address is blacklisted
    function blacklist(address addr) external view returns (bool);

    /// @notice Gets the minimum required KYC level for operations
    /// @dev This is a state variable, not a function taking an address
    /// @return Minimum KYC level required (typically for withdrawals)
    function kycsLevel() external view returns (uint256);

    /// @notice Gets the reference to the KYC contract
    /// @dev Used to check KYC levels of addresses
    /// @return The KYC contract interface
    function kyc() external view returns (IKYC);

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the admin contract address
    /// @return Address of the admin asset contract
    function getOwner() external view returns (address);

    /// @notice Transfers tokens between accounts as admin
    /// @dev Only callable by super admin
    /// @param _from Source address
    /// @param _to Destination address
    /// @param _value Amount to transfer
    /// @return success True if transfer succeeds
    function adminTransfer(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);

    /// @notice Batch transfers tokens between multiple accounts
    /// @dev Only callable by super admin
    /// @param _from Array of source addresses
    /// @param _to Array of destination addresses
    /// @param _value Array of amounts to transfer
    /// @return success True if all transfers succeed
    function batchTransfer(
        address[] calldata _from,
        address[] calldata _to,
        uint256[] calldata _value
    ) external returns (bool success);
}
