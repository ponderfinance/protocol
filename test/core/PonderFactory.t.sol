// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../mocks/ERC20Mint.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/factory/types/PonderFactoryTypes.sol";


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
    event FeeToUpdated(address indexed oldFeeTo, address indexed newFeeTo);

    function setUp() public {
        factory = new PonderFactory(feeToSetter, initialLauncher, initialPonder);
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");
        tokenC = new ERC20Mint("Token C", "TKNC");
    }

    function testCreatePair() public {
        address token0 = address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB);
        address token1 = address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA);

        // Get pair creation bytecode
        bytes memory bytecode = type(PonderPair).creationCode;

        // Compute salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // Compute the pair address using CREATE2 formula
        address expectedPair = computeAddress(salt, keccak256(bytecode), address(factory));

        // Set up event expectation
        vm.expectEmit(true, true, true, true);
        emit PairCreated(token0, token1, expectedPair, 1);

        // Create the pair
        address pair = factory.createPair(address(tokenA), address(tokenB));

        // Verify results
        assertFalse(pair == address(0));
        assertEq(pair, expectedPair);
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function computeAddress(bytes32 salt, bytes32 codeHash, address deployer) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            codeHash
        )))));
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

    function testSetLauncher() public {
        address newLauncher = address(0x123);

        vm.startPrank(feeToSetter);

        // Expect event for setting pending launcher
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.setLauncher(newLauncher);

        // Verify pending state
        assertEq(factory.pendingLauncher(), newLauncher);
        assertEq(factory.launcher(), initialLauncher); // Still the original launcher

        // Warp past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Apply the launcher change
        factory.applyLauncher();

        // Now verify the launcher has been updated
        assertEq(factory.launcher(), newLauncher);

        vm.stopPrank();
    }

    function testFailSetLauncherUnauthorized() public {
        address newLauncher = address(0x123);
        factory.setLauncher(newLauncher);
    }

    function testLauncherInitialization() public {
        assertEq(factory.launcher(), initialLauncher, "Launcher not initialized correctly");
    }

    function testSetFeeToEmitsEvent() public {
        address newFeeTo = address(0x1);
        vm.prank(feeToSetter);

        vm.expectEmit(true, true, false, true);
        emit FeeToUpdated(address(0), newFeeTo);

        factory.setFeeTo(newFeeTo);
        assertEq(factory.feeTo(), newFeeTo);
    }

    function testFailSetFeeToZeroAddress() public {
        vm.prank(feeToSetter);
        factory.setFeeTo(address(0));
    }

    function testSetFeeToMultipleTimes() public {
        address firstFeeTo = address(0x1);
        address secondFeeTo = address(0x2);

        vm.startPrank(feeToSetter);

        // First update
        vm.expectEmit(true, true, false, true);
        emit FeeToUpdated(address(0), firstFeeTo);
        factory.setFeeTo(firstFeeTo);
        assertEq(factory.feeTo(), firstFeeTo);

        // Second update
        vm.expectEmit(true, true, false, true);
        emit FeeToUpdated(firstFeeTo, secondFeeTo);
        factory.setFeeTo(secondFeeTo);
        assertEq(factory.feeTo(), secondFeeTo);

        vm.stopPrank();
    }

    // Existing unauthorized access test
    function testFailSetFeeToUnauthorized() public {
        address newFeeTo = address(0x1);
        factory.setFeeTo(newFeeTo);
    }

    function testSetLauncherWithTimelock() public {
        address newLauncher = address(0x123);
        vm.startPrank(feeToSetter);

        // Initial set - should go to pending
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.setLauncher(newLauncher);

        // Check pending state
        assertEq(factory.pendingLauncher(), newLauncher);
        assertEq(factory.launcher(), initialLauncher); // Original launcher unchanged
//        assertEq(factory.launcherDelay(), block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK);

        // Try to apply before timelock - should fail
        vm.expectRevert();
        factory.applyLauncher();

        // Warp to after timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Apply launcher change
        vm.expectEmit(true, true, false, true);
        emit LauncherUpdated(initialLauncher, newLauncher);
        factory.applyLauncher();

        // Verify final state
        assertEq(factory.launcher(), newLauncher);
        assertEq(factory.pendingLauncher(), address(0));
//        assertEq(factory.launcherDelay(), 0);

        vm.stopPrank();
    }


    function testFailSetLauncherToZeroAddress() public {
        vm.prank(feeToSetter);
        factory.setLauncher(address(0));
    }

    function testFailApplyLauncherWithoutPending() public {
        vm.prank(feeToSetter);
        factory.applyLauncher();
    }

    function testFailApplyLauncherBeforeTimelock() public {
        address newLauncher = address(0x123);

        vm.startPrank(feeToSetter);

        // Set new launcher
        factory.setLauncher(newLauncher);

        // Get current timestamp
        uint256 currentTime = block.timestamp;

        // Try to apply before timelock expires (warp to just before expiry)
        vm.warp(currentTime + PonderFactoryTypes.LAUNCHER_TIMELOCK - 1);

        // This should revert with TimelockNotFinished
        factory.applyLauncher();

        vm.stopPrank();
    }

    function testSetLauncherWhilePending() public {
        address firstLauncher = address(0x123);
        address secondLauncher = address(0x456);

        vm.startPrank(feeToSetter);

        // Set first launcher
        factory.setLauncher(firstLauncher);

        // Set second launcher (should override first)
        factory.setLauncher(secondLauncher);

        // Verify second launcher is pending
        assertEq(factory.pendingLauncher(), secondLauncher);

        vm.stopPrank();
    }

    function testTimelockExpiry() public {
        address newLauncher = address(0x123);

        vm.startPrank(feeToSetter);

        // Set new launcher
        factory.setLauncher(newLauncher);

        // Warp way past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1 weeks);

        // Should still be able to apply
        factory.applyLauncher();

        assertEq(factory.launcher(), newLauncher);
        vm.stopPrank();
    }

    function testFailApplyLauncherUnauthorized() public {
        address newLauncher = address(0x123);

        vm.prank(feeToSetter);
        factory.setLauncher(newLauncher);

        // Warp past timelock
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);

        // Try to apply from unauthorized address
        vm.prank(address(0xdeadbeef));
        factory.applyLauncher();
    }

    function testMultipleSetLauncherOverwrite() public {
        address firstNewLauncher = address(0x123);
        address secondNewLauncher = address(0x456);

        vm.startPrank(feeToSetter);

        // Set first launcher
        factory.setLauncher(firstNewLauncher);
        assertEq(factory.pendingLauncher(), firstNewLauncher);

        // Set second launcher - should overwrite pending
        factory.setLauncher(secondNewLauncher);
        assertEq(factory.pendingLauncher(), secondNewLauncher);

        // Warp and apply
        vm.warp(block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK + 1);
        factory.applyLauncher();

        // Verify final state
        assertEq(factory.launcher(), secondNewLauncher);
        vm.stopPrank();
    }

    // Helper function to compute the expected pair address
    function computePairAddress(address token0, address token1) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            address(factory),
            keccak256(abi.encodePacked(token0, token1)),
            PonderFactoryTypes.INIT_CODE_PAIR_HASH
        )))));
    }
}
