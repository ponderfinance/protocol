// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IKAP20 Interface
/// @notice Interface for the KAP20 standard on Bitkub Chain
/// @dev Extends the ERC20 standard with additional functions for KYC compliance and admin control
interface IKAP20 {
    /// @notice Admin function to set an allowance on behalf of an owner
    /// @param owner The address that will approve the allowance
    /// @param spender The address that will be able to spend the tokens
    /// @param amount The amount of tokens the spender can spend
    /// @return True if the admin approval was successful
    function adminApprove(address owner, address spender, uint256 amount) external returns (bool);

    /// @notice Admin function to transfer tokens between addresses
    /// @dev Only callable by authorized committee members
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the admin transfer was successful
    function adminTransfer(address sender, address recipient, uint256 amount) external returns (bool success);

    /// @notice Internal transfer function that requires both parties to have KYC
    /// @dev Only callable by super admin or transfer router
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the internal transfer was successful
    function internalTransfer(address sender, address recipient, uint256 amount) external returns (bool success);

    /// @notice External transfer function that requires sender to have KYC
    /// @dev Only callable by super admin or transfer router
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the external transfer was successful
    function externalTransfer(address sender, address recipient, uint256 amount) external returns (bool success);

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner Address of previous owner
    /// @param newOwner Address of new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice KYC service address update
    /// @param caller Address that updated the KYC service
    /// @param oldAddress Previous KYC service address
    /// @param newAddress New KYC service address
    event KYCBitkubChainSet(address indexed caller, address indexed oldAddress, address indexed newAddress);

    /// @notice Committee address update
    /// @param caller Address that updated the committee
    /// @param oldAddress Previous committee address
    /// @param newAddress New committee address
    event CommitteeSet(address indexed caller, address indexed oldAddress, address indexed newAddress);

    /// @notice Transfer router address update
    /// @param caller Address that updated the transfer router
    /// @param oldAddress Previous transfer router address
    /// @param newAddress New transfer router address
    event TransferRouterSet(address indexed caller, address indexed oldAddress, address indexed newAddress);

    /// @notice Admin project router address update
    /// @param caller Address that updated the admin project router
    /// @param oldAddress Previous admin project router address
    /// @param newAddress New admin project router address
    event AdminProjectRouterSet(address indexed caller, address indexed oldAddress, address indexed newAddress);

    /// @notice Accepted KYC level update
    /// @param caller Address that updated the KYC level
    /// @param oldKYCLevel Previous KYC level
    /// @param newKYCLevel New KYC level
    event AcceptedKYCLevelSet(address indexed caller, uint256 oldKYCLevel, uint256 newKYCLevel);

    /// @notice KYC enforcement activation
    /// @param caller Address that activated KYC enforcement
    event ActivateOnlyKYCAddress(address indexed caller);

    /// @notice Contract pause
    /// @param account Address that paused the contract
    event Paused(address indexed account);

    /// @notice Contract unpause
    /// @param account Address that unpaused the contract
    event Unpaused(address indexed account);
}
