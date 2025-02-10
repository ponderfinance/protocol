// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/staking/PonderStaking.sol";

contract PonderTokenTest is Test {
    PonderToken token;
    address teamReserve = address(0x4);
    address mockStaking = address(0x5);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);
    event TokensBurned(address indexed burner, uint256 amount);

    function setUp() public {
        token = new PonderToken(
            teamReserve,
            address(this), // launcher
            mockStaking
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitialState() public {
        assertEq(token.name(), "Koi");
        assertEq(token.symbol(), "KOI");
        assertEq(token.decimals(), 18);
        assertEq(token.owner(), address(this));
        assertEq(token.launcher(), address(this));
        assertEq(token.teamReserve(), teamReserve);
        assertEq(address(token.staking()), mockStaking);
    }

    function testInitialSupplyAndAllocations() public {
        // Check total supply
        assertEq(token.totalSupply(), PonderTokenTypes.MAXIMUM_SUPPLY);

        // Check allocations
        assertEq(token.balanceOf(mockStaking), PonderTokenTypes.TEAM_ALLOCATION);
        assertEq(token.balanceOf(address(this)),
            PonderTokenTypes.INITIAL_LIQUIDITY + PonderTokenTypes.COMMUNITY_REWARDS);

        // Verify percentages
        assertEq(PonderTokenTypes.TEAM_ALLOCATION, PonderTokenTypes.MAXIMUM_SUPPLY / 5); // 20%
        assertEq(PonderTokenTypes.INITIAL_LIQUIDITY, 2 * PonderTokenTypes.MAXIMUM_SUPPLY / 5); // 40%
        assertEq(PonderTokenTypes.COMMUNITY_REWARDS, 2 * PonderTokenTypes.MAXIMUM_SUPPLY / 5); // 40%
    }

    function testCannotDeployWithZeroAddresses() public {
        vm.expectRevert(PonderTokenTypes.ZeroAddress.selector);
        new PonderToken(address(0), address(this), mockStaking);

        vm.expectRevert(PonderTokenTypes.ZeroAddress.selector);
        new PonderToken(teamReserve, address(this), address(0));
    }

    function testStakingAddressImmutable() public {
        address initialStaking = address(token.staking());
        // Verify there's no way to change it
        assertEq(address(token.staking()), initialStaking);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnershipTransfer() public {
        address newOwner = address(0x123);

        // Start transfer
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(address(this), newOwner);
        token.transferOwnership(newOwner);
        assertEq(token.pendingOwner(), newOwner);

        // Complete transfer
        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), newOwner);
        token.acceptOwnership();

        assertEq(token.owner(), newOwner);
        assertEq(token.pendingOwner(), address(0));
    }

    function testFailTransferOwnershipUnauthorized() public {
        vm.prank(address(0x123));
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        token.transferOwnership(address(0x456));
    }

    function testFailAcceptOwnershipUnauthorized() public {
        token.transferOwnership(address(0x123));
        vm.prank(address(0x456));
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        token.acceptOwnership();
    }

    function testCannotTransferOwnershipToZero() public {
        vm.expectRevert(PonderTokenTypes.ZeroAddress.selector);
        token.transferOwnership(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        LAUNCHER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetLauncher() public {
        address newLauncher = address(0x123);

        vm.expectEmit(true, true, false, false);
        emit LauncherUpdated(address(this), newLauncher);

        token.setLauncher(newLauncher);
        assertEq(token.launcher(), newLauncher);
    }

    function testCannotSetLauncherUnauthorized() public {
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        vm.prank(address(0x456));
        token.setLauncher(address(0x123));
    }

    function testCannotSetLauncherToZero() public {
        vm.expectRevert(PonderTokenTypes.ZeroAddress.selector);
        token.setLauncher(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function testBurn() public {
        uint256 burnAmount = 1000e18;
        uint256 initialBalance = token.balanceOf(address(this));
        uint256 initialSupply = token.totalSupply();
        uint256 initialBurned = token.totalBurned();

        token.burn(burnAmount);

        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.totalBurned(), initialBurned + burnAmount);
        assertEq(token.balanceOf(address(this)), initialBalance - burnAmount);
    }

    function testOnlyOwnerOrLauncherCanBurn() public {
        uint256 burnAmount = 1000e18;

        // Test unauthorized
        vm.prank(address(0x123));
        vm.expectRevert(PonderTokenTypes.OnlyLauncherOrOwner.selector);
        token.burn(burnAmount);

        // Test launcher can burn
        address newLauncher = address(0x789);
        token.setLauncher(newLauncher);

        vm.startPrank(newLauncher);
        token.burn(burnAmount);
        vm.stopPrank();
    }

    function testBurnLimits() public {
        // Test minimum burn
        vm.expectRevert(PonderTokenTypes.BurnAmountTooSmall.selector);
        token.burn(999);

        // Test maximum burn (>1% of supply)
        uint256 tooLarge = token.totalSupply() / 50; // 2%
        vm.expectRevert(PonderTokenTypes.BurnAmountTooLarge.selector);
        token.burn(tooLarge);
    }

    function testCannotBurnMoreThanBalance() public {
        address poorUser = address(0x123);
        uint256 burnAmount = 1000e18;

        token.setLauncher(poorUser);

        vm.prank(poorUser);
        vm.expectRevert(PonderTokenTypes.InsufficientBalance.selector);
        token.burn(burnAmount);
    }

    function testBurnEvent() public {
        uint256 burnAmount = 1000e18;

        vm.expectEmit(true, true, false, false);
        emit TokensBurned(address(this), burnAmount);
        token.burn(burnAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        PERMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testPermit() public {
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        // Transfer some tokens to owner for testing
        token.transfer(owner, value);

        // Create permit message
        bytes32 permitHash = keccak256(abi.encode(
            token.PERMIT_TYPEHASH(),
            owner,
            spender,
            value,
            token.nonces(owner),
            deadline
        ));

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            token.domainSeparator(),
            permitHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
        assertEq(token.nonces(owner), 1);
    }

    function testPermitExpired() public {
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp - 1;

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        vm.expectRevert(abi.encodeWithSignature("PermitExpired()"));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitInvalidSignature() public {
        uint256 ownerPrivateKey = 0x1234;
        uint256 wrongPrivateKey = 0x5678;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
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
    }

    function testPermitReplay() public {
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0x2);
        uint256 value = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        token.transfer(owner, value);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        // First permit should succeed
        token.permit(owner, spender, value, deadline, v, r, s);

        // Same permit should fail (nonce increased)
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                        DOMAIN SEPARATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testDomainSeparator() public {
        bytes32 separator = token.domainSeparator();

        bytes32 expectedSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Koi")),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );

        assertEq(separator, expectedSeparator);
    }

    function testDomainSeparatorChainId() public {
        bytes32 initialSeparator = token.domainSeparator();

        // Change chain ID
        vm.chainId(999);
        bytes32 newSeparator = token.domainSeparator();

        assertTrue(newSeparator != initialSeparator);
    }
}
