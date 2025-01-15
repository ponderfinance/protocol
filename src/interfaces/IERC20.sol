// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC20
 * @dev Interface for the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @notice Returns the name of the token.
     * @return The name of the token as a string.
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the symbol of the token.
     * @return The symbol of the token as a string.
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the number of decimals used for display purposes.
     * @return The number of decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the total supply of the token.
     * @return The total token supply.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the balance of a specific address.
     * @param owner The address to query.
     * @return The balance of the address.
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @notice Returns the allowance of a spender for a specific owner.
     * @param owner The address of the token owner.
     * @param spender The address allowed to spend the tokens.
     * @return The remaining allowance for the spender.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @notice Approves a spender to spend a specific amount of tokens.
     * @param spender The address allowed to spend the tokens.
     * @param value The amount to approve.
     * @return True if the operation is successful.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @notice Transfers tokens to a specific address.
     * @param to The recipient of the tokens.
     * @param value The amount of tokens to transfer.
     * @return True if the operation is successful.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @notice Transfers tokens from one address to another using an allowance mechanism.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return True if the operation is successful.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    /**
     * @notice Allows a spender to transfer tokens on behalf of an owner using a signed permit.
     * @param owner The owner of the tokens.
     * @param spender The address allowed to spend the tokens.
     * @param value The amount to approve.
     * @param deadline The deadline for the permit.
     * @param v The recovery id of the signature.
     * @param r The R component of the signature.
     * @param s The S component of the signature.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Returns the EIP-2612 domain separator.
     * @return The domain separator.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Returns the EIP-2612 permit type hash.
     * @return The permit type hash.
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    /**
     * @notice Returns the current nonce for an address for permit functionality.
     * @param owner The address to query.
     * @return The current nonce for the address.
     */
    function nonces(address owner) external view returns (uint256);
}
