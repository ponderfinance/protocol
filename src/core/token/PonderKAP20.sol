// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IKYCBitkubChain } from "./IKYCBitkubChain.sol";
import { IAdminProjectRouter } from "./IAdminProjectRouter.sol";
import { IKAP20 } from "./IKAP20.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER KAP20 TOKEN
//////////////////////////////////////////////////////////////*/

/// @title PonderKAP20
/// @author taayyohh
/// @notice KAP20 implementation for Bitkub Chain with gasless approvals (EIP-2612)
/// @dev Extends OpenZeppelin ERC20 with permit functionality and Bitkub Chain compliance
///      Used as base contract for PONDER token implementation on Bitkub Chain
contract PonderKAP20 is ERC20, IKAP20 {
    using ECDSA for bytes32;

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
                       KAP-20 ADDITIONAL STORAGE
   //////////////////////////////////////////////////////////////*/

    /// @notice Bitkub Chain KYC verification service
    /// @dev Used to verify KYC status of addresses
    IKYCBitkubChain public kyc;

    /// @notice Bitkub Chain admin project router
    /// @dev Used to verify admin privileges
    IAdminProjectRouter public adminProjectRouter;

    /// @notice Committee address for admin operations
    /// @dev Has highest authority for contract administration
    address public committee;

    /// @notice Transfer router for special transfer operations
    /// @dev Can execute internal and external transfers
    address public transferRouter;

    /// @notice Project identifier for admin verification
    /// @dev Used with adminProjectRouter
    string public constant PROJECT = "PONDER";

    /// @notice Minimum KYC level required for token operations
    /// @dev Default is set in constructor
    uint256 public acceptedKYCLevel;

    /// @notice Flag to enforce KYC for all operations
    /// @dev When true, all operations require KYC verification
    bool public isActivatedOnlyKYCAddress;

    /// @notice Contract pause state
    /// @dev When true, most operations are disabled
    bool private _paused;

    /// @notice Owner address for admin operations
    /// @dev Initially set to deployer
    address private _owner;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Permit timestamp validation failed
    /// @dev Thrown when permit deadline has passed
    error PermitExpired();

    /// @notice Permit signature verification failed
    /// @dev Thrown for invalid or unauthorized signatures
    error InvalidSignature();

    /// @notice Contract is paused
    /// @dev Thrown when an operation is attempted while paused
    error PausedToken();

    /// @notice Caller is not authorized
    /// @dev Thrown when caller lacks required permissions
    error NotAuthorized();

    /// @notice Address is zero
    /// @dev Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice KYC level is insufficient
    /// @dev Thrown when KYC verification fails
    error KYCNotApproved();

    /// @notice KYC level is invalid
    /// @dev Thrown when KYC level is invalid
    error InvalidKYCLevel();

    /// @notice Caller is not the owner
    /// @dev Thrown when a non-owner tries to call an owner-only function
    error NotOwner();

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR
   //////////////////////////////////////////////////////////////*/

    /// @notice Initializes token and permit functionality
    /// @dev Simplified constructor matching PonderERC20 for easier migration
    /// @param tokenName ERC20 token name
    /// @param tokenSymbol ERC20 token symbol
    constructor(string memory tokenName, string memory tokenSymbol)
    ERC20(tokenName, tokenSymbol)
    {
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_THIS = address(this);
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();

        // Set deployer as owner
        _owner = msg.sender;

        // Initialize KAP parameters with safe defaults
        acceptedKYCLevel = 0;
        isActivatedOnlyKYCAddress = false;
        _paused = false;
    }

    /*//////////////////////////////////////////////////////////////
                       MODIFIERS
   //////////////////////////////////////////////////////////////*/

    /// @notice Ensures function can only be called by the owner
    /// @dev Reverts with NotOwner if caller is not the owner
    modifier onlyOwner() virtual {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    /// @notice Ensures function can only be called when contract is not paused
    /// @dev Reverts with Paused error if contract is paused
    modifier whenNotPaused() {
        if (_paused) revert PausedToken();
        _;
    }

    /// @notice Ensures function can only be called by committee
    /// @dev Reverts with NotAuthorized if caller is not committee
    modifier onlyCommittee() {
        if (committee == address(0)) revert NotAuthorized();
        if (msg.sender != committee) revert NotAuthorized();
        _;
    }

    /// @notice Ensures function can only be called by super admin
    /// @dev Reverts with NotAuthorized if caller is not super admin
    /// @dev Bypasses check if adminProjectRouter not set
    modifier onlySuperAdmin() {
        if (address(adminProjectRouter) == address(0)) return; // Skip check if not set up
        if (!adminProjectRouter.isSuperAdmin(msg.sender, PROJECT)) revert NotAuthorized();
        _;
    }

    /// @notice Ensures function can only be called by super admin or transfer router
    /// @dev Reverts with NotAuthorized if caller is neither super admin nor transfer router
    /// @dev Bypasses check if adminProjectRouter not set
    modifier onlySuperAdminOrTransferRouter() {
        if (address(adminProjectRouter) == address(0)) return; // Skip check if not set up
        if (!(adminProjectRouter.isSuperAdmin(msg.sender, PROJECT) || msg.sender == transferRouter))
            revert NotAuthorized();
        _;
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
    /// @param owner_ Address to get nonce for
    /// @return Current nonce value
    function nonces(address owner_) public view returns (uint256) {
        return _nonces[owner_];
    }

    /// @notice Enables gasless token approvals
    /// @dev Validates signature and sets approval
    /// @param owner_ Token owner address
    /// @param spender Address to approve
    /// @param value Amount to approve
    /// @param deadline Timestamp when permit expires
    /// @param v ECDSA signature recovery byte
    /// @param r ECDSA signature half
    /// @param s ECDSA signature half
    function permit(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        if (deadline < block.timestamp) revert PermitExpired();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner_, spender, value, _nonces[owner_]++, deadline))
            )
        );

        address recoveredAddress = ECDSA.recover(digest, v, r, s);
        if (recoveredAddress == address(0) || recoveredAddress != owner_) revert InvalidSignature();

        _approve(owner_, spender, value);
    }

    /*//////////////////////////////////////////////////////////////
                       KAP-20 FUNCTIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Admin function to transfer tokens between addresses
    /// @dev Only callable by committee
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the admin transfer was successful
    function adminTransfer(address sender, address recipient, uint256 amount)
    external
    onlyCommittee
    returns (bool success)
    {
        if (address(kyc) != address(0) && isActivatedOnlyKYCAddress) {
            if (kyc.kycsLevel(sender) == 0) revert KYCNotApproved();
        }

        _transfer(sender, recipient, amount);
        return true;
    }

    /// @notice Internal transfer function that requires both parties to have KYC
    /// @dev Only callable by super admin or transfer router
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the internal transfer was successful
    function internalTransfer(address sender, address recipient, uint256 amount)
    external
    onlySuperAdminOrTransferRouter
    whenNotPaused
    returns (bool success)
    {
        if (address(kyc) != address(0)) {
            if (kyc.kycsLevel(sender) < acceptedKYCLevel || kyc.kycsLevel(recipient) < acceptedKYCLevel) {
                revert KYCNotApproved();
            }
        }

        _transfer(sender, recipient, amount);
        return true;
    }

    /// @notice External transfer function that requires sender to have KYC
    /// @dev Only callable by super admin or transfer router
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the external transfer was successful
    function externalTransfer(address sender, address recipient, uint256 amount)
    external
    onlySuperAdminOrTransferRouter
    whenNotPaused
    returns (bool success)
    {
        if (address(kyc) != address(0)) {
            if (kyc.kycsLevel(sender) < acceptedKYCLevel) {
                revert KYCNotApproved();
            }
        }

        _transfer(sender, recipient, amount);
        return true;
    }

    /// @notice Admin function to set an allowance on behalf of an owner
    /// @dev Only callable by super admin
    /// @param owner_ The address that will approve the allowance
    /// @param spender The address that will be able to spend the tokens
    /// @param amount The amount of tokens the spender can spend
    /// @return success True if the admin approval was successful
    function adminApprove(address owner_, address spender, uint256 amount)
    external
    onlySuperAdmin
    returns (bool success)
    {
        if (address(kyc) != address(0)) {
            if (kyc.kycsLevel(owner_) < acceptedKYCLevel) {
                revert KYCNotApproved();
            }
        }

        _approve(owner_, spender, amount);
        return true;
    }

    /// @notice Transfers tokens to a specified address
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the transfer was successful
    function transfer(address recipient, uint256 amount)
    public
    virtual
    override(ERC20)
    whenNotPaused
    returns (bool success)
    {
        return super.transfer(recipient, amount);
    }

    /// @notice Transfers tokens from one address to another using an allowance
    /// @param sender The address to transfer tokens from
    /// @param recipient The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the transfer was successful
    function transferFrom(address sender, address recipient, uint256 amount)
    public
    virtual
    override(ERC20)
    whenNotPaused
    returns (bool success)
    {
        return super.transferFrom(sender, recipient, amount);
    }

    /// @notice Sets an allowance for a spender to spend on behalf of the caller
    /// @param spender The address that will be able to spend the tokens
    /// @param amount The amount of tokens the spender can spend
    /// @return success True if the approval was successful
    function approve(address spender, uint256 amount)
    public
    virtual
    override(ERC20)
    whenNotPaused
    returns (bool success)
    {
        return super.approve(spender, amount);
    }

    /// @notice Get balance of an account
    /// @param account The address to query the balance of
    /// @return The balance of the account
    function balanceOf(address account)
    public
    view
    virtual
    override(ERC20)
    returns (uint256)
    {
        return super.balanceOf(account);
    }

    /// @notice Get allowance of a spender for an owner_
    /// @param owner_ The address that approved the allowance
    /// @param spender The address that can spend the allowance
    /// @return The amount of tokens the spender can spend
    function allowance(address owner_, address spender)
    public
    view
    virtual
    override(ERC20)
    returns (uint256)
    {
        return super.allowance(owner_, spender);
    }

    /// @notice Get the total supply of tokens
    /// @return The total supply
    function totalSupply()
    public
    view
    virtual
    override(ERC20)
    returns (uint256)
    {
        return super.totalSupply();
    }

    /// @notice Get the token name
    /// @return The name of the token
    function name()
    public
    view
    virtual
    override(ERC20)
    returns (string memory)
    {
        return super.name();
    }

    /// @notice Get the token symbol
    /// @return The symbol of the token
    function symbol()
    public
    view
    virtual
    override(ERC20)
    returns (string memory)
    {
        return super.symbol();
    }

    /// @notice Get the token decimals
    /// @return The decimals of the token
    function decimals()
    public
    view
    virtual
    override(ERC20)
    returns (uint8)
    {
        return super.decimals();
    }

    /*//////////////////////////////////////////////////////////////
                       OWNERSHIP AND ADMIN FUNCTIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Get the owner address
    /// @return The current owner address
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /// @notice Transfers ownership to a new address
    /// @dev Only callable by the current owner
    /// @param newOwner The address that will become the new owner
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /// @notice Sets the KYC verification service
    /// @dev Only callable by owner
    /// @param _kyc Address of the KYC verification service
    function setKYC(address _kyc) external onlyOwner {
        if (_kyc == address(0)) revert ZeroAddress();
        address oldKyc = address(kyc);
        kyc = IKYCBitkubChain(_kyc);
        emit KYCBitkubChainSet(msg.sender, oldKyc, _kyc);
    }

    /// @notice Sets the committee address
    /// @dev Only callable by owner
    /// @param _committee Address of the new committee
    function setCommittee(address _committee) external onlyOwner {
        if (_committee == address(0)) revert ZeroAddress();
        address oldCommittee = committee;
        committee = _committee;
        emit CommitteeSet(msg.sender, oldCommittee, _committee);
    }

    /// @notice Sets the transfer router address
    /// @dev Only callable by owner
    /// @param _transferRouter Address of the new transfer router
    function setTransferRouter(address _transferRouter) external onlyOwner {
        address oldTransferRouter = transferRouter;
        transferRouter = _transferRouter;
        emit TransferRouterSet(msg.sender, oldTransferRouter, _transferRouter);
    }

    /// @notice Sets the admin project router
    /// @dev Only callable by owner
    /// @param _adminProjectRouter Address of the new admin project router
    function setAdminProjectRouter(address _adminProjectRouter) external onlyOwner {
        address oldAdminProjectRouter = address(adminProjectRouter);
        adminProjectRouter = IAdminProjectRouter(_adminProjectRouter);
        emit AdminProjectRouterSet(msg.sender, oldAdminProjectRouter, _adminProjectRouter);
    }

    /// @notice Sets the accepted KYC level
    /// @dev Only callable by owner
    /// @param _kycLevel The new KYC level
    function setAcceptedKYCLevel(uint256 _kycLevel) external onlyOwner {
        uint256 oldKYCLevel = acceptedKYCLevel;
        acceptedKYCLevel = _kycLevel;
        emit AcceptedKYCLevelSet(msg.sender, oldKYCLevel, _kycLevel);
    }

    /// @notice Activates KYC address enforcement
    /// @dev Only callable by owner
    function activateOnlyKYCAddress() external onlyOwner {
        isActivatedOnlyKYCAddress = true;
        emit ActivateOnlyKYCAddress(msg.sender);
    }

    /// @notice Pauses the contract
    /// @dev Only callable by owner
    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpauses the contract
    /// @dev Only callable by owner
    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Returns the pause state of the contract
    /// @return True if the contract is paused
    function paused() external view returns (bool) {
        return _paused;
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL HOOKS
   //////////////////////////////////////////////////////////////*/

    /// @notice Internal transfer hook
    /// @dev Can be overridden by derived contracts
    /// @param from Address sending tokens
    /// @param to Address receiving tokens
    /// @param amount Amount of tokens transferred
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._update(from, to, amount);
    }
}
