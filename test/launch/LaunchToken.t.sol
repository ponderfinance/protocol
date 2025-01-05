// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderToken.sol";
import "../../src/periphery/PonderRouter.sol";
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

    function testPartialVestingClaims() public {
        uint256 vestAmount = TEST_AMOUNT;

        // First claim at 25%
        vm.warp(block.timestamp + 45 days);
        vm.startPrank(creator);
        token.claimVestedTokens();
        uint256 firstClaim = token.vestedClaimed();
        assertApproxEqRel(firstClaim, vestAmount / 4, 0.01e18, "First claim should be ~25%");

        // Second claim at 75%
        vm.warp(block.timestamp + 90 days);
        token.claimVestedTokens();
        uint256 secondClaim = token.vestedClaimed() - firstClaim;
        assertApproxEqRel(secondClaim, vestAmount / 2, 0.01e18, "Second claim should be ~50%");
        vm.stopPrank();
    }

    function testGetVestingInfo() public {
        uint256 vestAmount = TEST_AMOUNT;
        uint256 startTime = block.timestamp;

        vm.warp(block.timestamp + 45 days);

        (
            uint256 total,
            uint256 claimed,
            uint256 available,
            uint256 start,
            uint256 end
        ) = token.getVestingInfo();

        assertEq(total, vestAmount, "Incorrect total vesting amount");
        assertEq(claimed, 0, "Should not have claimed any tokens");
        assertApproxEqRel(available, vestAmount / 4, 0.01e18, "Available amount should be ~25%");
        assertEq(start, startTime, "Incorrect vesting start time");
        assertEq(end, startTime + token.VESTING_DURATION(), "Incorrect vesting end time");
    }

    function testInitialState() public {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.launcher(), launcher);
        assertEq(address(token.factory()), address(factory));
        assertEq(address(token.router()), address(router));
        assertEq(address(token.ponder()), address(ponder));
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertTrue(token.transfersEnabled());
        assertNotEq(token.kubPair(), address(0));
        assertNotEq(token.ponderPair(), address(0));
    }

    receive() external payable {}
}
