// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/WETH9.sol";
import "../mocks/MockKKUBUnwrapper.sol";

contract LaunchTokenTest is Test {
    LaunchToken token;
    PonderToken ponder;
    PonderFactory factory;
    PonderRouter router;
    WETH9 weth;

    address owner = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address creator = makeAddr("creator");
    address feeCollector = makeAddr("feeCollector");
    address treasury = makeAddr("treasury");
    address launcher = makeAddr("launcher");

    uint256 constant INITIAL_LIQUIDITY = 100e18;
    uint256 constant TEST_AMOUNT = 100e18;
    uint256 constant FEE_TEST_AMOUNT = 1000e18;

    event VestingInitialized(address indexed creator, uint256 amount, uint256 startTime, uint256 endTime);
    event TokensClaimed(address indexed creator, uint256 amount);
    event CreatorFeePaid(address indexed creator, uint256 amount, address pair);
    event ProtocolFeePaid(uint256 amount, address pair);
    event TransfersEnabled();
    event PairsSet(address kubPair, address ponderPair);
    event LauncherTransferred(address indexed previousLauncher, address indexed newLauncher);
    event NewPendingLauncher(address indexed previousPending, address indexed newPending);

    function setUp() public {
        // Deploy core contracts
        weth = new WETH9();
        ponder = new PonderToken(treasury, treasury, launcher);
        factory = new PonderFactory(address(this), launcher, address(1));

        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        // Deploy launch token
        token = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Create trading pairs
        address kubPair = factory.createPair(address(token), address(weth));
        address ponderPair = factory.createPair(address(token), address(ponder));

        // Set pairs and initialize token
        vm.startPrank(launcher);
        vm.expectEmit(true, true, true, true);
        emit PairsSet(kubPair, ponderPair);
        token.setPairs(kubPair, ponderPair);

        token.setupVesting(creator, TEST_AMOUNT);
        token.enableTransfers();

        // Setup initial balances
        token.transfer(alice, TEST_AMOUNT * 10);
        token.transfer(bob, TEST_AMOUNT * 10);
        vm.stopPrank();
    }

    function testFailSetPairsUnauthorized() public {
        vm.prank(alice);
        token.setPairs(address(0x123), address(0x456));
    }

    function testFailSetPairsTwice() public {
        vm.startPrank(launcher);
        token.setPairs(address(0x123), address(0x456));
        token.setPairs(address(0x789), address(0xabc));
        vm.stopPrank();
    }

    function testVestingClaim() public {
        uint256 vestAmount = TEST_AMOUNT;

        vm.warp(block.timestamp + 90 days);

        vm.startPrank(creator);
        uint256 expectedClaim = vestAmount / 2;
        vm.expectEmit(true, false, false, true);
        emit TokensClaimed(creator, expectedClaim);
        token.claimVestedTokens();
        vm.stopPrank();

        assertEq(token.balanceOf(creator), expectedClaim, "Incorrect vested amount claimed");
        assertEq(token.vestedClaimed(), expectedClaim, "Incorrect vested amount recorded");
    }

    function testInitialState() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.launcher(), launcher);
        assertEq(address(token.FACTORY()), address(factory));
        assertEq(address(token.ROUTER()), address(router));
        assertEq(address(token.PONDER()), address(ponder));
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertTrue(token.transfersEnabled());
        assertNotEq(token.kubPair(), address(0));
        assertNotEq(token.ponderPair(), address(0));
    }


    function testCannotSetupVestingWithInvalidParams() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.startPrank(launcher);

        // Test 1: Zero address creator
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.InvalidCreator.selector));
        newToken.setupVesting(address(0), TEST_AMOUNT);

        // Test 2: Zero amount
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.InvalidAmount.selector));
        newToken.setupVesting(creator, 0);

        // Test 3: Excessive amount
        uint256 totalSupply = newToken.TOTAL_SUPPLY();
        uint256 excessiveAmount = totalSupply + 1;

        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ExcessiveAmount.selector));
        newToken.setupVesting(creator, excessiveAmount);

        vm.stopPrank();
    }

    function testCannotSetupExcessiveVestingAmount() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        uint256 totalSupply = newToken.TOTAL_SUPPLY();
        uint256 excessiveAmount = totalSupply + 1 ether; // Make sure it's clearly excessive

        vm.startPrank(launcher);
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.ExcessiveAmount.selector));
        newToken.setupVesting(creator, excessiveAmount);
        vm.stopPrank();
    }

    function testCannotClaimBeforeVestingInitialized() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("VestingNotInitialized()"));
        newToken.claimVestedTokens();
    }

    function testCannotReinitializeVesting() public {
        vm.startPrank(launcher);
        vm.expectRevert(abi.encodeWithSignature("VestingAlreadyInitialized()"));
        token.setupVesting(creator, TEST_AMOUNT);
        vm.stopPrank();
    }

    function testCannotClaimMoreThanLauncherBalance() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.startPrank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);
        newToken.transfer(address(1), newToken.balanceOf(launcher));
        vm.stopPrank();

        vm.warp(block.timestamp + newToken.VESTING_DURATION());

        vm.startPrank(creator);
        vm.expectRevert(abi.encodeWithSignature("InsufficientLauncherBalance()"));
        newToken.claimVestedTokens();
        vm.stopPrank();
    }

    function testCannotManipulateVestingThroughTransferBypass() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Setup initial vesting
        vm.prank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);

        // Try to claim through a transfer manipulation
        vm.prank(creator);
        vm.expectRevert(); // Should fail
        newToken.transferFrom(launcher, creator, TEST_AMOUNT);
    }

    function testVestingStateConsistency() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.startPrank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);

        // Try to manipulate state through multiple paths
        vm.expectRevert();
        newToken.setupVesting(creator, TEST_AMOUNT / 2); // Try to reduce amount

        // Transfer some tokens away
        newToken.transfer(address(1), newToken.balanceOf(launcher) / 2);
        vm.stopPrank();

        // Fast forward to vesting completion
        vm.warp(block.timestamp + newToken.VESTING_DURATION());

        // Verify vesting amount remains unchanged
        (uint256 total,,,,) = newToken.getVestingInfo();
        assertEq(total, TEST_AMOUNT, "Vesting amount should not change");
    }

    function testCannotClaimTooFrequently() public {
        // Deploy fresh token instance
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Setup vesting
        vm.prank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);

        // Advance to middle of vesting period
        vm.warp(block.timestamp + newToken.VESTING_DURATION() / 2);

        // First claim should succeed
        vm.prank(creator);
        newToken.claimVestedTokens();

        // Second immediate claim should fail
        vm.expectRevert(abi.encodeWithSignature("ClaimTooFrequent()"));
        vm.prank(creator);
        newToken.claimVestedTokens();
    }

    function testCompleteVestingLifecycle() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.prank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);

        // Claim at 50% vesting
        vm.warp(block.timestamp + newToken.VESTING_DURATION() / 2);
        vm.prank(creator);
        newToken.claimVestedTokens();

        uint256 expectedHalf = TEST_AMOUNT / 2;
        assertApproxEqRel(
            newToken.vestedClaimed(),
            expectedHalf,
            0.01e18, // 1% tolerance for rounding
            "Should claim approximately half"
        );

        // Advance time and claim remaining
        vm.warp(block.timestamp + newToken.VESTING_DURATION() + newToken.MIN_CLAIM_INTERVAL());
        vm.prank(creator);
        newToken.claimVestedTokens();

        // Should claim full amount (with small rounding tolerance)
        assertApproxEqRel(
            newToken.vestedClaimed(),
            TEST_AMOUNT,
            0.01e18,
            "Should claim full amount"
        );
    }

    function testGetVestingInfo() public {
        vm.warp(block.timestamp + token.VESTING_DURATION() / 4);  // 25% through vesting

        (
            uint256 total,
            uint256 claimed,
            uint256 available,
            uint256 start,
            uint256 end
        ) = token.getVestingInfo();

        assertEq(total, TEST_AMOUNT, "Incorrect total vesting amount");
        assertEq(claimed, 0, "Should not have claimed any tokens");
        assertApproxEqRel(available, TEST_AMOUNT / 4, 0.01e18, "Available amount should be ~25%");
        assertGt(start, 0, "Invalid vesting start time");
        assertEq(end, start + token.VESTING_DURATION(), "Invalid vesting end time");
    }

    function testNoClaimAmountManipulation() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.startPrank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);
        vm.stopPrank();

        // Try claiming at different intervals
        for(uint256 i = 1; i <= 4; i++) {
            // Move forward 25% each time
            vm.warp(block.timestamp + newToken.VESTING_DURATION() / 4);

            uint256 preClaim = newToken.vestedClaimed();
            vm.prank(creator);
            newToken.claimVestedTokens();
            uint256 postClaim = newToken.vestedClaimed();

            uint256 claimAmount = postClaim - preClaim;
            assertApproxEqRel(
                claimAmount,
                TEST_AMOUNT / 4,
                0.01e18,
                "Claim amount should be ~25%"
            );

            // Wait for next claim interval
            vm.warp(block.timestamp + newToken.MIN_CLAIM_INTERVAL());
        }

        assertApproxEqRel(
            newToken.vestedClaimed(),
            TEST_AMOUNT,
            0.01e18,
            "Total claimed should equal total vested"
        );
    }

    function testPartialVestingClaims() public {
        // Advance to 25% through vesting period
        vm.warp(block.timestamp + token.VESTING_DURATION() / 4);

        vm.prank(creator);
        token.claimVestedTokens();

        assertApproxEqRel(
            token.vestedClaimed(),
            TEST_AMOUNT / 4,
            0.01e18,
            "First claim should be ~25%"
        );
    }

    function testClaimLimitsAndTiming() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        vm.prank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);

        // Test claim at 25% vesting
        vm.warp(block.timestamp + newToken.VESTING_DURATION() / 4);
        vm.prank(creator);
        newToken.claimVestedTokens();

        assertApproxEqRel(
            newToken.vestedClaimed(),
            TEST_AMOUNT / 4,
            0.01e18,
            "First claim should be ~25%"
        );
    }

    function testNoReentrancyInClaim() public {
        ReentrancyTestToken newToken = new ReentrancyTestToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        ReentrancyAttacker attacker = new ReentrancyAttacker(address(newToken));

        vm.startPrank(launcher);
        newToken.setupVesting(address(attacker), TEST_AMOUNT);
        newToken.enableTransfers();
        vm.stopPrank();

        vm.warp(block.timestamp + newToken.VESTING_DURATION() / 2);

        // Use the exact custom error selector
        bytes4 customError = bytes4(keccak256("ReentrancyGuardReentrantCall()"));
        vm.expectRevert(customError);
        attacker.attack();
    }

    function testVestingInitializationSafety() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Test initialization state
        assertFalse(newToken.isVestingInitialized(), "Should not be initialized");

        // Setup vesting
        vm.prank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);

        // Verify initialization
        assertTrue(newToken.isVestingInitialized(), "Should be initialized");

        // Verify cannot initialize again
        vm.expectRevert(abi.encodeWithSignature("VestingAlreadyInitialized()"));
        vm.prank(launcher);
        newToken.setupVesting(creator, TEST_AMOUNT);
    }

    function testVestingAmountSafety() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Transfer most tokens away from launcher to create a low balance scenario
        vm.startPrank(launcher);
        uint256 transferAmount = newToken.TOTAL_SUPPLY() - 1 ether;
        newToken.transfer(address(1), transferAmount);

        // Try to vest more than launcher's remaining balance
        vm.expectRevert(abi.encodeWithSelector(LaunchToken.InsufficientLauncherBalance.selector));
        newToken.setupVesting(creator, 2 ether); // Try to vest more than remaining balance
        vm.stopPrank();
    }

    function testTransferLauncher() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Test failed transfer from non-launcher
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        newToken.transferLauncher(alice);

        // Test failed transfer to zero address
        vm.prank(launcher);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        newToken.transferLauncher(address(0));

        // Test successful transfer initiation
        vm.startPrank(launcher);
        vm.expectEmit(true, true, false, true);
        emit NewPendingLauncher(address(0), alice);
        newToken.transferLauncher(alice);
        assertEq(newToken.pendingLauncher(), alice);
        vm.stopPrank();

        // Test failed acceptance from wrong address
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NotPendingLauncher()"));
        newToken.acceptLauncher();

        // Test successful acceptance
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit LauncherTransferred(launcher, alice);
        newToken.acceptLauncher();

        // Verify final state
        assertEq(newToken.launcher(), alice);
        assertEq(newToken.pendingLauncher(), address(0));

        // Verify launcher controls transfer after ownership change
        vm.prank(alice);
        newToken.transferLauncher(bob);
        assertEq(newToken.pendingLauncher(), bob);
    }

    function testMaintenanceOfLauncherPrivileges() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Store initial launcher balance
        uint256 initialBalance = newToken.balanceOf(launcher);

        // Transfer launcher role
        vm.prank(launcher);
        newToken.transferLauncher(alice);

        vm.prank(alice);
        newToken.acceptLauncher();

        // Verify token balance transferred
        assertEq(newToken.balanceOf(alice), initialBalance, "New launcher should receive tokens");
        assertEq(newToken.balanceOf(launcher), 0, "Old launcher should have no tokens");

        // Verify new launcher can use launcher-only functions
        vm.startPrank(alice);
        newToken.setupVesting(creator, TEST_AMOUNT);
        newToken.enableTransfers();
        vm.stopPrank();

        // Verify old launcher cannot use functions
        vm.startPrank(launcher);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        newToken.setupVesting(creator, TEST_AMOUNT);
        vm.stopPrank();
    }

    function testCannotReacceptLauncher() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Setup transfer
        vm.prank(launcher);
        newToken.transferLauncher(alice);

        // Accept transfer
        vm.prank(alice);
        newToken.acceptLauncher();

        // Try to accept again
        vm.expectRevert(abi.encodeWithSignature("NotPendingLauncher()"));
        vm.prank(alice);
        newToken.acceptLauncher();
    }

    function testTradingRestrictions() public {
        LaunchToken newToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Create pairs first
        address launchKubPair = factory.createPair(address(newToken), address(weth));

        vm.startPrank(launcher);
        newToken.setPairs(launchKubPair, address(0));
        newToken.enableTransfers();
        vm.stopPrank();

        // Create contract and normal user
        address maliciousContract = makeAddr("maliciousContract");
        vm.etch(maliciousContract, hex"6080604052"); // Simple bytecode
        address normalUser = makeAddr("normalUser");

        // Fund accounts
        deal(address(newToken), maliciousContract, 1 ether);
        deal(address(newToken), normalUser, 1 ether);

        // Test contract sending
        vm.startPrank(maliciousContract);
        vm.expectRevert(abi.encodeWithSignature("ContractBuyingRestricted()"));
        newToken.transfer(normalUser, 0.1 ether);
        vm.stopPrank();

        // Test contract receiving
        vm.startPrank(normalUser);
        vm.expectRevert(abi.encodeWithSignature("ContractBuyingRestricted()"));
        newToken.transfer(maliciousContract, 0.1 ether);
        vm.stopPrank();

        // Test max tx limit
        uint256 maxTx = newToken.TOTAL_SUPPLY() / 200; // 0.5% limit

        // Fund user with enough tokens for the test
        deal(address(newToken), normalUser, maxTx * 3); // Ensure enough balance for all tests

        vm.startPrank(normalUser);

        // Test exceeding max tx limit
        vm.expectRevert(abi.encodeWithSignature("MaxTransferExceeded()"));
        newToken.transfer(address(0x123), maxTx + 1);

        // Test exact max tx limit (should work)
        newToken.transfer(address(0x123), maxTx);
        vm.stopPrank();

        // Verify restrictions lift after period
        vm.warp(block.timestamp + 16 minutes);

        // Contract transfers should work both ways
        vm.prank(maliciousContract);
        newToken.transfer(normalUser, 0.5 ether);

        vm.prank(normalUser);
        newToken.transfer(maliciousContract, 0.5 ether);

        // Test large transfer after restrictions are lifted
        vm.startPrank(normalUser);
        uint256 userBalance = newToken.balanceOf(normalUser);
        newToken.transfer(address(0x123), userBalance - 1); // Transfer almost all balance
        vm.stopPrank();
    }

    receive() external payable {}
}

contract ReentrancyAttacker {
    LaunchToken public immutable token;
    bool public attacking;

    constructor(address _token) {
        token = LaunchToken(_token);
    }

    function attack() external {
        attacking = true;
        token.claimVestedTokens();
    }

    function onTokenTransfer(address, uint256) external returns (bool) {
        if (attacking) {
            attacking = false;
            token.claimVestedTokens();
        }
        return true;
    }
}


error ReentrancyGuard__ReentrantCall();

contract ReentrancyTestToken is LaunchToken {
    constructor(
        string memory _name,
        string memory _symbol,
        address _launcher,
        address _factory,
        address payable _router,
        address _ponder
    ) LaunchToken(_name, _symbol, _launcher, _factory, _router, _ponder) {}

    // Override _update to add callback functionality
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._update(from, to, amount);

        // If recipient is a contract and not a special address, try the callback
        if (to.code.length > 0 &&
        to != address(ROUTER) &&
        to != kubPair &&
            to != ponderPair) {
            ReentrancyAttacker(to).onTokenTransfer(from, amount);
        }
    }
}

contract MockMaliciousContract {
    function isContract() public view returns (bool) {
        return true;
    }
}
