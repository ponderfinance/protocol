// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/masterchef/PonderMasterChef.sol";
import "../../src/core/oracle/PonderPriceOracle.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../../src/core/distributor/FeeDistributor.sol";
import "../../src/launch/FiveFiveFiveLauncher.sol";
import "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "forge-std/Script.sol";
import "./IDeployBitkub.sol";

contract DeployBitkubScript is Script, IDeployBitkubScript {
    // Immutable addresses
    address constant USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
    address constant KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;

    // Custom errors
    error InvalidAddress();
    error PairCreationFailed();
    error DeploymentFailed(string name);
    error LiquidityAddFailed();
    error DeploymentDeadlineExceeded();
    error UnauthorizedDeployer();
    error ConfigurationFailed(string name);
    error FeePolicyConfigFailed();

    // Events
    event DeploymentStarted(address indexed deployer, uint256 deadline);
    event ContractDeployed(string indexed name, address indexed addr);
    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
    event ConfigurationFinalized(
        address indexed ponder,
        address indexed masterChef,
        address indexed feeDistributor
    );

    modifier onlyDeployer(address _deployer) {
        if (msg.sender != _deployer) revert UnauthorizedDeployer();
        _;
    }

    modifier withinDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeploymentDeadlineExceeded();
        _;
    }

    function validateAddresses(
        address teamReserve,
        address marketing,
        address deployer
    ) public pure override {
        if (teamReserve == address(0) ||
        marketing == address(0) ||
            deployer == address(0)
        ) {
            revert InvalidAddress();
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");
        address marketing = vm.envAddress("MARKETING_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        validateAddresses(teamReserve, marketing, deployer);

        DeployConfig memory config = DeployConfig({
            ponderPerSecond: vm.envOr("PONDER_PER_SECOND", uint256(3168000000000000000)),
            initialKubAmount: vm.envOr("INITIAL_KUB_AMOUNT", uint256(1000 ether)),
            liquidityAllocation: vm.envOr("LIQUIDITY_ALLOCATION", uint256(200_000_000 ether)),
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        vm.startBroadcast(deployerPrivateKey);

        emit DeploymentStarted(deployer, config.deploymentDeadline);

        DeploymentState memory state = deployCore(
            deployer,
            teamReserve,
            marketing,
            config
        );

        setupInitialPrices(state, config);
        finalizeConfiguration(state, deployer, config);

        vm.stopBroadcast();

        logDeployment(state);
    }

    function deployCore(
        address deployer,
        address teamReserve,
        address marketing,
        DeployConfig memory config
    ) public
    override
    withinDeadline(config.deploymentDeadline)
    returns (DeploymentState memory state)
    {
        state.deployer = deployer;
        state.teamReserve = teamReserve;
        state.marketing = marketing;

        // Deploy factory first
        state.factory = new PonderFactory(deployer, address(0), address(0));
        verifyContract("PonderFactory", address(state.factory));
        emit ContractDeployed("PonderFactory", address(state.factory));

        // Deploy KKUBUnwrapper
        state.kkubUnwrapper = new KKUBUnwrapper(KKUB);
        verifyContract("KKUBUnwrapper", address(state.kkubUnwrapper));
        emit ContractDeployed("KKUBUnwrapper", address(state.kkubUnwrapper));

        // Deploy router
        state.router = new PonderRouter(
            address(state.factory),
            KKUB,
            address(state.kkubUnwrapper)
        );
        verifyContract("PonderRouter", address(state.router));
        emit ContractDeployed("PonderRouter", address(state.router));

        // Deploy PONDER token with updated constructor params
        state.ponder = new PonderToken(
            teamReserve,
            marketing,
            address(0) // Initial launcher set later
        );
        verifyContract("PonderToken", address(state.ponder));
        emit ContractDeployed("PonderToken", address(state.ponder));

        // Create PONDER-KUB pair
        state.factory.createPair(address(state.ponder), KKUB);
        state.ponderKubPair = state.factory.getPair(address(state.ponder), KKUB);
        if (state.ponderKubPair == address(0)) revert PairCreationFailed();
        emit ContractDeployed("PONDER-KUB Pair", state.ponderKubPair);

        // Deploy oracle with updated base token support
        state.oracle = new PonderPriceOracle(
            address(state.factory),
            KKUB,
            USDT
        );
        verifyContract("PonderPriceOracle", address(state.oracle));
        emit ContractDeployed("PriceOracle", address(state.oracle));

        // Deploy staking with factory reference
        state.staking = new PonderStaking(
            address(state.ponder),
            address(state.router),
            address(state.factory)
        );
        verifyContract("PonderStaking", address(state.staking));
        emit ContractDeployed("Staking", address(state.staking));

        // Deploy fee distributor with updated constructor
        state.feeDistributor = new FeeDistributor(
            address(state.factory),
            address(state.router),
            address(state.ponder),
            address(state.staking),
            teamReserve
        );
        verifyContract("FeeDistributor", address(state.feeDistributor));
        emit ContractDeployed("FeeDistributor", address(state.feeDistributor));

        // Deploy launcher with price oracle
        state.launcher = new FiveFiveFiveLauncher(
            address(state.factory),
            payable(address(state.router)),
            teamReserve,
            address(state.ponder),
            address(state.oracle)
        );
        verifyContract("Launcher", address(state.launcher));
        emit ContractDeployed("Launcher", address(state.launcher));

        // Deploy MasterChef with updated constructor
        state.masterChef = new PonderMasterChef(
            state.ponder,
            state.factory,
            teamReserve,
            config.ponderPerSecond
        );
        verifyContract("MasterChef", address(state.masterChef));
        emit ContractDeployed("MasterChef", address(state.masterChef));

        return state;
    }

    function setupInitialPrices(
        DeploymentState memory state,
        DeployConfig memory config
    ) public override withinDeadline(config.deploymentDeadline) {
        // Verify deployer balance
        uint256 deployerBalance = state.ponder.balanceOf(state.deployer);
        if (deployerBalance < config.liquidityAllocation) {
            revert LiquidityAddFailed();
        }

        // Approve router for liquidity
        bool approveSuccess = state.ponder.approve(
            address(state.router),
            config.liquidityAllocation
        );
        if (!approveSuccess) revert LiquidityAddFailed();

        // Add initial liquidity with ETH
        (bool success,) = address(state.router).call{value: config.initialKubAmount}(
            abi.encodeWithSelector(
                state.router.addLiquidityETH.selector,
                address(state.ponder),
                config.liquidityAllocation,
                config.liquidityAllocation,
                config.initialKubAmount,
                state.deployer,
                config.liquidityDeadline
            )
        );

        if (!success) revert LiquidityAddFailed();

        emit LiquidityAdded(config.initialKubAmount, config.liquidityAllocation);
    }

    function finalizeConfiguration(
        DeploymentState memory state,
        address deployer,
        DeployConfig memory config
    ) public override onlyDeployer(deployer) withinDeadline(config.deploymentDeadline) {
        // Verify deployer permissions
        if (state.factory.feeToSetter() != deployer) revert UnauthorizedDeployer();

        // Configure PONDER token roles
        state.ponder.setMinter(address(state.masterChef));
        state.ponder.setLauncher(address(state.launcher));

        // Configure factory settings
        state.factory.setLauncher(address(state.launcher));
        state.factory.setPonder(address(state.ponder));
        state.factory.setFeeTo(address(state.feeDistributor));

        // Apply launcher changes after timelock if needed
        if (state.factory.pendingLauncher() != address(0)) {
            state.factory.applyLauncher();
        }

        emit ConfigurationFinalized(
            address(state.ponder),
            address(state.masterChef),
            address(state.feeDistributor)
        );
    }

    function verifyContract(string memory name, address contractAddress) public view override {
        uint256 size;
        assembly {
            size := extcodesize(contractAddress)
        }
        if (size == 0) revert DeploymentFailed(name);
    }

    function logDeployment(DeploymentState memory state) internal view {
        console.log("\nDeployment Summary on Bitkub Chain:");
        console.log("--------------------------------");
        console.log("KKUB Address:", KKUB);
        console.log("PonderToken:", address(state.ponder));
        console.log("Factory:", address(state.factory));
        console.log("KKUBUnwrapper:", address(state.kkubUnwrapper));
        console.log("Router:", address(state.router));
        console.log("PriceOracle:", address(state.oracle));
        console.log("PONDER/KKUB Pair:", state.ponderKubPair);
        console.log("MasterChef:", address(state.masterChef));
        console.log("FiveFiveFiveLauncher:", address(state.launcher));
        console.log("PonderStaking (xPONDER):", address(state.staking));
        console.log("FeeDistributor:", address(state.feeDistributor));

        // Get pair reserves for rate calculation
        (uint112 ponderReserve, uint112 kubReserve,) = IPonderPair(state.ponderKubPair).getReserves();

        console.log("\nLiquidity Details:");
        console.log("--------------------------------");
        console.log("Initial KUB:", uint256(kubReserve) / 1e18);
        console.log("Initial PONDER:", uint256(ponderReserve) / 1e18);
        console.log("Initial PONDER/KUB Rate:", uint256(ponderReserve) / uint256(kubReserve));

        console.log("\nToken Allocation Summary:");
        console.log("--------------------------------");
        console.log("Liquidity Mining (40%):", uint256(400_000_000 * 1e18));
        console.log("Team/Reserve (25%):", uint256(250_000_000 * 1e18));
        console.log("Marketing/Community (15%):", uint256(150_000_000 * 1e18));
    }

    receive() external payable {}
}
