// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PonderERC20 is ERC20 {
    // EIP-2612 permit functionality
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;
    address private immutable _CACHED_THIS;

    bytes32 public constant PERMIT_TYPEHASH =
    0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint256) private _nonces;

    // Custom errors
    error PermitExpired();
    error InvalidSignature();

    constructor(string memory tokenName, string memory tokenSymbol)
    ERC20(tokenName, tokenSymbol)
    {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_THIS = address(this);
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

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

    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID && address(this) == _CACHED_THIS) {
            return _CACHED_DOMAIN_SEPARATOR;
        }
        return _computeDomainSeparator();
    }

    function nonces(address owner) public view returns (uint256) {
        return _nonces[owner];
    }

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

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._update(from, to, amount);
    }
}
