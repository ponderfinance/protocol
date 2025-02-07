// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER STAKING INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderStaking
/// @author taayyohh
/// @notice Interface for Ponder protocol's staking functionality
/// @dev Defines core staking operations, events, and view functions
///      Implemented by the main staking contract
interface IPonderStaking {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when PONDER tokens are staked for xPONDER
    /// @dev Tracks both input and output amounts for stake operations
    /// @param user Address of the staking user
    /// @param ponderAmount Amount of PONDER tokens staked
    /// @param xPonderAmount Amount of xPONDER shares minted
    event Staked(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when PONDER tokens are withdrawn for xPONDER
    /// @dev Tracks both input and output amounts for unstake operations
    /// @param user Address of the withdrawing user
    /// @param ponderAmount Amount of PONDER tokens withdrawn
    /// @param xPonderAmount Amount of xPONDER shares burned
    event Withdrawn(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when rewards are distributed via rebase
    /// @dev Used to track system-wide staking metrics
    /// @param totalSupply Total supply of xPONDER after rebase
    /// @param totalPonderBalance Total PONDER tokens in staking contract
    event RebasePerformed(uint256 totalSupply, uint256 totalPonderBalance);

    /// @notice Emitted when two-step ownership transfer begins
    /// @dev First step of ownership transfer process
    /// @param currentOwner Address of the current owner
    /// @param pendingOwner Address of the proposed new owner
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);

    /// @notice Emitted when ownership transfer is completed
    /// @dev Final step of ownership transfer process
    /// @param previousOwner Address of the previous owner
    /// @param newOwner Address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                        STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes PONDER tokens to receive xPONDER shares
    /// @dev Transfers PONDER from user and mints xPONDER
    /// @param amount Amount of PONDER tokens to stake
    /// @return shares Amount of xPONDER shares minted
    function enter(uint256 amount) external returns (uint256 shares);

    /// @notice Withdraws PONDER tokens by burning xPONDER shares
    /// @dev Burns xPONDER and returns corresponding PONDER
    /// @param shares Amount of xPONDER shares to burn
    /// @return amount Amount of PONDER tokens returned
    function leave(uint256 shares) external returns (uint256 amount);

    /// @notice Distributes accumulated rewards to all stakers
    /// @dev Updates share price based on accumulated PONDER
    function rebase() external;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates PONDER tokens for given xPONDER amount
    /// @dev Uses current share price for calculation
    /// @param shares Amount of xPONDER shares to calculate for
    /// @return Amount of PONDER tokens that would be received
    function getPonderAmount(uint256 shares) external view returns (uint256);

    /// @notice Calculates xPONDER shares for given PONDER amount
    /// @dev Uses current share price for calculation
    /// @param amount Amount of PONDER tokens to calculate for
    /// @return Amount of xPONDER shares that would be received
    function getSharesAmount(uint256 amount) external view returns (uint256);

    /// @notice Returns minimum PONDER required for first stake
    /// @dev Used to prevent dust accounts
    /// @return Minimum amount of PONDER for first-time stakers
    function minimumFirstStake() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates two-step ownership transfer
    /// @dev Only current owner can call
    /// @param newOwner Address to transfer ownership to
    function transferOwnership(address newOwner) external;

    /// @notice Completes two-step ownership transfer
    /// @dev Only pending owner can call
    function acceptOwnership() external;
}
