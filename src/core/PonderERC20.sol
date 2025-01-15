// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IERC20.sol";

/**
 * @title PonderERC20
 * @dev Implementation of the ERC20 standard with EIP-2612 permit functionality.
 */
contract PonderERC20 is IERC20 {
    // Token metadata
    string private _name;
    string private _symbol;

    /// @notice Token decimals, defaulted to 18.
    uint8 public constant decimals = 18;

    // Total supply of the token
    uint256 private _totalSupply;

    // Mapping of balances per address
    mapping(address => uint256) private _balances;

    // Mapping of allowances between owner and spender
    mapping(address => mapping(address => uint256)) private _allowances;

    // EIP-2612 permit functionality
    bytes32 private _DOMAIN_SEPARATOR;

    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;
    address private immutable _CACHED_THIS;

    /// @notice The EIP-2612 permit type hash.
    bytes32 public constant PERMIT_TYPEHASH =
    0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // Mapping of nonces for each address for permit functionality
    mapping(address => uint256) private _nonces;

    /**
     * @dev Constructor to initialize the token name and symbol.
     * @param tokenName The name of the token.
     * @param tokenSymbol The symbol of the token.
     */
    constructor(string memory tokenName, string memory tokenSymbol) {
        _name = tokenName;
        _symbol = tokenSymbol;

        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_THIS = address(this);
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(_name)),
                keccak256(bytes('1')),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Returns the name of the token.
     * @return The token name.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @notice Returns the symbol of the token.
     * @return The token symbol.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Returns the EIP-2612 domain separator.
     * @return The domain separator.
     */
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID && address(this) == _CACHED_THIS) {
            return _CACHED_DOMAIN_SEPARATOR;
        }
        return _computeDomainSeparator();
    }

    /**
     * @notice Returns the current nonce for an address for permit functionality.
     * @param owner The address to query.
     * @return The current nonce for the address.
     */
    function nonces(address owner) external view override returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @notice Returns the total supply of the token.
     * @return The total supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Returns the balance of a specific address.
     * @param account The address to query.
     * @return The balance of the address.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Returns the allowance of a spender for a specific owner.
     * @param owner The owner of the tokens.
     * @param spender The address allowed to spend the tokens.
     * @return The remaining allowance for the spender.
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev Internal function to mint new tokens.
     * @param to The address receiving the minted tokens.
     * @param value The amount of tokens to mint.
     */
    function _mint(address to, uint256 value) internal virtual {
        require(to != address(0), "MINT_TO_ZERO_ADDRESS");
        _totalSupply += value;
        _balances[to] += value;
        emit Transfer(address(0), to, value);
    }

    /**
     * @dev Internal function to burn tokens from an address.
     * @param from The address to burn tokens from.
     * @param value The amount of tokens to burn.
     */
    function _burn(address from, uint256 value) internal virtual {
        require(from != address(0), "BURN_FROM_ZERO_ADDRESS");
        _balances[from] -= value;
        _totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    /**
     * @notice Approves a spender to spend a specific amount of tokens.
     * @param spender The address allowed to spend the tokens.
     * @param value The amount to approve.
     * @return True if the operation is successful.
     */
    function approve(address spender, uint256 value) external virtual override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Internal function to set an allowance.
     * @param owner The owner of the tokens.
     * @param spender The address allowed to spend the tokens.
     * @param value The amount to approve.
     */
    function _approve(address owner, address spender, uint256 value) internal virtual {
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @notice Transfers tokens to a specific address.
     * @param to The recipient of the tokens.
     * @param value The amount of tokens to transfer.
     * @return True if the operation is successful.
     */
    function transfer(address to, uint256 value) external virtual override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Transfers tokens from one address to another.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return True if the operation is successful.
     */
    function transferFrom(address from, address to, uint256 value) external virtual override returns (bool) {
        if (_allowances[from][msg.sender] != type(uint256).max) {
            _allowances[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Internal function to perform a token transfer.
     * @param from The sender of the tokens.
     * @param to The recipient of the tokens.
     * @param value The amount of tokens to transfer.
     */
    function _transfer(address from, address to, uint256 value) internal virtual {
        require(to != address(0), "TRANSFER_TO_ZERO_ADDRESS");
        _balances[from] -= value;
        _balances[to] += value;
        emit Transfer(from, to, value);
    }

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
    ) external virtual override {
        require(deadline >= block.timestamp, 'EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR(), // Use the function instead of the state variable
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
