// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER STAKING STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderStakingStorage
/// @author taayyohh
/// @notice Storage layout for Ponder protocol's staking functionality
/// @dev Abstract contract defining state variables for staking implementation
///      Must be inherited by the main staking contract
///      All state variables are carefully ordered for optimal packing
abstract contract PonderStakingStorage {
    /*//////////////////////////////////////////////////////////////
                    TIMING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Contract deployment timestamp
    /// @dev Used for team lock period validation
    uint256 public immutable DEPLOYMENT_TIME;

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to perform administrative functions
    /// @dev Has exclusive access to privileged operations
    /// @dev Can be transferred via two-step ownership transfer
    address public stakingOwner;

    /// @notice Address proposed in ownership transfer
    /// @dev Part of two-step ownership transfer pattern
    /// @dev Must accept ownership to become effective owner
    address public pendingOwner;

    /*//////////////////////////////////////////////////////////////
                        STAKING PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp of most recent reward distribution
    /// @dev Updated whenever rewards are distributed
    /// @dev Used to calculate time-weighted rewards
    uint256 public lastRebaseTime;

    /// @notice Accumulated PONDER rewards per staked share
    /// @dev Increases when rewards are distributed
    /// @dev Used to calculate individual staker rewards
    uint256 public ponderPerShare;

    /// @notice Total amount of PONDER tokens staked
    /// @dev Updated on every stake/unstake operation
    /// @dev Used for reward distribution calculations
    uint256 public totalDepositedPonder;

    /*//////////////////////////////////////////////////////////////
                        FEE TRACKING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Accumulated protocol fees per staked share
    /// @dev Increases when protocol fees are distributed
    /// @dev Separate from staking rewards for clear accounting
    /// @dev Scaled by FEE_PRECISION for accurate calculation
    uint256 public accumulatedFeesPerShare;

    /// @notice Maps staker address to their fee debt
    /// @dev Used to track claimed fees and calculate pending rewards
    /// @dev Updated on stake, unstake, and fee claim operations
    mapping(address => uint256) public userFeeDebt;

    /// @notice Total unclaimed fees in the contract
    /// @dev Running total of fees not yet claimed by stakers
    /// @dev Updated when fees are distributed or claimed
    uint256 public totalUnclaimedFees;
}
