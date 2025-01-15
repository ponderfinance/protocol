// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mocks/ERC20Mint.sol";
import "../../src/core/PonderFactory.sol";

contract PonderFactoryTest is Test {
    PonderFactory factory;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    ERC20Mint tokenC;
    address feeToSetter = address(0xfee);
    address initialLauncher = address(0xbad);
    address initialPonder = address(0xbade);

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);

    function setUp() public {
        factory = new PonderFactory(feeToSetter, initialLauncher, initialPonder);
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");
        tokenC = new ERC20Mint("Token C", "TKNC");
    }

    function testCreatePair() public {
        address token0 = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address token1 = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        // Get the expected pair address
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        address expectedPair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            address(factory),
            salt,
            factory.INIT_CODE_PAIR_HASH()
        )))));

        // Now use the computed address in expectEmit
        vm.expectEmit(true, true, true, true);
        emit PairCreated(token0, token1, expectedPair, 1);

        // Create the pair
        address pair = factory.createPair(address(tokenA), address(tokenB));

        // Verify results
        assertFalse(pair == address(0));
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function testCreatePairReversed() public {
        address pair1 = factory.createPair(address(tokenA), address(tokenB));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair1);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair1);
    }

    function testFailCreatePairZeroAddress() public {
        factory.createPair(address(0), address(tokenA));
    }

    function testFailCreatePairIdenticalTokens() public {
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testFailCreatePairExistingPair() public {
        factory.createPair(address(tokenA), address(tokenB));
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testCreateMultiplePairs() public {
        factory.createPair(address(tokenA), address(tokenB));
        factory.createPair(address(tokenA), address(tokenC));
        factory.createPair(address(tokenB), address(tokenC));

        assertEq(factory.allPairsLength(), 3);
    }

    function testSetFeeTo() public {
        address newFeeTo = address(0x1);
        vm.prank(feeToSetter);
        factory.setFeeTo(newFeeTo);
        assertEq(factory.feeTo(), newFeeTo);
    }

    function testFailSetFeeToUnauthorized() public {
        address newFeeTo = address(0x1);
        factory.setFeeTo(newFeeTo);
    }

    function testSetFeeToSetter() public {
        address newFeeToSetter = address(0x1);
        vm.prank(feeToSetter);
        factory.setFeeToSetter(newFeeToSetter);
        assertEq(factory.feeToSetter(), newFeeToSetter);
    }

    function testFailSetFeeToSetterUnauthorized() public {
        address newFeeToSetter = address(0x1);
        factory.setFeeToSetter(newFeeToSetter);
    }

    function testSetMigrator() public {
        address newMigrator = address(0x1);
        vm.prank(feeToSetter);
        factory.setMigrator(newMigrator);
        assertEq(factory.migrator(), newMigrator);
    }

    function testFailSetMigratorUnauthorized() public {
        address newMigrator = address(0x1);
        factory.setMigrator(newMigrator);
    }

    function testSetLauncher() public {
        address newLauncher = address(0x123);
        vm.prank(feeToSetter);
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.setLauncher(newLauncher);
        assertEq(factory.launcher(), newLauncher);
    }

    function testFailSetLauncherUnauthorized() public {
        address newLauncher = address(0x123);
        factory.setLauncher(newLauncher);
    }

    function testLauncherInitialization() public {
        assertEq(factory.launcher(), initialLauncher, "Launcher not initialized correctly");
    }

    // Helper function to compute the expected pair address
    function computePairAddress(address token0, address token1) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            address(factory),
            keccak256(abi.encodePacked(token0, token1)),
            factory.INIT_CODE_PAIR_HASH()
        )))));
    }
}
