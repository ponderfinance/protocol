// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPonderFactory
 * @notice Interface for the Ponder protocol's pair factory
 * @dev Handles creation and management of Ponder trading pairs
 */
interface IPonderFactory {
    /**
     * @notice Returns the address authorized to set fee collection address
     * @return Address of the fee setter
     */
    function feeToSetter() external view returns (address);

    /**
     * @notice Returns the address that collects protocol fees
     * @return Address where protocol fees are sent
     */
    function feeTo() external view returns (address);

    /**
     * @notice Returns the address of the protocol's launcher contract
     * @return Address of the launcher contract
     */
    function launcher() external view returns (address);

    /**
     * @notice Returns the address of the PONDER token
     * @return Address of the PONDER token contract
     */
    function ponder() external view returns (address);

    /**
     * @notice Returns the address of the migrator contract
     * @return Address of the migrator contract used for pool migrations
     */
    function migrator() external view returns (address);

    /**
     * @notice Returns the pending launcher address during timelock period
     * @return Address of the pending launcher
     */
    function pendingLauncher() external view returns (address);

    /**
     * @notice Returns the timestamp when launcher can be updated
     * @return Timestamp when the launcher update timelock expires
     */
    function launcherDelay() external view returns (uint256);

    /**
     * @notice Creates a new trading pair for two tokens
     * @dev Pair creation uses CREATE2 for deterministic addresses
     * @param tokenA Address of the first token
     * @param tokenB Address of the second token
     * @return pair Address of the newly created pair contract
     */
    function createPair(address tokenA, address tokenB) external returns (address pair);

    /**
     * @notice Fetches the address of the pair for two tokens
     * @param tokenA Address of the first token
     * @param tokenB Address of the second token
     * @return pair Address of the pair contract, or zero address if it doesn't exist
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /**
     * @notice Returns the address of a pair by its index
     * @return pair Address of the pair contract at the specified index
     */
    function allPairs(uint256 index) external view returns (address pair);

    /**
     * @notice Returns the total number of pairs created through the factory
     * @return Number of pairs created
     */
    function allPairsLength() external view returns (uint256);

    /**
     * @notice Updates the address that receives protocol fees
     * @dev Can only be called by feeToSetter
     * @param feeTo New address to receive protocol fees
     */
    function setFeeTo(address feeTo) external;

    /**
     * @notice Updates the address authorized to change the fee receiver
     * @dev Can only be called by current feeToSetter
     * @param feeToSetter New address authorized to set fee receiver
     */
    function setFeeToSetter(address feeToSetter) external;

    /**
     * @notice Sets the migrator contract address
     * @dev Can only be called by feeToSetter
     * @param migrator New migrator contract address
     */
    function setMigrator(address migrator) external;

    /**
     * @notice Initiates the launcher update process with timelock
     * @dev Can only be called by feeToSetter
     * @param launcher Address of the new launcher contract
     */
    function setLauncher(address launcher) external;

    /**
     * @notice Completes the launcher update after timelock period
     * @dev Can only be called by feeToSetter after timelock expires
     */
    function applyLauncher() external;

    /**
     * @notice Updates the PONDER token address
     * @dev Can only be called by feeToSetter
     * @param ponder New PONDER token address
     */
    function setPonder(address ponder) external;

    /**
     * @notice Emitted when a new pair is created
     * @param token0 Address of the first token in the pair (sorted by address)
     * @param token1 Address of the second token in the pair (sorted by address)
     * @param pair Address of the created pair contract
     * @param pairIndex Index of the pair in allPairs array
     */
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairIndex);

    /**
     * @notice Emitted when the fee receiver address is updated
     * @param oldFeeTo Previous fee receiver address
     * @param newFeeTo New fee receiver address
     */
    event FeeToUpdated(address indexed oldFeeTo, address indexed newFeeTo);

    /**
     * @notice Emitted when the launcher address is updated
     * @param oldLauncher Previous launcher address
     * @param newLauncher New launcher address
     */
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);
}
