// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER ERC20 TOKEN
//////////////////////////////////////////////////////////////*/

/// @title PonderERC20
/// @author taayyohh
/// @notice ERC20 implementation with gasless approvals (EIP-2612)
/// @dev Extends OpenZeppelin ERC20 with permit functionality
///      Used as base contract for PONDER token implementation
contract PonderERC20 is ERC20 {
    /*//////////////////////////////////////////////////////////////
                       EIP-2612 STORAGE
   //////////////////////////////////////////////////////////////*/

    /// @notice Domain separator for EIP-712 signatures
    /// @dev Cached on construction for gas optimization
    /// @dev Recomputed if chain ID or contract address changes
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    /// @notice Chain ID at contract deployment
    /// @dev Used to detect chain ID changes for domain separator
    /// @dev Set as immutable for gas optimization
    uint256 private immutable _CACHED_CHAIN_ID;

    /// @notice Contract address at deployment
    /// @dev Used to detect contract address changes
    /// @dev Set as immutable for gas optimization
    address private immutable _CACHED_THIS;

    /// @notice EIP-2612 permit typehash
    /// @dev keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    /// @dev Used in permit signature verification
    bytes32 public constant PERMIT_TYPEHASH =
    0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /// @notice Permit nonces per address
    /// @dev Prevents signature replay attacks
    /// @dev Increments with each successful permit
    mapping(address => uint256) private _nonces;


    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Permit timestamp validation failed
    /// @dev Thrown when permit deadline has passed
    error PermitExpired();

    /// @notice Permit signature verification failed
    /// @dev Thrown for invalid or unauthorized signatures
    error InvalidSignature();

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR
   //////////////////////////////////////////////////////////////*/

    /// @notice Initializes token and permit functionality
    /// @dev Caches domain separator components
    /// @param tokenName ERC20 token name
    /// @param tokenSymbol ERC20 token symbol
    constructor(string memory tokenName, string memory tokenSymbol)
    ERC20(tokenName, tokenSymbol)
    {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_THIS = address(this);
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                       EIP-2612 FUNCTIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Calculates EIP-712 domain separator
    /// @dev Incorporates name, version, chain ID, contract address
    /// @return Domain separator hash
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

    /// @notice Retrieves current domain separator
    /// @dev Returns cached value if chain hasn't changed
    /// @return Current domain separator
    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID && address(this) == _CACHED_THIS) {
            return _CACHED_DOMAIN_SEPARATOR;
        }
        return _computeDomainSeparator();
    }

    /// @notice Gets current nonce for address
    /// @dev Used for signature generation
    /// @param owner Address to get nonce for
    /// @return Current nonce value
    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

    /// @notice Enables gasless token approvals
    /// @dev Validates signature and sets approval
    /// @param owner Token owner address
    /// @param spender Address to approve
    /// @param value Amount to approve
    /// @param deadline Timestamp when permit expires
    /// @param v ECDSA signature recovery byte
    /// @param r ECDSA signature half
    /// @param s ECDSA signature half
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

    /*//////////////////////////////////////////////////////////////
                       INTERNAL HOOKS
   //////////////////////////////////////////////////////////////*/

    /// @notice Pre-transfer hook
    /// @dev Override point for custom transfer logic
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Transfer amount
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._update(from, to, amount);
    }
}
