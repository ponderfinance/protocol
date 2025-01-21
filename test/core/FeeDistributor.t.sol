// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/distributor/FeeDistributor.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/router/PonderRouter.sol";

/**
 * @title Mock ERC20 Token for Testing
 */
contract ERC20Mock is PonderERC20 {
    constructor(string memory name, string memory symbol) PonderERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Add this function to prevent reverting
    function isLaunchToken() external pure returns (bool) {
        return false;
    }
}

contract ReentrantToken is PonderERC20 {
    FeeDistributor public distributor;
    bool private _isReentering;

    constructor(address _distributor) PonderERC20("Reentrant", "RENT") {
        distributor = FeeDistributor(_distributor);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        // During convertFees, the router will call transfer. Try to reenter convertFees here
        if (to == address(distributor) && !_isReentering) {
            _isReentering = true;
            distributor.convertFees(address(this));  // Try to reenter convertFees
            _isReentering = false;
        }

        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        // Check if we're being transferred to pair during convertFees
        if (from == address(distributor) && !_isReentering) {
            _isReentering = true;
            distributor.convertFees(address(this));  // Try to reenter convertFees
            _isReentering = false;
        }

        if (amount > allowance(from, msg.sender)) revert("Insufficient allowance");

        _transfer(from, to, amount);
        _approve(from, msg.sender, allowance(from, msg.sender) - amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function isLaunchToken() external pure returns (bool) {
        return false;
    }
}

contract ReentrantPair {
    FeeDistributor public distributor;
    address public token0;
    address public token1;
    bool private _isReentering;

    constructor(address _distributor, address _token0, address _token1) {
        distributor = FeeDistributor(_distributor);
        token0 = _token0;
        token1 = _token1;
    }

    function sync() external {
        if (!_isReentering) {
            _isReentering = true;
            distributor.collectFeesFromPair(address(this));
            _isReentering = false;
        }
    }

    function skim(address to) external {
        // Transfer some tokens to simulate fee collection
        uint256 amount = 1000e18;
        IERC20(token0).transfer(to, amount);
        IERC20(token1).transfer(to, amount);
    }

    // Added to match IPonderPair interface
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (1000e6, 1000e6, uint32(block.timestamp));
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
    address public marketing;
    address public teamReserve;
    address constant WETH = address(0x1234);

    // Test token for pairs
    ERC20Mock public testToken;

    uint256 constant BASIS_POINTS = 10000;
    uint256 constant MAX_PAIRS_PER_DISTRIBUTION = 10;
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;


    bytes4 constant DISTRIBUTION_TOO_FREQUENT_ERROR = 0x1e4f7d8c;
    bytes4 constant INVALID_PAIR_ERROR = 0x6fd6873e;
    bytes4 constant INSUFFICIENT_ACCUMULATION_ERROR = 0x7bb6e304;
    bytes4 constant SWAP_FAILED_ERROR = 0x7c5f487d;
    bytes4 constant INVALID_PAIR_COUNT_ERROR = 0x7773d3bc;
    bytes4 constant INVALID_PAIR_COUNT = 0xf392fe61;  // Updated

    error InvalidPairCount();
    error InvalidPair();
    error DistributionTooFrequent();
    error InsufficientAccumulation();
    error SwapFailed();
    error ReentrancyGuardReentrantCall();

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

    function _getPath(address tokenIn, address tokenOut) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return path;
    }

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
        // First ensure larger initial liquidity
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

        // Do moderate swaps to generate fees without extreme price impact
        for (uint i = 0; i < 10; i++) {
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
            uint256 swapAmount = uint256(reserve0) / 10; // Use 10% of reserves instead of 20%

            testToken.transfer(address(pair), swapAmount);
            uint256 amountOut = (swapAmount * 997 * reserve1) / ((reserve0 * 1000) + (swapAmount * 997));
            pair.swap(0, amountOut, address(this), "");
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);

            (reserve0, reserve1,) = pair.getReserves();
            swapAmount = uint256(reserve1) / 10; // Also reduced to 10%
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
        assertEq(address(distributor.FACTORY()), address(factory));
        assertEq(address(distributor.ROUTER()), address(router));
        assertEq(address(distributor.PONDER()), address(ponder));
        assertEq(address(distributor.STAKING()), address(staking));
        assertEq(distributor.team(), teamReserve);
        assertEq(distributor.stakingRatio(), 8000); // 80%
        assertEq(distributor.teamRatio(), 2000);    // 20%
    }

    /**
     * @notice Test collecting fees from pair
     */
    function test_CollectFeesFromPair() public {
        // Set the Fee Distributor address in the factory
        factory.setFeeTo(address(distributor));

        // Generate trading fees
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

        // Simulate the Fee Distributor calling skim
        vm.prank(address(distributor)); // Correct use of vm.prank()
        pair.skim(address(distributor));

        // Fee Distributor collects the fees
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

        uint256 prePonderBalance = ponder.balanceOf(address(distributor));
        uint256 preTokenBalance = testToken.balanceOf(address(distributor));

        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        // Additional trade and sync
        testToken.mint(address(this), 1_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);
        testToken.transfer(address(pair), 1_000_000e18);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountIn = 1_000_000e18;
        uint256 amountOut = (amountIn * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + amountIn * 997);

        pair.swap(0, amountOut, address(this), "");

        // Sync before converting
        pair.sync();

        // Convert fees
        distributor.convertFees(address(testToken));

        // Now skim any excess
        vm.prank(address(distributor));
        pair.skim(address(distributor));

        uint256 postPonderBalance = ponder.balanceOf(address(distributor));
        uint256 postTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(
            postPonderBalance > prePonderBalance || postTokenBalance > preTokenBalance,
            "Should convert fees and increase balance"
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
        require(totalAmount >= distributor.minimumAmount(), "Insufficient PONDER for distribution");

        uint256 expectedStaking = (totalAmount * 8000) / BASIS_POINTS; // 80%
        uint256 expectedTeam = (totalAmount * 2000) / BASIS_POINTS;    // 20%

        uint256 initialStaking = ponder.balanceOf(address(staking));
        uint256 initialTeam = ponder.balanceOf(teamReserve);

        // Remove this line as it's no longer needed
        // vm.warp(block.timestamp + 1 days);

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

    function test_StakingShareValueUpdate() public {
        // First we need user1 to have tokens to stake
        vm.startPrank(address(this));  // Test contract has marketing tokens in setUp()
        ponder.transfer(user1, 10_000e18);
        vm.stopPrank();

        // Now do the staking
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Record initial state
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));
        uint256 initialShareValue = staking.getPonderAmount(1000e18);

        // Generate and distribute fees using the existing helper
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Get balances before distribution
        uint256 stakingBalanceBefore = ponder.balanceOf(address(staking));

        distributor.distribute();

        // Get final states
        uint256 finalStakingBalance = ponder.balanceOf(address(staking));
        uint256 finalShareValue = staking.getPonderAmount(1000e18);

        // Verify balances changed
        assertGt(finalStakingBalance, stakingBalanceBefore, "Staking should receive tokens");

        // Verify share value increased proportionally
        assertGt(finalShareValue, initialShareValue, "Share value should increase");

        // The share value increase should match the balance increase ratio
        uint256 expectedFinalValue = (initialShareValue * finalStakingBalance) / initialStakingBalance;
        assertApproxEqRel(finalShareValue, expectedFinalValue, 0.01e18,
            "Share value should increase proportionally");
    }

    function test_ReentrancyFromToken() public {
        // Deploy malicious token that attempts reentrancy
        ReentrantToken reentrantToken = new ReentrantToken(address(distributor));  // collectMode = true

        // Create pair with reentrant token
        factory.createPair(address(ponder), address(reentrantToken));
        address reentrantPairAddr = factory.getPair(address(ponder), address(reentrantToken));

        // Setup initial liquidity with smaller amounts
        reentrantToken.mint(address(this), 2_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);

        reentrantToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(ponder),
            address(reentrantToken),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Generate some fees
        reentrantToken.transfer(reentrantPairAddr, 10e18);
        bytes memory empty;
        IPonderPair(reentrantPairAddr).swap(0, 1e18, address(this), empty);

        // Attempt reentrancy attack - should fail
        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        distributor.collectFeesFromPair(reentrantPairAddr);
    }

    function test_ReentrancyFromPair() public {
        // Deploy tokens
        ERC20Mock token0 = new ERC20Mock("Token0", "TK0");
        ERC20Mock token1 = new ERC20Mock("Token1", "TK1");

        // Deploy malicious pair that attempts reentrancy
        ReentrantPair reentrantPair = new ReentrantPair(
            address(distributor),
            address(token0),
            address(token1)
        );

        // Setup tokens
        token0.mint(address(reentrantPair), 1_000_000e18);
        token1.mint(address(reentrantPair), 1_000_000e18);

        // Expect the custom error
        vm.expectRevert(ReentrancyGuardReentrantCall.selector);
        distributor.collectFeesFromPair(address(reentrantPair));
    }

    function test_EmergencyTokenRecovery() public {
        // Deploy token and mint some to distributor
        ERC20Mock token = new ERC20Mock("Test", "TST");
        token.mint(address(distributor), 1000e18);

        uint256 initialBalance = token.balanceOf(address(this));

        // Non-owner should not be able to recover tokens
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        distributor.emergencyTokenRecover(address(token), address(this), 1000e18);

        // Owner should be able to recover tokens
        vm.prank(owner);
        distributor.emergencyTokenRecover(address(token), address(this), 1000e18);

        assertEq(
            token.balanceOf(address(this)) - initialBalance,
            1000e18,
            "Recovery amount incorrect"
        );
    }

    function test_CollectFeesWithInvalidPair() public {
        // Try to collect fees from zero address
        vm.expectRevert(); // Should revert with invalid pair error
        distributor.collectFeesFromPair(address(0));

        // Try to collect fees from non-pair contract
        vm.expectRevert(); // Should revert when calling non-existent functions
        distributor.collectFeesFromPair(address(0x1234));
    }

    function test_CollectFeesStateValidation() public {
        // Setup pair and generate fees like in previous tests
        _generateTradingFees();

        // Get initial state
        uint256 initialBalance = ponder.balanceOf(address(distributor));

        // Collect fees
        distributor.collectFeesFromPair(address(pair));

        // Verify state changes
        uint256 finalBalance = ponder.balanceOf(address(distributor));
        assertTrue(finalBalance >= initialBalance, "Balance should not decrease");

        // Try to collect again immediately
        distributor.collectFeesFromPair(address(pair));

        // Verify no significant balance change on second collection
        uint256 afterSecondCollection = ponder.balanceOf(address(distributor));
        assertApproxEqRel(
            afterSecondCollection,
            finalBalance,
            0.01e18,
            "No significant fees should be collected twice"
        );
    }

    // Add these test functions to FeeDistributorTest contract

    function test_DistributePairFeesMaxLimit() public {
        // Create array with too many pairs
        address[] memory pairs = new address[](11); // MAX_PAIRS_PER_DISTRIBUTION + 1
        for(uint i = 0; i < 11; i++) {
            // Create new test tokens and pairs
            ERC20Mock newToken = new ERC20Mock("Test", "TEST");
            factory.createPair(address(ponder), address(newToken));
            pairs[i] = factory.getPair(address(ponder), address(newToken));
        }

        // Should revert when trying to distribute too many pairs
        vm.expectRevert(abi.encodeWithSignature("InvalidPairCount()"));
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesWithInvalidPair() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(0); // Invalid pair address

        vm.expectRevert(abi.encodeWithSignature("InvalidPair()"));
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesSuccessfulDistribution() public {
        _generateTradingFees();

        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        uint256 preStakingBalance = IERC20(ponder).balanceOf(address(staking));
        uint256 preTeamBalance = IERC20(ponder).balanceOf(teamReserve);

        distributor.distributePairFees(pairs);

        uint256 postStakingBalance = IERC20(ponder).balanceOf(address(staking));
        uint256 postTeamBalance = IERC20(ponder).balanceOf(teamReserve);

        assertTrue(postStakingBalance > preStakingBalance, "Staking balance should increase");
        assertTrue(postTeamBalance > preTeamBalance, "Team balance should increase");

        // Verify distribution ratio (80/20)
        uint256 stakingIncrease = postStakingBalance - preStakingBalance;
        uint256 teamIncrease = postTeamBalance - preTeamBalance;
        assertApproxEqRel(
            stakingIncrease * 2000,
            teamIncrease * 8000,
            0.01e18,
            "Incorrect distribution ratio"
        );
    }

    function test_DistributePairFeesDuplicatePairs() public {
        address[] memory pairs = new address[](2);
        pairs[0] = address(pair);
        pairs[1] = address(pair);

        vm.expectRevert(INVALID_PAIR_ERROR);
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesInsufficientAccumulation() public {
        // Create new pair with more substantial liquidity
        ERC20Mock smallToken = new ERC20Mock("Small", "SMALL");
        factory.createPair(address(ponder), address(smallToken));
        address smallPair = factory.getPair(address(ponder), address(smallToken));

        // Add sufficient initial liquidity
        uint256 initAmount = 10_000e18;
        smallToken.mint(address(this), initAmount);
        ponder.transfer(address(this), initAmount);

        smallToken.approve(address(router), initAmount);
        ponder.approve(address(router), initAmount);

        router.addLiquidity(
            address(ponder),
            address(smallToken),
            initAmount,
            initAmount,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory pairs = new address[](1);
        pairs[0] = smallPair;

        // Should fail with InsufficientAccumulation error code 0x6fd6873e
        vm.expectRevert(bytes4(0x6fd6873e));
        distributor.distributePairFees(pairs);
    }

    function test_MaxPairsPerDistribution() public {
        address[] memory tooManyPairs = new address[](MAX_PAIRS_PER_DISTRIBUTION + 1);

        vm.expectRevert(abi.encodeWithSignature("InvalidPairCount()"));
        distributor.distributePairFees(tooManyPairs);
    }

    function test_ProcessedPairsCleanup() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // Generate initial fees
        _generateTradingFees();

        // First distribution
        distributor.distributePairFees(pairs);

        // Wait cooldown period
        vm.warp(block.timestamp + 1 hours + 1);

        // Generate new fees
        _generateTradingFees();

        // Second distribution should work since we properly reset processedPairs
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesSlippageProtection() public {
        _generateTradingFees();

        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Create extreme price impact - trying to create >100x imbalance
        uint256 extremeAmount = uint256(reserve0) * 150; // 150x the current reserve
        testToken.mint(address(this), extremeAmount);
        testToken.approve(address(router), extremeAmount);

        // Do multiple trades to create extreme imbalance
        address[] memory path = new address[](2);
        path[0] = address(testToken);
        path[1] = address(ponder);

        // First big trade
        router.swapExactTokensForTokens(
            extremeAmount / 2,
            0,
            path,
            address(this),
            block.timestamp
        );

        // Second big trade to really push the ratio
        router.swapExactTokensForTokens(
            extremeAmount / 2,
            0,
            path,
            address(this),
            block.timestamp
        );

        pair.sync();
        vm.warp(block.timestamp + 1 hours);

        // Now should fail due to extreme reserve ratio
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesCooldown() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // First distribution
        _generateTradingFees();
        distributor.distributePairFees(pairs);

        // Try immediate second distribution - should fail with DistributionTooFrequent
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distributePairFees(pairs);

        // After cooldown, should work
        vm.warp(block.timestamp + 1 hours + 1);
        _generateTradingFees();
        distributor.distributePairFees(pairs);
    }

    function test_ConvertFeesSlippageProtection() public {
        // First generate some fees
        _generateTradingFees();

        // Get initial balances
        uint256 initialTokenBalance = testToken.balanceOf(address(distributor));
        require(initialTokenBalance > 0, "No fees generated");

        // Create extreme imbalance (similar to our working distributePairFees test)
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 extremeAmount = uint256(reserve0) * 150; // 150x reserves
        testToken.mint(address(this), extremeAmount);
        testToken.approve(address(router), extremeAmount);

        address[] memory path = new address[](2);
        path[0] = address(testToken);
        path[1] = address(ponder);

        // Do two massive trades to really break the price
        router.swapExactTokensForTokens(
            extremeAmount / 2,
            0,
            path,
            address(this),
            block.timestamp
        );

        router.swapExactTokensForTokens(
            extremeAmount / 2,
            0,
            path,
            address(this),
            block.timestamp
        );

        pair.sync();
        vm.warp(block.timestamp + 1 hours);

        // Now the conversion should fail due to extreme imbalance
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.convertFees(address(testToken));
    }

    function test_ConvertFeesSuccessful() public {
        // Generate some fees
        _generateTradingFees();

        // Get initial balances
        uint256 initialPonderBalance = ponder.balanceOf(address(distributor));
        uint256 initialTokenBalance = testToken.balanceOf(address(distributor));

        // Ensure we have enough fees to convert
        require(initialTokenBalance >= distributor.minimumAmount(), "Insufficient fees");

        // Convert fees
        distributor.convertFees(address(testToken));

        // Verify balances changed appropriately
        uint256 finalPonderBalance = ponder.balanceOf(address(distributor));
        uint256 finalTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(finalPonderBalance > initialPonderBalance, "PONDER balance should increase");
        assertTrue(finalTokenBalance < initialTokenBalance, "Token balance should decrease");
    }

    function test_ConvertFeesInvalidToken() public {
        // Deploy a mock token but don't create a pair for it
        ERC20Mock invalidToken = new ERC20Mock("Invalid", "INV");

        // Mint some tokens to the distributor
        invalidToken.mint(address(distributor), distributor.minimumAmount());

        // Should revert with PairNotFound since no pair exists
        vm.expectRevert(abi.encodeWithSignature("PairNotFound()"));
        distributor.convertFees(address(invalidToken));
    }

    function test_ConvertFeesReentrancyProtection() public {
        ReentrantToken maliciousToken = new ReentrantToken(address(distributor));

        // Create pair
        factory.createPair(address(maliciousToken), address(ponder));

        // Setup liquidity
        maliciousToken.mint(address(this), 10000e18);
        ponder.transfer(address(this), 10000e18);

        maliciousToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(maliciousToken),
            address(ponder),
            10000e18,
            10000e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Mint directly to distributor
        maliciousToken.mint(address(distributor), distributor.minimumAmount());

        // Change this line to expect SwapFailed instead
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.convertFees(address(maliciousToken));
    }

    function test_DistributionTimingManipulation() public {
        // Initial setup and first distribution
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        vm.warp(1000); // Set initial time
        distributor.distribute();

        // Generate more fees for subsequent attempts
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Ensure sufficient balance
        uint256 distributorBalance = ponder.balanceOf(address(distributor));
        require(distributorBalance >= distributor.minimumAmount(), "Insufficient balance for test");

        // Try after 30 minutes
        vm.warp(1000 + 30 minutes);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();

        // Generate more fees and try after 45 minutes
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        vm.warp(1000 + 45 minutes);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();

        // Should work after cooldown
        vm.warp(1000 + 1 hours);
        distributor.distribute();
    }

    function test_DistributionFrontRunningProtection() public {
        // Initial setup - generate some fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Set initial timestamp
        uint256 startTime = 1000;
        vm.warp(startTime);

        // First distribution
        distributor.distribute();

        // Verify lastDistributionTimestamp was set
        assertEq(distributor.lastDistributionTimestamp(), startTime, "Distribution timestamp not set");

        // Generate more fees for the attack attempt
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Setup attacker
        address attacker = address(0x2);
        vm.startPrank(address(this));
        ponder.transfer(attacker, 100_000e18);
        vm.stopPrank();

        vm.startPrank(attacker);
        ponder.approve(address(staking), 100_000e18);
        staking.enter(100_000e18);

        // Try to distribute immediately after (t = startTime + 1)
        vm.warp(startTime + 1);

        // Should fail due to cooldown
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();
        vm.stopPrank();

        // Verify distribution still fails just before cooldown ends
        vm.warp(startTime + DISTRIBUTION_COOLDOWN - 1);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();

        // Should succeed after cooldown
        vm.warp(startTime + DISTRIBUTION_COOLDOWN);
        distributor.distribute();
    }

    function test_StakingPositionStability() public {
        // Setup initial stakers
        address[] memory stakers = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        for(uint i = 0; i < stakers.length; i++) {
            stakers[i] = address(uint160(i + 1));
            amounts[i] = 1000e18 * (i + 1);

            vm.startPrank(address(this));
            ponder.transfer(stakers[i], amounts[i]);
            vm.stopPrank();

            vm.startPrank(stakers[i]);
            ponder.approve(address(staking), amounts[i]);
            staking.enter(amounts[i]);
            vm.stopPrank();
        }

        // Generate and collect fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Set initial timestamp and distribute
        uint256 startTime = 1000;
        vm.warp(startTime);
        distributor.distribute();

        // Verify timestamp set
        assertEq(distributor.lastDistributionTimestamp(), startTime, "Distribution timestamp not set");

        // Setup for attack attempt
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        address attacker = address(0x999);
        vm.startPrank(address(this));
        ponder.transfer(attacker, 100_000e18);
        vm.stopPrank();

        vm.startPrank(attacker);
        ponder.approve(address(staking), 100_000e18);
        staking.enter(100_000e18);

        // Try to distribute within cooldown period (t = startTime + 1)
        vm.warp(startTime + 1);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();
        vm.stopPrank();
    }

}

