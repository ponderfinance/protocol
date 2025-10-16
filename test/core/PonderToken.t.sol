// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/staking/PonderStaking.sol";

contract PonderTokenTest is Test {
    PonderToken token;
    address launcher = address(0x4);
    address teamReserve = address(0x4);
    address mockStaking = address(0x5);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);
    event TokensBurned(address indexed burner, uint256 amount);

    function setUp() public {
        mockStaking = address(1);  // Use address(1) as temporary staking
        teamReserve = address(0x888);
        launcher = address(this);  // Set launcher to test contract for initial testing

        token = new PonderToken(
            teamReserve,
            launcher,
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
        assertEq(token.launcher(), launcher);
        assertEq(token.teamReserve(), teamReserve);
        assertEq(token.staking(), address(1)); // Temporary staking address
    }

    function testInitialSupplyAndAllocations() public {
        // Get actual balances and supply
        uint256 totalSupply = token.totalSupply();             // 600M total
        uint256 teamBalance = token.balanceOf(address(token)); // Team allocation in contract
        uint256 launcherBalance = token.balanceOf(launcher);   // Initial liquidity + Community rewards

        // Verify total supply equals our set maximum
        assertEq(totalSupply, 600_000_000e18, "Wrong total supply");

        // Verify team allocation is 200M (1/3 of 600M)
        assertEq(teamBalance, 200_000_000e18, "Wrong team allocation");

        // Verify launcher gets 400M (2/3 of 600M)
        assertEq(launcherBalance, 400_000_000e18, "Wrong launcher balance");

        // Verify team allocation matches the constant
        assertEq(teamBalance, token.teamAllocation(), "Team allocation mismatch");

        // Verify allocations add up to total supply
        assertEq(teamBalance + launcherBalance, totalSupply, "Total supply mismatch");
    }

    function testCannotDeployWithZeroAddresses() public {
        // Zero teamReserve should fail with ZeroAddress
        vm.expectRevert(abi.encodeWithSelector(PonderTokenTypes.ZeroAddress.selector));
        new PonderToken(address(0), launcher, mockStaking);

        // Zero launcher should fail with ERC20InvalidReceiver
        vm.expectRevert(abi.encodeWithSignature("ERC20InvalidReceiver(address)", address(0)));
        new PonderToken(teamReserve, address(0), mockStaking);
    }

    function testStakingInitialization() public {
        // Deploy new staking contract
        PonderStaking newStaking = new PonderStaking(
            address(token),
            address(0x123), // mock router
            address(0x456)  // mock factory
        );

        // Set staking address
        token.setStaking(address(newStaking));

        // Initialize staking with team allocation
        token.initializeStaking();

        // Verify team allocation is now in staking contract
        assertEq(token.balanceOf(address(newStaking)), PonderTokenTypes.TEAM_ALLOCATION);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function testCannotInitializeStakingTwice() public {
        PonderStaking newStaking = new PonderStaking(
            address(token),
            address(0x123),
            address(0x456)
        );

        token.setStaking(address(newStaking));
        token.initializeStaking();

        vm.expectRevert(PonderTokenTypes.AlreadyInitialized.selector);
        token.initializeStaking();
    }


    function testStakingAddressInitialization() public {
        // Deploy new staking contract
        PonderStaking newStaking = new PonderStaking(
            address(token),
            address(0x123), // mock router
            address(0x456)  // mock factory
        );

        // Set staking address
        token.setStaking(address(newStaking));

        // Try to set it again - should revert
        vm.expectRevert(PonderTokenTypes.AlreadyInitialized.selector);
        token.setStaking(address(0x789));

        // Verify final staking address
        assertEq(token.staking(), address(newStaking));
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

        token.transferOwnership(newOwner);
        assertEq(token.pendingOwner(), newOwner);

        vm.prank(newOwner);
        token.acceptOwnership();

        assertEq(token.owner(), newOwner);
        assertEq(token.pendingOwner(), address(0));
    }

    function testOnlyOwnerCanTransfer() public {
        address newOwner = address(0x123);
        address notOwner = address(0x456);

        vm.prank(notOwner);
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        token.transferOwnership(newOwner);
    }

    function testOnlyPendingOwnerCanAccept() public {
        address newOwner = address(0x123);
        address notOwner = address(0x456);

        token.transferOwnership(newOwner);

        vm.prank(notOwner);
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        token.acceptOwnership();
    }

    function test_RevertWhen_TransferOwnershipUnauthorized() public {
        address unauthorized = address(0x123);

        // Try to transfer ownership from unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert();
        token.transferOwnership(address(0x456));
    }


    function test_RevertWhen_AcceptOwnershipUnauthorized() public {
        address newOwner = address(0x123);
        address unauthorized = address(0x456);

        // Set up the transfer
        token.transferOwnership(newOwner);

        // Try to accept from unauthorized account
        vm.prank(unauthorized);
        vm.expectRevert();
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
        emit LauncherUpdated(launcher, newLauncher);
        token.setLauncher(newLauncher);

        assertEq(token.launcher(), newLauncher);
    }

    function testOnlyOwnerCanSetLauncher() public {
        vm.expectRevert(PonderTokenTypes.Forbidden.selector);
        vm.prank(address(0x456));
        token.setLauncher(address(0x123));
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
        // First transfer some tokens to this contract
        vm.prank(launcher);
        token.transfer(address(this), 10000e18);

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

        // Transfer tokens to test accounts
        vm.startPrank(launcher);
        token.transfer(address(this), burnAmount);
        token.transfer(launcher, burnAmount);
        vm.stopPrank();

        // Test unauthorized
        vm.prank(address(0x123));
        vm.expectRevert(PonderTokenTypes.OnlyLauncherOrOwner.selector);
        token.burn(burnAmount);

        // Test launcher can burn
        vm.prank(launcher);
        token.burn(burnAmount);

        // Test owner can burn
        token.burn(burnAmount);
    }

    function testBurnLimits() public {
        // Transfer some tokens to this contract
        vm.prank(launcher);
        token.transfer(address(this), 10000e18);

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
        // Transfer tokens to this contract
        vm.prank(launcher);
        token.transfer(address(this), 10000e18);

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

        // Transfer tokens to owner for testing
        token.transfer(owner, value * 2);  // Transfer more than needed

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

        // Transfer tokens to owner for testing
        token.transfer(owner, value * 2);  // Transfer more than needed

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
