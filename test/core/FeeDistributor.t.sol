// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/core/FeeDistributor.sol";
import "../../src/core/PonderStaking.sol";
import "../../src/core/PonderToken.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";

contract ERC20Mock is PonderERC20 {
    constructor(string memory name, string memory symbol) PonderERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockFailingToken is PonderERC20 {
    constructor() PonderERC20("Failing", "FAIL") {}

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}


contract FeeDistributorTest is Test {
    FeeDistributor public distributor;
    PonderStaking public staking;
    PonderToken public ponder;
    PonderFactory public factory;
    PonderRouter public router;
    PonderPair public pair;

    address public owner;
    address public user1;
    address public treasury;
    address public teamReserve;
    address public marketing;
    address constant WETH = address(0x1234);

    // Test token for pairs
    ERC20Mock public testToken;

    uint256 constant BASIS_POINTS = 10000;

    event FeesDistributed(
        uint256 totalAmount,
        uint256 stakingAmount,
        uint256 treasuryAmount,
        uint256 teamAmount
    );

    event FeesCollected(address indexed token, uint256 amount);
    event FeesConverted(address indexed token, uint256 tokenAmount, uint256 ponderAmount);
    event DistributionRatiosUpdated(
        uint256 stakingRatio,
        uint256 treasuryRatio,
        uint256 teamRatio
    );

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        treasury = address(0x2);
        teamReserve = address(0x3);
        marketing = address(0x4);

        // Deploy core contracts
        factory = new PonderFactory(owner, address(0), address(0));

        router = new PonderRouter(
            address(factory),
            WETH,
            address(0) // No unwrapper needed for tests
        );

        ponder = new PonderToken(
            treasury,
            teamReserve,
            marketing,
            address(0)
        );

        staking = new PonderStaking(
            address(ponder),
            address(router),
            address(factory)
        );

        distributor = new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(staking),
            treasury,
            teamReserve
        );

        // Deploy test token and create pair
        testToken = new ERC20Mock("Test Token", "TEST");
        factory.createPair(address(ponder), address(testToken));
        pair = PonderPair(factory.getPair(address(ponder), address(testToken)));

        // Set fee collector
        factory.setFeeTo(address(distributor));

        // Setup initial liquidity
        _setupInitialLiquidity();
    }
    function _setupInitialLiquidity() internal {
        // Add initial liquidity with larger amounts
        uint256 ponderAmount = 1_000_000e18;
        uint256 tokenAmount = 1_000_000e18;

        // Send PONDER from treasury to this contract
        vm.startPrank(treasury);
        ponder.transfer(address(this), ponderAmount * 2); // Double the amount for trading
        vm.stopPrank();

        // Mint test tokens
        testToken.mint(address(this), tokenAmount * 2);

        // Approve tokens
        testToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        // Add initial liquidity
        router.addLiquidity(
            address(ponder),
            address(testToken),
            ponderAmount,
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function _generateTradingFees() internal {
        // First ensure much larger initial liquidity
        testToken.mint(address(this), 100_000_000e18);
        vm.prank(treasury);
        ponder.transfer(address(this), 100_000_000e18);

        // Add massive liquidity to the pair
        vm.startPrank(address(this));
        testToken.approve(address(pair), type(uint256).max);
        ponder.approve(address(pair), type(uint256).max);

        testToken.transfer(address(pair), 10_000_000e18);
        ponder.transfer(address(pair), 10_000_000e18);
        pair.mint(address(this));
        vm.stopPrank();

        // Do large swaps to generate significant fees
        for (uint i = 0; i < 10; i++) {
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
            uint256 swapAmount = uint256(reserve0) / 5; // 20% of reserves

            testToken.transfer(address(pair), swapAmount);
            // Calculate output amount considering total 0.3% fee (997/1000)
            uint256 amountOut = (swapAmount * 997 * reserve1) / ((reserve0 * 1000) + (swapAmount * 997));

            pair.swap(0, amountOut, address(this), "");

            // Call skim after each swap to collect protocol fees
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);

            (reserve0, reserve1,) = pair.getReserves();
            swapAmount = uint256(reserve1) / 5;
            ponder.transfer(address(pair), swapAmount);

            pair.swap(amountOut, 0, address(this), "");

            // Call skim after each swap
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);
            pair.sync();
        }
    }

    function test_InitialState() public {
        assertEq(address(distributor.factory()), address(factory));
        assertEq(address(distributor.router()), address(router));
        assertEq(address(distributor.ponder()), address(ponder));
        assertEq(address(distributor.staking()), address(staking));
        assertEq(distributor.treasury(), treasury);
        assertEq(distributor.team(), teamReserve);
        assertEq(distributor.stakingRatio(), 5000); // 50%
        assertEq(distributor.treasuryRatio(), 3000); // 30%
        assertEq(distributor.teamRatio(), 2000); // 20%
    }

    function test_CollectFeesFromPair() public {
        // Setup
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Store balances before collection
        uint256 prePonderBalance = ponder.balanceOf(address(distributor));
        uint256 preTokenBalance = testToken.balanceOf(address(distributor));

        // Let time pass and sync pair
        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        // Do an additional trade and skim
        testToken.mint(address(this), 1_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);
        testToken.transfer(address(pair), 1_000_000e18);
        // Calculate expected output with 0.3% total fee
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1,) = pair.getReserves();
        uint256 amountIn = 1_000_000e18;
        uint256 amountOut = (amountIn * 997 * uint256(reserve1)) / (uint256(reserve0) * 1000 + amountIn * 997);
        pair.swap(0, amountOut, address(this), "");
        pair.skim(address(distributor));

        // Collect fees
        distributor.collectFeesFromPair(address(pair));

        // Check balances after collection
        uint256 postPonderBalance = ponder.balanceOf(address(distributor));
        uint256 postTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(
            postPonderBalance > prePonderBalance || postTokenBalance > preTokenBalance,
            "Should collect fees"
        );
    }

    function test_ConvertFees() public {
        // Setup and generate fees
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Ensure some time passes
        vm.warp(block.timestamp + 1 hours);
        pair.sync();
        pair.skim(address(distributor));  // Make sure fees are collected

        // Make sure we have tokens to convert
        uint256 initialTestBalance = testToken.balanceOf(address(distributor));
        require(initialTestBalance > 0, "No test tokens to convert");

        uint256 initialPonderBalance = ponder.balanceOf(address(distributor));

        // Approve tokens for conversion
        vm.startPrank(address(distributor));
        testToken.approve(address(router), type(uint256).max);
        vm.stopPrank();

        // Convert fees
        distributor.convertFees(address(testToken));

        uint256 finalTestBalance = testToken.balanceOf(address(distributor));
        uint256 finalPonderBalance = ponder.balanceOf(address(distributor));

        // Check the relative differences instead of absolute values
        assertTrue(
            finalTestBalance <= initialTestBalance / 100,  // 99% converted
            "Should convert most test tokens"
        );
        assertTrue(
            finalPonderBalance > initialPonderBalance,
            "Should receive PONDER from conversion"
        );
    }

    function test_Distribute() public {
        // Setup and collect fees
        _generateTradingFees();
        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        distributor.collectFeesFromPair(address(pair));

        // Convert collected fees to PONDER
        vm.startPrank(address(distributor));
        testToken.approve(address(router), type(uint256).max);
        vm.stopPrank();
        distributor.convertFees(address(testToken));

        // Get total amount to distribute
        uint256 totalAmount = ponder.balanceOf(address(distributor));
        require(totalAmount >= distributor.MINIMUM_AMOUNT(), "Insufficient PONDER for distribution");

        // Calculate expected distributions
        uint256 expectedStaking = (totalAmount * distributor.stakingRatio()) / BASIS_POINTS;
        uint256 expectedTreasury = (totalAmount * distributor.treasuryRatio()) / BASIS_POINTS;
        uint256 expectedTeam = (totalAmount * distributor.teamRatio()) / BASIS_POINTS;

        // Record initial balances
        uint256 initialStaking = ponder.balanceOf(address(staking));
        uint256 initialTreasury = ponder.balanceOf(treasury);
        uint256 initialTeam = ponder.balanceOf(teamReserve);

        // Advance time for rebase and setup approvals
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(address(distributor));
        ponder.approve(address(staking), type(uint256).max);
        ponder.approve(treasury, type(uint256).max);
        ponder.approve(teamReserve, type(uint256).max);
        vm.stopPrank();

        // Distribute
        distributor.distribute();

        // Verify distributions with relative comparison
        uint256 stakingReceived = ponder.balanceOf(address(staking)) - initialStaking;
        uint256 treasuryReceived = ponder.balanceOf(treasury) - initialTreasury;
        uint256 teamReceived = ponder.balanceOf(teamReserve) - initialTeam;

        assertApproxEqRel(
            stakingReceived,
            expectedStaking,
            0.01e18, // 1% tolerance
            "Wrong staking distribution"
        );
        assertApproxEqRel(
            treasuryReceived,
            expectedTreasury,
            0.01e18,
            "Wrong treasury distribution"
        );
        assertApproxEqRel(
            teamReceived,
            expectedTeam,
            0.01e18,
            "Wrong team distribution"
        );

        // Verify distributor balance is nearly zero
        assertLt(
            ponder.balanceOf(address(distributor)),
            distributor.MINIMUM_AMOUNT(),
            "Should distribute almost all PONDER"
        );
    }

    function test_DistributePairFees() public {
        // Setup and generate fees
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Ensure time passes and sync
        vm.warp(block.timestamp + 1 days);
        pair.sync();

        // Setup pairs array
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // Record initial balances
        uint256 initialStaking = ponder.balanceOf(address(staking));
        uint256 initialTreasury = ponder.balanceOf(treasury);
        uint256 initialTeam = ponder.balanceOf(teamReserve);

        // Setup necessary approvals
        vm.startPrank(address(distributor));
        testToken.approve(address(router), type(uint256).max);
        ponder.approve(address(staking), type(uint256).max);
        ponder.approve(treasury, type(uint256).max);
        ponder.approve(teamReserve, type(uint256).max);
        vm.stopPrank();

        // Get initial balances
        uint256 initialTestBalance = testToken.balanceOf(address(distributor));

        // Distribute fees
        distributor.distributePairFees(pairs);

        // Get final balances
        uint256 finalTestBalance = testToken.balanceOf(address(distributor));

        // Check relative conversion instead of absolute values
        assertTrue(
            finalTestBalance <= initialTestBalance / 100,  // 99% converted
            "Should convert most test tokens"
        );

        // Check that each recipient received something
        assertTrue(
            ponder.balanceOf(address(staking)) > initialStaking &&
            ponder.balanceOf(treasury) > initialTreasury &&
            ponder.balanceOf(teamReserve) > initialTeam,
            "Should distribute to all recipients"
        );
    }

    function test_UpdateDistributionRatios() public {
        uint256 newStakingRatio = 6000; // 60%
        uint256 newTreasuryRatio = 2500; // 25%
        uint256 newTeamRatio = 1500; // 15%

        vm.expectEmit(true, true, true, true);
        emit DistributionRatiosUpdated(
            newStakingRatio,
            newTreasuryRatio,
            newTeamRatio
        );

        distributor.updateDistributionRatios(
            newStakingRatio,
            newTreasuryRatio,
            newTeamRatio
        );

        assertEq(distributor.stakingRatio(), newStakingRatio);
        assertEq(distributor.treasuryRatio(), newTreasuryRatio);
        assertEq(distributor.teamRatio(), newTeamRatio);
    }

    function test_RevertInvalidRatios() public {
        // Total > 100%
        vm.expectRevert(abi.encodeWithSignature("RatioSumIncorrect()"));
        distributor.updateDistributionRatios(5000, 3000, 3000);

        // Total < 100%
        vm.expectRevert(abi.encodeWithSignature("RatioSumIncorrect()"));
        distributor.updateDistributionRatios(5000, 2000, 2000);
    }

    function test_SetTreasury() public {
        address newTreasury = address(0x123);
        distributor.setTreasury(newTreasury);
        assertEq(distributor.treasury(), newTreasury);
    }

    function test_SetTeam() public {
        address newTeam = address(0x123);
        distributor.setTeam(newTeam);
        assertEq(distributor.team(), newTeam);
    }

    function test_RevertZeroAddresses() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        distributor.setTreasury(address(0));

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        distributor.setTeam(address(0));
    }

    function test_RevertUnauthorizedDistributionChange() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        distributor.updateDistributionRatios(6000, 2500, 1500);
    }

    function test_RevertUnauthorizedAddressChange() public {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        distributor.setTreasury(address(0x123));

        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        distributor.setTeam(address(0x123));

        vm.stopPrank();
    }

    function test_MultipleDistributions() public {
        // First distribution setup
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Record initial balances before any distributions
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));
        uint256 initialTreasuryBalance = ponder.balanceOf(treasury);
        uint256 initialTeamBalance = ponder.balanceOf(teamReserve);

        // First distribution
        vm.warp(block.timestamp + 1 hours);
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));
        vm.warp(block.timestamp + 1 days);
        distributor.distribute();

        // Generate new fees with smaller amounts
        vm.warp(block.timestamp + 1 days);

        // Setup smaller swaps
        uint256 smallSwapAmount = 1000e18;
        testToken.mint(address(this), smallSwapAmount);
        vm.prank(treasury);
        ponder.transfer(address(this), smallSwapAmount);

        // Setup approvals
        vm.startPrank(address(distributor));
        testToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);
        vm.stopPrank();

        // Do swap via pair directly to ensure fees
        vm.startPrank(address(this));
        testToken.transfer(address(pair), smallSwapAmount);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = (smallSwapAmount * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + smallSwapAmount * 997);

        pair.swap(0, amountOut, address(this), "");

        // Collect fees via skim
        pair.skim(address(distributor));
        vm.stopPrank();

        // Second distribution
        vm.warp(block.timestamp + 1 days);
        pair.sync();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));
        vm.warp(block.timestamp + 1 days);
        distributor.distribute();

        // Verify there were increases from initial balances
        assertGt(
            ponder.balanceOf(address(staking)),
            initialStakingBalance,
            "Staking balance should increase"
        );
        assertGt(
            ponder.balanceOf(treasury),
            initialTreasuryBalance,
            "Treasury balance should increase"
        );
        assertGt(
            ponder.balanceOf(teamReserve),
            initialTeamBalance,
            "Team balance should increase"
        );
    }

    function test_KValueMaintenance() public {
        // Setup and generate fees
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Get initial K value
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 initialK = uint256(reserve0) * uint256(reserve1);

        // Collect fees
        distributor.collectFeesFromPair(address(pair));

        // Try to swap - should work now because collectFeesFromPair includes sync
        testToken.mint(address(this), 1000e18);
        testToken.transfer(address(pair), 1000e18);

        (reserve0, reserve1,) = pair.getReserves();
        uint256 amountOut = (1000e18 * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + 1000e18 * 997);

        // This should succeed
        pair.swap(0, amountOut, address(this), "");

        // Get final K value
        (uint112 finalReserve0, uint112 finalReserve1,) = pair.getReserves();
        uint256 finalK = uint256(finalReserve0) * uint256(finalReserve1);

        // K should either increase or stay the same
        assertGe(finalK, initialK, "K value should not decrease");
    }

    function test_CollectFeesAndSwap() public {
        // Setup and generate fees
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Collect fees without explicit sync
        distributor.collectFeesFromPair(address(pair));

        // Try to swap - this should work with proper syncing in collectFeesFromPair
        uint256 swapAmount = 1000e18;
        testToken.mint(address(this), swapAmount);
        testToken.transfer(address(pair), swapAmount);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = (swapAmount * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + swapAmount * 997);

        pair.swap(0, amountOut, address(this), "");

        // Verify swap succeeded
        assertTrue(ponder.balanceOf(address(this)) > 0, "Swap should succeed");
    }

    function _getAmountOut(
        uint256 amountIn,
        uint112 reserveIn,
        uint112 reserveOut
    ) internal pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * uint256(reserveOut);
        uint256 denominator = (uint256(reserveIn) * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function test_GetUniqueTokensEmptyArray() public {
        address[] memory emptyPairs = new address[](0);
        distributor.distributePairFees(emptyPairs);
        // If we get here without reverting, the test passed
    }

    function test_ConvertFeesWithPONDER() public {
        // Test that converting PONDER token returns early
        uint256 initialBalance = ponder.balanceOf(address(distributor));
        distributor.convertFees(address(ponder));
        assertEq(ponder.balanceOf(address(distributor)), initialBalance, "Should not convert PONDER");
    }

    function test_ConvertFeesInsufficientAmount() public {
        // Test converting amount below MINIMUM_AMOUNT
        testToken.mint(address(distributor), distributor.MINIMUM_AMOUNT() - 1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        distributor.convertFees(address(testToken));
    }

    function test_DistributeZeroAmounts() public {
        // Test distribution with amount below MINIMUM_AMOUNT
        vm.prank(treasury);
        ponder.transfer(address(distributor), distributor.MINIMUM_AMOUNT() - 1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        distributor.distribute();
    }

    function test_DistributeTransferFailures() public {
        // Setup mock token that fails transfers
        MockFailingToken failingPonder = new MockFailingToken();
        // Deploy new distributor with failing token
        FeeDistributor failingDistributor = new FeeDistributor(
            address(factory),
            address(router),
            address(failingPonder),
            address(staking),
            treasury,
            teamReserve
        );

        // Mint some tokens and attempt distribution
        failingPonder.mint(address(failingDistributor), 1000e18);
        vm.expectRevert(abi.encodeWithSignature("TransferFailed()"));
        failingDistributor.distribute();
    }

    function test_TransferOwnershipZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        distributor.transferOwnership(address(0));
    }

    function test_TransferOwnershipComplete() public {
        address newOwner = address(0x123);
        distributor.transferOwnership(newOwner);

        vm.prank(newOwner);
        distributor.acceptOwnership();
        assertEq(distributor.owner(), newOwner);
        assertEq(distributor.pendingOwner(), address(0));
    }

    function test_ConstructorZeroAddressValidation() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new FeeDistributor(
            address(0),  // _factory
            address(router),
            address(ponder),
            address(staking),
            treasury,
            teamReserve
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new FeeDistributor(
            address(factory),
            address(0),  // _router
            address(ponder),
            address(staking),
            treasury,
            teamReserve
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new FeeDistributor(
            address(factory),
            address(router),
            address(0),  // _ponder
            address(staking),
            treasury,
            teamReserve
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(0),  // _staking
            treasury,
            teamReserve
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(staking),
            address(0),  // _treasury
            teamReserve
        );

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(staking),
            treasury,
            address(0)  // _team
        );
    }

    function test_SwapFailure() public {
        // Setup scenario where swap would fail
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        // Mock router to fail swaps
        vm.mockCall(
            address(router),
            abi.encodeWithSelector(IPonderRouter.swapExactTokensForTokens.selector),
            abi.encode()
        );
        // Make the mock revert
        vm.expectRevert();
        vm.mockCallRevert(
            address(router),
            abi.encodeWithSelector(IPonderRouter.swapExactTokensForTokens.selector),
            "SWAP_FAILED"
        );

        // This should now revert with SwapFailed()
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.convertFees(address(testToken));
    }
    // Helper function to get balance with fallback
    function _getBalance(address token, address account) internal view returns (uint256) {
        try IERC20(token).balanceOf(account) returns (uint256 balance) {
            return balance;
        } catch {
            return 0;
        }
    }
}
