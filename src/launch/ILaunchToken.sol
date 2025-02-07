// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    LAUNCH TOKEN INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title ILaunchToken
/// @author taayyohh
/// @notice Interface for the launch token implementation
/// @dev Defines core functionality for token launches and vesting
interface ILaunchToken {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when vesting schedule is initialized
    /// @param creator Address of the token creator
    /// @param amount Total amount of tokens to vest
    /// @param startTime Timestamp when vesting begins
    /// @param endTime Timestamp when vesting ends
    event VestingInitialized(address indexed creator, uint256 amount, uint256 startTime, uint256 endTime);

    /// @notice Emitted when vested tokens are claimed
    /// @param creator Address claiming the tokens
    /// @param amount Number of tokens claimed
    event TokensClaimed(address indexed creator, uint256 amount);

    /// @notice Emitted when token transfers are enabled
    /// @dev Called after launch completion
    event TransfersEnabled();

    /// @notice Emitted when trading pairs are set
    /// @param kubPair Address of the token-KUB trading pair
    /// @param ponderPair Address of the token-PONDER trading pair
    event PairsSet(address kubPair, address ponderPair);

    /// @notice Emitted when pending launcher is updated
    /// @param previousPending Previous pending launcher address
    /// @param newPending New pending launcher address
    event NewPendingLauncher(address indexed previousPending, address indexed newPending);

    /// @notice Emitted when launcher transfer is completed
    /// @param previousLauncher Previous launcher address
    /// @param newLauncher New launcher address
    event LauncherTransferred(address indexed previousLauncher, address indexed newLauncher);

    /// @notice Emitted when maximum transaction amount is updated
    /// @param oldMaxTxAmount Previous maximum transaction amount
    /// @param newMaxTxAmount New maximum transaction amount
    event MaxTxAmountUpdated(uint256 oldMaxTxAmount, uint256 newMaxTxAmount);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current launcher address
    /// @return Address of the current launcher
    /// @dev Launcher has special privileges for token management
    function launcher() external view returns (address);

    /// @notice Returns the creator address
    /// @return Address of the token creator
    /// @dev Creator receives vested token allocation
    function creator() external view returns (address);

    /// @notice Checks if vesting has been initialized
    /// @return bool True if vesting is initialized
    /// @dev Used to prevent multiple vesting initializations
    function isVestingInitialized() external view returns (bool);

    /// @notice Verification function for launch token
    /// @return bool Always returns true
    /// @dev Used to verify contract is a launch token
    function isLaunchToken() external pure returns (bool);

    /// @notice Returns current vesting information
    /// @return total Total amount being vested
    /// @return claimed Amount already claimed
    /// @return available Amount currently available to claim
    /// @return start Vesting start timestamp
    /// @return end Vesting end timestamp
    /// @dev Returns all relevant vesting parameters in single call
    function getVestingInfo() external view returns (
        uint256 total,
        uint256 claimed,
        uint256 available,
        uint256 start,
        uint256 end
    );

    /*//////////////////////////////////////////////////////////////
                        STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets up the vesting schedule for token creator
    /// @param _creator Address of the token creator
    /// @param _amount Amount of tokens to vest
    /// @dev Can only be called once by launcher
    function setupVesting(address _creator, uint256 _amount) external;

    /// @notice Allows creator to claim their vested tokens
    /// @dev Calculates and transfers available tokens
    /// @dev Subject to minimum claim interval
    function claimVestedTokens() external;

    /// @notice Sets the trading pairs for the token
    /// @param _kubPair Address of the KUB pair
    /// @param _ponderPair Address of the PONDER pair
    /// @dev Can only be called once by launcher
    function setPairs(address _kubPair, address _ponderPair) external;

    /// @notice Enables token transfers
    /// @dev Can only be called once by launcher
    /// @dev Initiates trading restriction period
    function enableTransfers() external;

    /// @notice Sets the maximum transaction amount
    /// @param _maxTxAmount New maximum transaction amount
    /// @dev Restricted to launcher
    /// @dev Used for trading volume control
    function setMaxTxAmount(uint256 _maxTxAmount) external;

    /// @notice Initiates launcher transfer process
    /// @param newLauncher Address of the new launcher
    /// @dev First step of two-step launcher transfer
    function transferLauncher(address newLauncher) external;

    /// @notice Completes launcher transfer process
    /// @dev Second step of two-step launcher transfer
    /// @dev Can only be called by pending launcher
    function acceptLauncher() external;
}
