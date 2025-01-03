// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/core/PonderToken.sol";

contract PonderTokenTest is Test {
    PonderToken token;
    address treasury = address(0x3);
    address teamReserve = address(0x4);
    address marketing = address(0x5);

    // Declare events used in the contract
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TeamTokensClaimed(uint256 amount);
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);

    function setUp() public {
        token = new PonderToken(treasury, teamReserve, marketing, address(this));
    }

    function testInitialState() public {
        assertEq(token.name(), "Koi");
        assertEq(token.symbol(), "KOI");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 450_000_000e18);
        assertEq(token.owner(), address(this));
        assertEq(token.minter(), address(0));
        assertEq(token.MAXIMUM_SUPPLY(), 1_000_000_000e18);
    }

    function testInitialAllocations() public {
        assertEq(token.balanceOf(token.treasury()), 250_000_000e18); // Treasury allocation
        assertEq(token.balanceOf(token.teamReserve()), 0);          // Team allocation starts at 0
        assertEq(token.balanceOf(token.marketing()), 100_000_000e18); // Marketing allocation
        assertEq(token.totalSupply(), 450_000_000e18);             // Total initial supply
    }

    function testSetMinter() public {
        vm.expectEmit(true, true, false, false);
        emit MinterUpdated(address(0), address(0x1));
        token.setMinter(address(0x1));
        assertEq(token.minter(), address(0x1));
    }

    function testFailSetMinterUnauthorized() public {
        vm.prank(address(0x1));
        token.setMinter(address(0x2));
    }

    function testMinting() public {
        token.setMinter(address(this));
        token.mint(address(0x1), 1000e18);
        assertEq(token.totalSupply(), 450_001_000e18);
        assertEq(token.balanceOf(address(0x1)), 1000e18);
    }

    function testFailMintOverMaxSupply() public {
        token.setMinter(address(this));
        token.mint(address(0x1), token.MAXIMUM_SUPPLY() + 1);
    }

    function testFailMintUnauthorized() public {
        vm.prank(address(0x1));
        token.mint(address(0x1), 1000);
    }

    function testMintingDeadline() public {
        token.setMinter(address(this));

        // Can mint before deadline
        token.mint(address(0x1), 1000e18);

        // Warp to just before deadline
        vm.warp(block.timestamp + 4 * 365 days - 1);
        token.mint(address(0x1), 1000e18);

        // Warp past deadline
        vm.warp(block.timestamp + 2);
        vm.expectRevert(PonderToken.MintingDisabled.selector);
        token.mint(address(0x1), 1000e18);
    }

    function testOwnershipTransfer() public {
        // Start transfer
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(address(this), address(0x1));
        token.transferOwnership(address(0x1));
        assertEq(token.pendingOwner(), address(0x1));

        // Complete transfer
        vm.prank(address(0x1));
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), address(0x1));
        token.acceptOwnership();

        assertEq(token.owner(), address(0x1));
        assertEq(token.pendingOwner(), address(0));
    }

    function testFailTransferOwnershipUnauthorized() public {
        vm.prank(address(0x1));
        token.transferOwnership(address(0x2));
    }

    function testFailAcceptOwnershipUnauthorized() public {
        token.transferOwnership(address(0x1));
        vm.prank(address(0x2));
        token.acceptOwnership();
    }

    function testFailZeroAddressOwner() public {
        token.transferOwnership(address(0));
    }

    function testFailZeroAddressMinter() public {
        token.setMinter(address(0));
    }

    function testTeamTokensClaiming() public {
        // Assert initial state of teamReserve balance
        assertEq(token.balanceOf(token.teamReserve()), 0);

        // Halfway through vesting
        vm.warp(block.timestamp + 365 days / 2);
        uint256 halfVested = token.TEAM_ALLOCATION() / 2;

        // Claim halfway vested tokens
        vm.prank(teamReserve); // Simulate call from teamReserve
        token.claimTeamTokens();
        assertEq(token.balanceOf(token.teamReserve()), halfVested);

        // Full vesting duration
        vm.warp(block.timestamp + 365 days / 2);
        uint256 totalVested = token.TEAM_ALLOCATION();

        // Claim fully vested tokens
        vm.prank(teamReserve); // Simulate call from teamReserve
        token.claimTeamTokens();
        assertEq(token.balanceOf(token.teamReserve()), totalVested);

        // No tokens should remain
        vm.prank(teamReserve); // Simulate call from teamReserve
        vm.expectRevert(PonderToken.NoTokensAvailable.selector);
        token.claimTeamTokens();
    }


    function testFailTeamTokensClaimBeforeStart() public {
        vm.warp(block.timestamp - 1); // Before vesting starts
        token.claimTeamTokens();
    }

    function testVestingCannotExceedAllocation() public {
        // Assert initial state of teamReserve balance
        assertEq(token.balanceOf(token.teamReserve()), 0);

        // Warp to beyond the vesting duration
        vm.warp(block.timestamp + token.VESTING_DURATION() + 1);

        // Claim all remaining vested tokens
        vm.prank(teamReserve); // Simulate call from teamReserve
        token.claimTeamTokens();
        assertEq(token.balanceOf(token.teamReserve()), token.TEAM_ALLOCATION());
        assertEq(token.totalSupply(), 450_000_000e18 + token.TEAM_ALLOCATION());
    }


    function testFailMintingBeyondMaxSupply() public {
        token.setMinter(address(this));
        uint256 remainingSupply = token.MAXIMUM_SUPPLY() - token.totalSupply();
        token.mint(address(0x1), remainingSupply);
        token.mint(address(0x1), 1); // Should fail
    }

    function testFailMintingAfterDeadline() public {
        token.setMinter(address(this));
        vm.warp(block.timestamp + token.MINTING_END() + 1);
        token.mint(address(0x1), 1000e18);
    }

    function testTreasuryTokenAllocation() public {
        assertEq(token.balanceOf(token.treasury()), 250_000_000e18); // Verify treasury allocation
    }

    function testMarketingTokenAllocation() public {
        assertEq(token.balanceOf(token.marketing()), 100_000_000e18); // Verify marketing allocation
    }

    function testInitialStateWithNoLauncher() public {
        // Deploy with no launcher
        PonderToken noLauncherToken = new PonderToken(
            treasury,
            teamReserve,
            marketing,
            address(0)
        );

        assertEq(noLauncherToken.launcher(), address(0));

        // Test setting launcher
        vm.expectEmit(true, true, false, false);
        emit LauncherUpdated(address(0), address(0x123));

        vm.prank(address(this));
        noLauncherToken.setLauncher(address(0x123));

        assertEq(noLauncherToken.launcher(), address(0x123));
    }

    function testSetLauncher() public {
        address newLauncher = address(0x123);

        vm.expectEmit(true, true, false, false);
        emit LauncherUpdated(address(this), newLauncher);

        token.setLauncher(newLauncher);
        assertEq(token.launcher(), newLauncher);
    }

    // Change from testRevertlSetLauncherUnauthorized to:
    function testRevertSetLauncherUnauthorized() public {
        vm.expectRevert(PonderToken.Forbidden.selector);
        vm.prank(address(0x456));
        token.setLauncher(address(0x123));
    }

    function testRevertSetLauncherToZero() public {
        vm.expectRevert(PonderToken.ZeroAddress.selector);
        token.setLauncher(address(0));
    }
}
