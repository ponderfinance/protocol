// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/core/token/PonderToken.sol";

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
    event TokensBurned(address indexed burner, uint256 amount);

    function setUp() public {
        token = new PonderToken(teamReserve, marketing, address(this));
    }

    function testInitialState() public {
        assertEq(token.name(), "Koi");
        assertEq(token.symbol(), "KOI");
        assertEq(token.decimals(), 18);
        // Initial supply = Initial Liquidity + Marketing = 200M + 150M = 350M
        assertEq(token.totalSupply(), 350_000_000e18);
        assertEq(token.owner(), address(this));
        assertEq(token.minter(), address(0));
        assertEq(token.maximumSupply(), 1_000_000_000e18);
    }

    function testInitialAllocations() public {
        assertEq(token.balanceOf(token.teamReserve()), 0);          // Team allocation starts at 0 (vested)
        assertEq(token.balanceOf(token.marketing()), 150_000_000e18); // Marketing allocation (15%)
        assertEq(token.totalSupply(), 350_000_000e18);             // 200M liquidity + 150M marketing
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
        assertEq(token.totalSupply(), 350_001_000e18); // 350M + 1000
        assertEq(token.balanceOf(address(0x1)), 1000e18);
    }

    function testFailMintOverMaxSupply() public {
        token.setMinter(address(this));
        token.mint(address(0x1), token.maximumSupply() + 1);
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
        vm.expectRevert(PonderTokenTypes.MintingDisabled.selector);
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
        uint256 halfVested = token.teamAllocation() / 2;

        // Claim halfway vested tokens
        vm.prank(teamReserve); // Simulate call from teamReserve
        token.claimTeamTokens();
        assertEq(token.balanceOf(token.teamReserve()), halfVested);

        // Full vesting duration
        vm.warp(block.timestamp + 365 days / 2);
        uint256 totalVested = token.teamAllocation();

        // Claim fully vested tokens
        vm.prank(teamReserve); // Simulate call from teamReserve
        token.claimTeamTokens();
        assertEq(token.balanceOf(token.teamReserve()), totalVested);

        // No tokens should remain
        vm.prank(teamReserve); // Simulate call from teamReserve
        vm.expectRevert(PonderTokenTypes.NoTokensAvailable.selector);
        token.claimTeamTokens();
    }


    function testClaimBeforeVestingStart() public {
        // Set time explicitly before vesting start
        vm.warp(token.teamVestingStart() - 1);

        vm.prank(teamReserve);
        // Should revert with VestingNotStarted
        vm.expectRevert(PonderTokenTypes.VestingNotStarted.selector);
        token.claimTeamTokens();
    }

    function testVestingCannotExceedAllocation() public {
        // Assert initial state of teamReserve balance
        assertEq(token.balanceOf(token.teamReserve()), 0);

        // Warp to beyond the vesting duration
        vm.warp(block.timestamp + token.vestingDuration() + 1);

        // Claim all remaining vested tokens
        vm.prank(teamReserve); // Simulate call from teamReserve
        token.claimTeamTokens();
        // Total supply = Initial 350M + 250M team allocation
        assertEq(token.balanceOf(token.teamReserve()), 250_000_000e18); // 25% team allocation
        assertEq(token.totalSupply(), 600_000_000e18);
    }


    function testFailMintingBeyondMaxSupply() public {
        token.setMinter(address(this));
        uint256 remainingSupply = token.maximumSupply() - token.totalSupply();
        token.mint(address(0x1), remainingSupply);
        token.mint(address(0x1), 1); // Should fail
    }

    function testFailMintingAfterDeadline() public {
        token.setMinter(address(this));
        vm.warp(block.timestamp + token.mintingEnd() + 1);
        token.mint(address(0x1), 1000e18);
    }

    function testMarketingTokenAllocation() public {
        assertEq(token.balanceOf(token.marketing()), 150_000_000e18); // 15% marketing allocation
    }

    function testInitialStateWithNoLauncher() public {
        // Deploy with no launcher
        PonderToken noLauncherToken = new PonderToken(
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
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        vm.prank(address(0x456));
        token.setLauncher(address(0x123));
    }

    function testRevertSetLauncherToZero() public {
        vm.expectRevert(PonderTokenTypes.ZeroAddress.selector);
        token.setLauncher(address(0));
    }

    function testMintingWithReservedTeamAllocation() public {
        token.setMinter(address(this));

        // Initial supply is 350M (200M liquidity + 150M marketing)
        // Team has 250M reserved
        // So max mintable should be 400M (1B - 350M - 250M reserved)
        uint256 initialSupply = token.totalSupply();
        uint256 maxMintable = token.maximumSupply() - initialSupply - token.teamAllocation();

        // Should succeed: Minting up to available supply (excluding reserved)
        token.mint(address(0x1), maxMintable);

        // Should fail: Trying to mint more when considering reserved tokens
        vm.expectRevert(PonderTokenTypes.SupplyExceeded.selector);
        token.mint(address(0x1), 1e18);
    }

    function testTeamClaimAndMintingInteraction() public {
        token.setMinter(address(this));

        // Initial state
        uint256 initialSupply = token.totalSupply();

        // Mint some tokens first
        uint256 mintAmount = 300_000_000e18; // 300M
        token.mint(address(0x1), mintAmount);

        // Fast forward halfway through vesting
        vm.warp(block.timestamp + 182.5 days);

        // Team claims half their tokens
        vm.prank(teamReserve);
        token.claimTeamTokens();

        // Calculate remaining mintable considering claimed and unclaimed team tokens
        uint256 unclaimedTeam = token.teamAllocation() - token.teamTokensClaimed();
        uint256 currentSupply = token.totalSupply();
        uint256 remainingMintable = token.maximumSupply() - currentSupply - unclaimedTeam;

        // Should succeed: Minting remaining available amount
        token.mint(address(0x1), remainingMintable);

        // Should fail: Trying to mint more
        vm.expectRevert(PonderTokenTypes.SupplyExceeded.selector);
        token.mint(address(0x1), 1e18);
    }

    function testFullSupplyAllocation() public {
        token.setMinter(address(this));

        // Fast forward to fully vested
        vm.warp(block.timestamp + 365 days);

        // Team claims all tokens
        vm.prank(teamReserve);
        token.claimTeamTokens();

        // Calculate remaining mintable after team claim
        uint256 currentSupply = token.totalSupply();
        uint256 remainingMintable = token.maximumSupply() - currentSupply;

        // Should succeed: Mint remaining supply
        token.mint(address(0x1), remainingMintable);

        // Verify exact total supply
        assertEq(token.totalSupply(), token.maximumSupply(), "Total supply should equal max supply");

        // Should fail: Mint any more tokens
        vm.expectRevert(PonderTokenTypes.SupplyExceeded.selector);
        token.mint(address(0x1), 1e18);
    }

    function testConcurrentTeamClaimAndMinting() public {
        token.setMinter(address(this));

        // Test concurrent minting and claiming over vesting period
        for (uint i = 0; i < 4; i++) {
            // Advance 3 months
            vm.warp(block.timestamp + 91.25 days);

            // Team claims their portion
            vm.prank(teamReserve);
            token.claimTeamTokens();

            // Calculate safe mintable amount
            uint256 unclaimedTeam = token.teamAllocation() - token.teamTokensClaimed();
            uint256 currentSupply = token.totalSupply();
            uint256 safeMintAmount = token.maximumSupply() - currentSupply - unclaimedTeam;

            if (safeMintAmount > 0) {
                // Should succeed: Mint safe amount
                token.mint(address(0x1), safeMintAmount);

                // Should fail: Mint any more
                vm.expectRevert(PonderTokenTypes.SupplyExceeded.selector);
                token.mint(address(0x1), 1e18);
            }
        }

        // Verify final supply respects maximum
        assertLe(token.totalSupply(), token.maximumSupply(), "Total supply should not exceed maximum");
    }

    function testNoTokensAvailableRevert() public {
        // Set time to vesting start (will have 0 tokens vested)
        vm.warp(token.teamVestingStart());

        vm.prank(teamReserve);
        // Now should revert with NoTokensAvailable
        vm.expectRevert(PonderTokenTypes.NoTokensAvailable.selector);
        token.claimTeamTokens();
    }

    function testVestingStartTime() public {
        // Verify initial state
        assertEq(token.teamVestingStart(), block.timestamp);

        // Set time exactly at vesting start (0 tokens)
        vm.warp(token.teamVestingStart());

        vm.prank(teamReserve);
        // Should revert with NoTokensAvailable
        vm.expectRevert(PonderTokenTypes.NoTokensAvailable.selector);
        token.claimTeamTokens();

        // Move forward to have some tokens available
        vm.warp(block.timestamp + 1 days);

        // Should now succeed
        uint256 expectedVested = (token.teamAllocation() * 1 days) / token.vestingDuration();
        vm.prank(teamReserve);
        token.claimTeamTokens();
        assertEq(token.teamTokensClaimed(), expectedVested);
    }

    function testBurn() public {
        // Setup
        uint256 burnAmount = 1000e18;
        uint256 initialBalance = token.balanceOf(address(this));
        uint256 initialSupply = token.totalSupply();
        uint256 initialBurned = token.totalBurned();

        // Set launcher for access control
        token.setLauncher(address(this));

        // Perform burn
        token.burn(burnAmount);

        // Verify burn effects
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.totalBurned(), initialBurned + burnAmount);
        assertEq(token.balanceOf(address(this)), initialBalance - burnAmount);
    }

    function testRevertBurnUnauthorized() public {
        uint256 burnAmount = 1000e18;
        address unauthorized = address(0x123);

        vm.prank(unauthorized);
        vm.expectRevert(PonderTokenTypes.OnlyLauncherOrOwner.selector);
        token.burn(burnAmount);
    }

    function testRevertBurnTooSmall() public {
        // Set launcher for access control
        token.setLauncher(address(this));

        vm.expectRevert(abi.encodeWithSignature("BurnAmountTooSmall()"));
        token.burn(999);
    }


    function testRevertBurnTooLarge() public {
        // Set launcher for access control
        token.setLauncher(address(this));

        uint256 tooLarge = token.totalSupply() / 50; // 2% of supply
        vm.expectRevert(abi.encodeWithSignature("BurnAmountTooLarge()"));
        token.burn(tooLarge);
    }

    function testRevertBurnInsufficientBalance() public {
        address poorUser = address(0x123);
        uint256 burnAmount = 1000e18;

        // Set launcher to poor user to bypass access control
        token.setLauncher(poorUser);

        vm.prank(poorUser);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance()"));

        token.burn(burnAmount);
    }

    function testBurnEventEmission() public {
        uint256 burnAmount = 1000e18;
        token.setLauncher(address(this));

        vm.expectEmit(true, true, false, false);
        emit TokensBurned(address(this), burnAmount);
        token.burn(burnAmount);
    }

    function testDomainSeparatorInitial() public {
        bytes32 separator = token.domainSeparator();
        assertTrue(separator != bytes32(0), "Domain separator should not be zero");

        // Calculate expected separator
        bytes32 expectedSeparator = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes("Koi")),  // token name
                keccak256(bytes('1')),    // version
                block.chainid,
                address(token)
            )
        );
        assertEq(separator, expectedSeparator, "Initial domain separator should match expected");
    }

    function testDomainSeparatorAfterChainIdChange() public {
        bytes32 initialSeparator = token.domainSeparator();

        // Change chain ID
        vm.chainId(999);

        bytes32 newSeparator = token.domainSeparator();
        assertTrue(newSeparator != initialSeparator, "Domain separator should change with chain ID");

        // Verify new separator matches expected value
        bytes32 expectedNewSeparator = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes("Koi")),
                keccak256(bytes('1')),
                uint256(999), // new chain ID
                address(token)
            )
        );
        assertEq(newSeparator, expectedNewSeparator, "New domain separator should match expected");
    }

    function testPermitNormalOperation() public {
        // Setup accounts and values
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);  // Derive address from private key
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        // First mint some tokens to owner
        token.setMinter(address(this));
        token.mint(owner, value);

        // Create permit message hash
        bytes32 permitHash = keccak256(abi.encode(
            token.PERMIT_TYPEHASH(),
            owner,
            spender,
            value,
            token.nonces(owner),
            deadline
        ));

        // Create EIP-712 hash
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            token.domainSeparator(),
            permitHash
        ));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Execute permit
        token.permit(owner, spender, value, deadline, v, r, s);

        // Verify results
        assertEq(token.allowance(owner, spender), value, "Allowance should be set after permit");
        assertEq(token.nonces(owner), 1, "Nonce should be incremented");
    }

    function testPermitAcrossChains() public {
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        // Mint tokens to owner
        token.setMinter(address(this));
        token.mint(owner, value);

        // Create permit message hash
        bytes32 permitHash = keccak256(abi.encode(
            token.PERMIT_TYPEHASH(),
            owner,
            spender,
            value,
            token.nonces(owner),
            deadline
        ));

        // Create EIP-712 hash
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            token.domainSeparator(),
            permitHash
        ));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // Change chain ID
        vm.chainId(999);

        // Permit should fail because domainSeparator is different on new chain
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitExpired() public {
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp - 1; // expired

        // Mint tokens to owner
        token.setMinter(address(this));
        token.mint(owner, value);

        // Create permit message hash
        bytes32 permitHash = keccak256(abi.encode(
            token.PERMIT_TYPEHASH(),
            owner,
            spender,
            value,
            token.nonces(owner),
            deadline
        ));

        // Create EIP-712 hash
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            token.domainSeparator(),
            permitHash
        ));

        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSignature("PermitExpired()"));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitInvalidSignature() public {
        address owner = address(0x1);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        // Use wrong private key
        uint256 wrongPrivateKey = 0x5678;
        vm.startPrank(owner);

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                token.domainSeparator(),
                keccak256(abi.encode(
                    token.PERMIT_TYPEHASH(),
                    owner,
                    spender,
                    value,
                    token.nonces(owner),
                    deadline
                ))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        token.permit(owner, spender, value, deadline, v, r, s);
        vm.stopPrank();
    }

}
