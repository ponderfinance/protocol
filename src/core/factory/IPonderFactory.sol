// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER FACTORY INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderFactory
/// @author taayyohh
/// @notice Interface for managing Ponder protocol's trading pair lifecycle
/// @dev Defines core functionality for pair creation and protocol configuration
interface IPonderFactory {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new trading pair is created
    /// @dev Includes sorted token addresses and pair indexing information
    /// @param token0 Address of the first token (lower address value)
    /// @param token1 Address of the second token (higher address value)
    /// @param pair Address of the newly created pair contract
    /// @param pairIndex Sequential index of the pair in allPairs array
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256 pairIndex
    );

    /// @notice Emitted when protocol fee recipient is changed
    /// @dev Tracks changes in fee collection address
    /// @param oldFeeTo Previous address receiving protocol fees
    /// @param newFeeTo New address to receive protocol fees
    event FeeToUpdated(
        address indexed oldFeeTo,
        address indexed newFeeTo
    );

    /// @notice Emitted when protocol launcher address is updated
    /// @dev Tracks changes in pair deployment permissions
    /// @param oldLauncher Previous launcher contract address
    /// @param newLauncher New launcher contract address
    event LauncherUpdated(
        address indexed oldLauncher,
        address indexed newLauncher
    );

    /// @notice Emitted when fee configuration admin is changed
    /// @dev Tracks changes in fee management permissions
    /// @param oldFeeToSetter Previous admin address
    /// @param newFeeToSetter New admin address
    event FeeToSetterUpdated(
        address indexed oldFeeToSetter,
        address indexed newFeeToSetter
    );

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns current fee management admin
    /// @dev This address can update fee-related parameters
    /// @return Address with fee configuration permissions
    function feeToSetter() external view returns (address);

    /// @notice Returns current protocol fee recipient
    /// @dev Address where protocol fees are collected
    /// @return Address receiving protocol fees
    function feeTo() external view returns (address);

    /// @notice Returns current protocol launcher
    /// @dev Address authorized to deploy new pairs
    /// @return Address of the launcher contract
    function launcher() external view returns (address);

    /// @notice Returns protocol governance token
    /// @dev Core token of the Ponder protocol
    /// @return Address of the PONDER token contract
    function ponder() external view returns (address);

    /// @notice Returns pending launcher during timelock
    /// @dev Part of launcher update safety mechanism
    /// @return Address queued to become new launcher
    function pendingLauncher() external view returns (address);

    /// @notice Returns launcher update timelock expiry
    /// @dev Timestamp when launcher can be updated
    /// @return Unix timestamp of timelock expiration
    function launcherDelay() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            PAIR MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new trading pair for provided tokens
    /// @dev Deploys pair contract using CREATE2 for address determinism
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the created pair contract
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    /// @notice Retrieves pair address for given tokens
    /// @dev Returns zero address if pair doesn't exist
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the pair contract
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    /// @notice Gets pair address by index
    /// @dev For pair enumeration and iteration
    /// @return pair Address of the indexed pair
    function allPairs(uint256) external view returns (address pair);

    /// @notice Returns total number of created pairs
    /// @dev Length of allPairs array
    /// @return Total count of deployed pairs
    function allPairsLength() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        ADMIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates protocol fee recipient
    /// @dev Restricted to feeToSetter
    /// @param feeTo New fee collection address
    function setFeeTo(address feeTo) external;

    /// @notice Updates fee management admin
    /// @dev Restricted to current feeToSetter
    /// @param feeToSetter New fee admin address
    function setFeeToSetter(address feeToSetter) external;

    /// @notice Initiates launcher update process
    /// @dev Starts timelock period for launcher change
    /// @param launcher Proposed new launcher address
    function setLauncher(address launcher) external;

    /// @notice Completes launcher update
    /// @dev Can only execute after timelock expires
    function applyLauncher() external;

    /// @notice Updates protocol token address
    /// @dev Restricted to feeToSetter
    /// @param ponder New PONDER token address
    function setPonder(address ponder) external;
}
