// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ILaunchToken {
    /// @notice Events
    event VestingInitialized(address indexed creator, uint256 amount, uint256 startTime, uint256 endTime);
    event TokensClaimed(address indexed creator, uint256 amount);
    event TransfersEnabled();
    event PairsSet(address kubPair, address ponderPair);
    event NewPendingLauncher(address indexed previousPending, address indexed newPending);
    event LauncherTransferred(address indexed previousLauncher, address indexed newLauncher);
    event MaxTxAmountUpdated(uint256 oldMaxTxAmount, uint256 newMaxTxAmount);

    /// @notice Returns the current launcher address
    function launcher() external view returns (address);

    /// @notice Returns the creator address
    function creator() external view returns (address);

    /// @notice Sets up the vesting schedule for token creator
    /// @param _creator Address of the token creator
    /// @param _amount Amount of tokens to vest
    function setupVesting(address _creator, uint256 _amount) external;

    /// @notice Checks if vesting has been initialized
    /// @return bool True if vesting is initialized
    function isVestingInitialized() external view returns (bool);

    /// @notice Allows creator to claim their vested tokens
    function claimVestedTokens() external;

    /// @notice Verification function for launch token
    /// @return bool Always returns true
    function isLaunchToken() external pure returns (bool);

    /// @notice Sets the trading pairs for the token
    /// @param _kubPair Address of the KUB pair
    /// @param _ponderPair Address of the PONDER pair
    function setPairs(address _kubPair, address _ponderPair) external;

    /// @notice Enables token transfers
    function enableTransfers() external;

    /// @notice Sets the maximum transaction amount
    /// @param _maxTxAmount New maximum transaction amount
    function setMaxTxAmount(uint256 _maxTxAmount) external;

    /// @notice Initiates launcher transfer process
    /// @param newLauncher Address of the new launcher
    function transferLauncher(address newLauncher) external;

    /// @notice Completes launcher transfer process
    function acceptLauncher() external;

    /// @notice Returns current vesting information
    /// @return total Total amount being vested
    /// @return claimed Amount already claimed
    /// @return available Amount currently available to claim
    /// @return start Vesting start timestamp
    /// @return end Vesting end timestamp
    function getVestingInfo() external view returns (
        uint256 total,
        uint256 claimed,
        uint256 available,
        uint256 start,
        uint256 end
    );
}
