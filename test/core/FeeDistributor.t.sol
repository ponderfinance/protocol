// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/core/FeeDistributor.sol";
import "../../src/core/PonderStaking.sol";
import "../../src/core/PonderToken.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";

/**
 * @title Mock ERC20 Token for Testing
 */
contract ERC20Mock is PonderERC20 {
    constructor(string memory name, string memory symbol) PonderERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title Mock Token that fails transfers
 * @dev Used to test error handling
 */
contract MockFailingToken is PonderERC20 {
    constructor() PonderERC20("Failing", "FAIL") {}

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title FeeDistributor Test Contract
 * @notice Tests the FeeDistributor contract's functionality
 * @dev Tests core fee collection, conversion, and distribution logic
 */
contract FeeDistributorTest is Test {
    FeeDistributor public distributor;
    PonderStaking public staking;
    PonderToken public ponder;
    PonderFactory public factory;
    PonderRouter public router;
    PonderPair public pair;

    address public owner;
    address public user1;
    address public teamReserve;
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
        teamReserve = address(0x3);

        // Deploy core contracts
        factory = new PonderFactory(owner, address(0), address(0));

        router = new PonderRouter(
            address(factory),
            WETH,
            address(0) // No unwrapper needed for tests
        );

        ponder = new PonderToken(
            teamReserve,
            address(this), // marketing
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

    /**
     * @notice Helper to setup initial liquidity in test pair
     */
    function _setupInitialLiquidity() internal {
        uint256 ponderAmount = 1_000_000e18;
        uint256 tokenAmount = 1_000_000e18;

        // Transfer PONDER from treasury
        ponder.transfer(address(this), ponderAmount * 2);

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

    /**
     * @notice Helper to generate trading fees through swaps
     */
    function _generateTradingFees() internal {
        // First ensure much larger initial liquidity
        testToken.mint(address(this), 100_000_000e18);
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
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);

            (reserve0, reserve1,) = pair.getReserves();
            swapAmount = uint256(reserve1) / 5;
            ponder.transfer(address(pair), swapAmount);

            pair.swap(amountOut, 0, address(this), "");
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);
            pair.sync();
        }
    }
    /**
     * @notice Test initial contract state
     */
    function test_InitialState() public {
        assertEq(address(distributor.factory()), address(factory));
        assertEq(address(distributor.router()), address(router));
        assertEq(address(distributor.ponder()), address(ponder));
        assertEq(address(distributor.staking()), address(staking));
        assertEq(distributor.team(), teamReserve);
        assertEq(distributor.stakingRatio(), 8000); // 80%
        assertEq(distributor.teamRatio(), 2000);    // 20%
    }

    /**
     * @notice Test collecting fees from pair
     */
    function test_CollectFeesFromPair() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        uint256 prePonderBalance = ponder.balanceOf(address(distributor));
        uint256 preTokenBalance = testToken.balanceOf(address(distributor));

        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        // Additional trade and skim
        testToken.mint(address(this), 1_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);
        testToken.transfer(address(pair), 1_000_000e18);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountIn = 1_000_000e18;
        uint256 amountOut = (amountIn * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + amountIn * 997);

        pair.swap(0, amountOut, address(this), "");
        pair.skim(address(distributor));

        distributor.collectFeesFromPair(address(pair));

        uint256 postPonderBalance = ponder.balanceOf(address(distributor));
        uint256 postTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(
            postPonderBalance > prePonderBalance || postTokenBalance > preTokenBalance,
            "Should collect fees"
        );
    }

    /**
     * @notice Test fee conversion to PONDER
     */
    function test_ConvertFees() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        vm.warp(block.timestamp + 1 hours);
        pair.sync();
        pair.skim(address(distributor));

        uint256 initialTestBalance = testToken.balanceOf(address(distributor));
        require(initialTestBalance > 0, "No test tokens to convert");

        uint256 initialPonderBalance = ponder.balanceOf(address(distributor));

        vm.startPrank(address(distributor));
        testToken.approve(address(router), type(uint256).max);
        vm.stopPrank();

        distributor.convertFees(address(testToken));

        uint256 finalTestBalance = testToken.balanceOf(address(distributor));
        uint256 finalPonderBalance = ponder.balanceOf(address(distributor));

        assertTrue(
            finalTestBalance <= initialTestBalance / 100,
            "Should convert most test tokens"
        );
        assertTrue(
            finalPonderBalance > initialPonderBalance,
            "Should receive PONDER from conversion"
        );
    }

    /**
     * @notice Test distribution ratio updates
     */
    function test_UpdateDistributionRatios() public {
        uint256 newStakingRatio = 7000; // 70%
        uint256 newTeamRatio = 3000;    // 30%

        distributor.updateDistributionRatios(
            newStakingRatio,
            newTeamRatio
        );

        assertEq(distributor.stakingRatio(), newStakingRatio);
        assertEq(distributor.teamRatio(), newTeamRatio);
    }

    /**
     * @notice Test invalid ratio combinations revert
     */
    function test_RevertInvalidRatios() public {
        // Total > 100%
        vm.expectRevert(abi.encodeWithSignature("RatioSumIncorrect()"));
        distributor.updateDistributionRatios(8000, 3000);

        // Total < 100%
        vm.expectRevert(abi.encodeWithSignature("RatioSumIncorrect()"));
        distributor.updateDistributionRatios(7000, 2000);
    }

    /**
     * @notice Test authorization controls
     */
    function test_RevertUnauthorizedDistributionChange() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        distributor.updateDistributionRatios(7000, 3000);
    }

    /**
     * @notice Test zero address validations
     */
    function test_RevertZeroAddresses() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        distributor.setTeam(address(0));
    }

/**
     * @notice Test fee distribution to stakers and team
     */
    function test_Distribution() public {
        _generateTradingFees();
        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        uint256 totalAmount = ponder.balanceOf(address(distributor));
        require(totalAmount >= distributor.MINIMUM_AMOUNT(), "Insufficient PONDER for distribution");

        uint256 expectedStaking = (totalAmount * 8000) / BASIS_POINTS; // 80%
        uint256 expectedTeam = (totalAmount * 2000) / BASIS_POINTS;    // 20%

        uint256 initialStaking = ponder.balanceOf(address(staking));
        uint256 initialTeam = ponder.balanceOf(teamReserve);

        // Advance time to allow rebase
        vm.warp(block.timestamp + 1 days);

        distributor.distribute();

        assertApproxEqRel(
            ponder.balanceOf(address(staking)) - initialStaking,
            expectedStaking,
            0.01e18,
            "Wrong staking distribution"
        );

        assertApproxEqRel(
            ponder.balanceOf(teamReserve) - initialTeam,
            expectedTeam,
            0.01e18,
            "Wrong team distribution"
        );
    }

    /**
     * @notice Test the complete fee lifecycle with multiple distributions
     */
    function test_CompleteFeeLifecycle() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        uint256 initialStakingBalance = ponder.balanceOf(address(staking));
        uint256 initialTeamBalance = ponder.balanceOf(teamReserve);

        // Collect and convert fees
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Advance time to allow rebase
        vm.warp(block.timestamp + 1 days);

        // Distribute
        distributor.distribute();

        // Verify distribution
        assertTrue(
            ponder.balanceOf(address(staking)) > initialStakingBalance,
            "Staking balance should increase"
        );
        assertTrue(
            ponder.balanceOf(teamReserve) > initialTeamBalance,
            "Team balance should increase"
        );

        // Verify ratio
        uint256 stakingIncrease = ponder.balanceOf(address(staking)) - initialStakingBalance;
        uint256 teamIncrease = ponder.balanceOf(teamReserve) - initialTeamBalance;

        assertApproxEqRel(
            stakingIncrease * 2000,
            teamIncrease * 8000,
            0.01e18,
            "Wrong distribution ratio"
        );
    }

    /**
     * @notice Test that K value is maintained throughout fee collection
     */
    function test_KValueMaintenance() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 initialK = uint256(reserve0) * uint256(reserve1);

        distributor.collectFeesFromPair(address(pair));

        (uint112 finalReserve0, uint112 finalReserve1,) = pair.getReserves();
        uint256 finalK = uint256(finalReserve0) * uint256(finalReserve1);

        assertGe(finalK, initialK, "K value should not decrease");
    }

    /**
     * @notice Helper function for calculating swap outputs
     */
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
}
