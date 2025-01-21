// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PonderERC20
 * @notice Implementation of the ERC20 token standard with EIP-2612 permit functionality
 * @dev Extends OpenZeppelin's ERC20 implementation with gasless approval mechanism
 */
contract PonderERC20 is ERC20 {
    /// @notice Cached domain separator to optimize gas costs for permit operations
    /// @dev Immutable value set at construction
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    /// @notice Cached chain ID to detect when domain separator needs to be recomputed
    /// @dev Immutable value set at construction
    uint256 private immutable _CACHED_CHAIN_ID;

    /// @notice Cached contract address to detect when domain separator needs to be recomputed
    /// @dev Immutable value set at construction
    address private immutable _CACHED_THIS;

    /// @notice EIP-2612 permit typehash for creating permit digests
    /// @dev keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH =
    0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice Mapping of owner address to their current nonce for permits
    /// @dev Prevents replay attacks by requiring incrementing nonces
    mapping(address => uint256) private _nonces;

    /// @notice Error thrown when permit deadline has passed
    error PermitExpired();

    /// @notice Error thrown when permit signature is invalid
    error InvalidSignature();

    /**
     * @notice Constructs the PonderERC20 contract
     * @dev Initializes ERC20 token details and caches domain separator components
     * @param tokenName The name of the token
     * @param tokenSymbol The symbol of the token
     */
    constructor(string memory tokenName, string memory tokenSymbol)
    ERC20(tokenName, tokenSymbol)
    {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_THIS = address(this);
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /**
     * @notice Computes the domain separator for EIP-712 structured data hashing
     * @dev Uses token name, version "1", chain ID, and contract address
     * @return bytes32 The computed domain separator
     */
    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Gets the domain separator for EIP-712 structured data hashing
     * @dev Returns cached value if chain ID and contract address haven't changed
     * @return bytes32 The domain separator
     */
    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID && address(this) == _CACHED_THIS) {
            return _CACHED_DOMAIN_SEPARATOR;
        }
        return _computeDomainSeparator();
    }

    /**
     * @notice Get the current nonce for an address
     * @dev Used for generating permit signatures
     * @param owner The address to get the nonce for
     * @return The current nonce
     */
    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @notice Approve spending of tokens via signature (EIP-2612)
     * @dev Validates permit signature and sets approval if valid
     * @param owner The owner of the tokens
     * @param spender The approved spender
     * @param value The amount of tokens to approve
     * @param deadline The timestamp after which the permit is invalid
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (deadline < block.timestamp) revert PermitExpired();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline))
            )
        );

        address recoveredAddress = ECDSA.recover(digest, v, r, s);
        if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSignature();

        _approve(owner, spender, value);
    }

    /**
     * @notice Hook that is called before any transfer of tokens
     * @dev Overrides OpenZeppelin's _update to allow custom transfer logic
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param amount Amount of tokens transferred
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._update(from, to, amount);
    }
}
