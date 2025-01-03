// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PonderERC20.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPonderRouter.sol";
import "../interfaces/IPonderFactory.sol";

/**
 * @title PonderStaking
 * @notice Staking contract for PONDER tokens that implements a rebase mechanism
 * @dev Users stake PONDER and receive xPONDER, which rebases to capture protocol fees
 */
contract PonderStaking is PonderERC20 {
    /// @notice The PONDER token contract
    IERC20 public immutable ponder;

    /// @notice Ponder protocol router for swaps
    IPonderRouter public immutable router;

    /// @notice Factory contract reference
    IPonderFactory public immutable factory;

    /// @notice Address that can perform admin functions
    address public owner;

    /// @notice Pending owner for 2-step transfer
    address public pendingOwner;

    /// @notice Last time the rewards were distributed
    uint256 public lastRebaseTime;

    /// @notice Minimum time between rebases
    uint256 public constant REBASE_DELAY = 1 days;

    /// @notice Events
    event Staked(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);
    event Withdrawn(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);
    event RebasePerformed(uint256 totalSupply, uint256 totalPonderBalance);
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Custom errors
    error InvalidAmount();
    error RebaseTooFrequent();
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();

    /**
     * @notice Contract constructor
     * @param _ponder Address of the PONDER token contract
     * @param _router Address of the PonderRouter contract
     * @param _factory Address of the PonderFactory contract
     */
    constructor(
        address _ponder,
        address _router,
        address _factory
    ) PonderERC20("Staked Koi", "xKOI") {
        if (_ponder == address(0) || _router == address(0) || _factory == address(0))
            revert ZeroAddress();

        ponder = IERC20(_ponder);
        router = IPonderRouter(_router);
        factory = IPonderFactory(_factory);
        owner = msg.sender;
        lastRebaseTime = block.timestamp;
    }

    /**
     * @notice Stakes PONDER tokens and mints xPONDER
     * @param amount Amount of PONDER to stake
     * @return shares Amount of xPONDER minted
     */
    function enter(uint256 amount) external returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        uint256 totalPonder = ponder.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        // If there are no shares minted yet, mint 1:1
        if (totalShares == 0 || totalPonder == 0) {
            shares = amount;
        } else {
            // Calculate and mint shares
            shares = (amount * totalShares) / totalPonder;
        }

        // Transfer PONDER from user
        ponder.transferFrom(msg.sender, address(this), amount);

        // Mint xPONDER to user
        _mint(msg.sender, shares);

        emit Staked(msg.sender, amount, shares);
    }

    /**
     * @notice Withdraws PONDER tokens by burning xPONDER
     * @param shares Amount of xPONDER to burn
     * @return amount Amount of PONDER returned
     */
    function leave(uint256 shares) external returns (uint256 amount) {
        if (shares == 0) revert InvalidAmount();

        uint256 totalShares = totalSupply();
        uint256 totalPonder = ponder.balanceOf(address(this));

        // Calculate amount of PONDER to return based on share of total
        amount = (shares * totalPonder) / totalShares;

        // Burn xPONDER
        _burn(msg.sender, shares);

        // Transfer PONDER to user
        ponder.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, shares);
    }

    /**
     * @notice Performs rebase to distribute accumulated fees
     * @dev Only callable after REBASE_DELAY has passed since last rebase
     */
    function rebase() external {
        if (block.timestamp < lastRebaseTime + REBASE_DELAY)
            revert RebaseTooFrequent();

        lastRebaseTime = block.timestamp;

        uint256 totalShares = totalSupply();
        uint256 totalPonder = ponder.balanceOf(address(this));

        emit RebasePerformed(totalShares, totalPonder);
    }

    /**
     * @notice Calculates the amount of PONDER that would be returned for a given amount of xPONDER
     * @param shares Amount of xPONDER to calculate for
     * @return Amount of PONDER that would be returned
     */
    function getPonderAmount(uint256 shares) external view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return shares;
        return (shares * ponder.balanceOf(address(this))) / totalShares;
    }

    /**
     * @notice Calculates the amount of xPONDER that would be minted for a given amount of PONDER
     * @param amount Amount of PONDER to calculate for
     * @return Amount of xPONDER that would be minted
     */
    function getSharesAmount(uint256 amount) external view returns (uint256) {
        uint256 totalShares = totalSupply();
        uint256 totalPonder = ponder.balanceOf(address(this));
        if (totalShares == 0 || totalPonder == 0) return amount;
        return (amount * totalShares) / totalPonder;
    }

    /**
     * @notice Initiates transfer of ownership
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert NotOwner();
        if (newOwner == address(0)) revert ZeroAddress();

        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    /**
     * @notice Completes transfer of ownership
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, owner);
    }

    /// @notice Modifier for owner-only functions
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
}
