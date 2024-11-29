// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPonderFactory.sol";
import "./PonderPair.sol";

contract PonderFactory is IPonderFactory {
    address public feeTo;
    address public feeToSetter;
    address public migrator;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error Forbidden();

    bytes32 public constant INIT_CODE_PAIR_HASH = 0x32a28a5e5a16edd31231a46671a9cf89017d54aeab136e4ea2b6afa3059554ed;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

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

    function setFeeTo(address _feeTo) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        feeToSetter = _feeToSetter;
    }

    function setMigrator(address _migrator) external {
        if (msg.sender != feeToSetter) revert Forbidden();
        migrator = _migrator;
    }
}
