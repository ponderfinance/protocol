// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPonderFactory.sol";
import "./PonderPair.sol";

/**
 * @title PonderFactory
 * @dev Factory contract for creating and managing Ponder pairs.
 */
contract PonderFactory is IPonderFactory {
    /// @notice Address receiving fees.
    address public feeTo;

    /// @notice Address allowed to set the fee receiver.
    address public feeToSetter;

    /// @notice Address of the migrator contract.
    address public migrator;

    /// @notice Address of the launcher.
    address public launcher;

    /// @notice Address of the Ponder token.
    address public ponder;

    /// @notice Mapping to store pair addresses by token addresses.
    mapping(address => mapping(address => address)) public getPair;

    /// @notice Array of all pair addresses created by the factory.
    address[] public allPairs;

    /// @dev Error to revert when tokenA and tokenB are identical.
    error IdenticalAddresses();

    /// @dev Error to revert when an address is zero.
    error ZeroAddress();

    /// @dev Error to revert when a pair already exists.
    error PairExists();

    /// @dev Error to revert when a forbidden action is attempted.
    error Forbidden();

    /// @notice Hash of the init code of the pair contract.
    bytes32 public constant INIT_CODE_PAIR_HASH = 0x5b2c36488f6f5358809016c6ef0a4062c13d936275a7f4ce9f23145c6a79fc18;

    /**
     * @dev Constructor to initialize the factory with required addresses.
     * @param _feeToSetter Address allowed to set the fee receiver.
     * @param _launcher Address of the launcher.
     * @param _ponder Address of the Ponder token.
     */
    constructor(address _feeToSetter, address _launcher, address _ponder) {
        feeToSetter = _feeToSetter;
        launcher = _launcher;
        ponder = _ponder;
    }

    /**
     * @notice Returns the total number of pairs created by the factory.
     * @return The length of the allPairs array.
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /**
     * @notice Creates a new pair for two tokens.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pair The address of the newly created pair.
     * @dev Reverts if the tokens are identical, zero, or if the pair already exists.
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PairExists();

        // Create the pair
        bytes memory bytecode = type(PonderPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        PonderPair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
     * @notice Sets the address to receive fees.
     * @param _feeTo The address to set as the fee receiver.
     * @dev Only callable by the feeToSetter.
     */
    function setFeeTo(address _feeTo) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeTo = _feeTo;
    }

    /**
     * @notice Sets the address allowed to update the fee receiver.
     * @param _feeToSetter The new feeToSetter address.
     * @dev Only callable by the current feeToSetter.
     */
    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeToSetter = _feeToSetter;
    }

    /**
     * @notice Sets the migrator contract address.
     * @param _migrator The address of the migrator contract.
     * @dev Only callable by the feeToSetter.
     */
    function setMigrator(address _migrator) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        migrator = _migrator;
    }

    /**
     * @notice Sets the launcher address.
     * @param _launcher The new launcher address.
     * @dev Only callable by the feeToSetter. Emits LauncherUpdated event.
     */
    function setLauncher(address _launcher) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        address oldLauncher = launcher;
        launcher = _launcher;
        emit LauncherUpdated(oldLauncher, _launcher);
    }

    /**
     * @notice Sets the Ponder token address.
     * @param _ponder The new Ponder token address.
     * @dev Only callable by the feeToSetter. Emits LauncherUpdated event.
     */
    function setPonder(address _ponder) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        address oldPonderToken = ponder;
        ponder = _ponder;
        emit LauncherUpdated(oldPonderToken, _ponder);
    }
}
