// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IDeployBitkub.sol";
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

contract DeployBitkubScript is Script, IDeployBitkub {
    // Constants
    address constant USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
    address constant KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
    uint256 constant DEPLOYMENT_TIMEOUT = 1 hours;

    // Events
    event DeploymentStarted(address indexed deployer, uint256 deadline);
    event ContractDeployed(string indexed name, address indexed addr);
    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
    event ConfigurationFinalized(
        address indexed ponder,
        address indexed masterChef,
        address indexed feeDistributor
    );

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");
        address marketing = vm.envAddress("MARKETING_ADDRESS");

        validateAddresses(teamReserve, marketing, deployer);

        IDeployBitkub.DeployConfig memory config = IDeployBitkub.DeployConfig({
            ponderPerSecond: 3168000000000000000,
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether,
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        emit DeploymentStarted(deployer, config.deploymentDeadline);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy core contracts
        DeploymentState memory state = _deployCore(
            deployer,
            teamReserve,
            marketing,
            config
        );

        // Setup initial prices if needed
        if (config.initialKubAmount > 0) {
            _setupInitialPrices(state, config);
        }

        // Finalize configuration
        _finalizeConfiguration(state, deployer, config);

        vm.stopBroadcast();

        _logDeployment(state);
    }

    // Internal implementation functions
    function _deployCore(
        address deployer,
        address teamReserve,
        address marketing,
        IDeployBitkub.DeployConfig memory config
    ) internal returns (DeploymentState memory state) {
        if (block.timestamp > config.deploymentDeadline)
            revert("DeploymentDeadlineExceeded()");

        // Initialize state
        state.deployer = deployer;
        state.teamReserve = teamReserve;
        state.marketing = marketing;
        state.deploymentStartTime = block.timestamp;

        // Deploy Factory
        PonderFactory factory = new PonderFactory(
            deployer,      // Set deployer as feeToSetter
            address(0),    // Launcher set later
            address(0)     // PONDER set later
        );
        state.factory = address(factory);
        emit ContractDeployed("Factory", address(factory));

        // Deploy PONDER
        PonderToken ponder = new PonderToken(
            teamReserve,
            marketing,
            address(0)     // Launcher set later
        );
        state.ponder = address(ponder);
        emit ContractDeployed("PONDER", address(ponder));

        // Deploy KKUBUnwrapper
        KKUBUnwrapper unwrapper = new KKUBUnwrapper(KKUB);
        state.kkubUnwrapper = address(unwrapper);
        emit ContractDeployed("KKUBUnwrapper", address(unwrapper));

        // Deploy Router
        PonderRouter router = new PonderRouter(
            address(factory),
            KKUB,
            address(unwrapper)
        );
        state.router = address(router);
        emit ContractDeployed("Router", address(router));

        // Create initial pair
        factory.createPair(address(ponder), KKUB);
        state.ponderKubPair = factory.getPair(address(ponder), KKUB);
        if (state.ponderKubPair == address(0)) revert("Pair creation failed");
        emit ContractDeployed("PONDER-KUB Pair", state.ponderKubPair);

        return state;
    }

    function _setupInitialPrices(
        DeploymentState memory state,
        IDeployBitkub.DeployConfig memory config
    ) internal {
        if (block.timestamp > config.liquidityDeadline)
            revert("LiquidityDeadlineExceeded()");

        // Approve router for PONDER
        PonderToken(state.ponder).approve(state.router, config.liquidityAllocation);

        // Add initial liquidity using router interface
        IPonderRouter(state.router).addLiquidityETH{value: config.initialKubAmount}(
            state.ponder,
            config.liquidityAllocation,
            config.liquidityAllocation,
            config.initialKubAmount,
            state.deployer,
            block.timestamp + 300
        );

        emit LiquidityAdded(config.initialKubAmount, config.liquidityAllocation);
    }

    function _finalizeConfiguration(
        DeploymentState memory state,
        address deployer,
        IDeployBitkub.DeployConfig memory config
    ) internal {
        if (msg.sender != deployer) revert("UnauthorizedDeployer()");
        if (block.timestamp > config.deploymentDeadline)
            revert("DeploymentDeadlineExceeded()");

        // Deploy remaining services
        PonderPriceOracle oracle = new PonderPriceOracle(state.factory, KKUB, USDT);
        state.oracle = address(oracle);

        PonderStaking staking = new PonderStaking(state.ponder, state.router, state.factory);
        state.staking = address(staking);

        FeeDistributor feeDistributor = new FeeDistributor(
            state.factory,
            state.router,
            state.ponder,
            address(staking),
            state.teamReserve
        );
        state.feeDistributor = address(feeDistributor);

        FiveFiveFiveLauncher launcher = new FiveFiveFiveLauncher(
            state.factory,
            payable(state.router),
            state.teamReserve,
            state.ponder,
            address(oracle)
        );
        state.launcher = address(launcher);

        PonderMasterChef masterChef = new PonderMasterChef(
            PonderToken(state.ponder),
            PonderFactory(state.factory),
            state.teamReserve,
            config.ponderPerSecond
        );
        state.masterChef = address(masterChef);

        // Configure permissions
        PonderToken(state.ponder).setMinter(address(masterChef));
        PonderToken(state.ponder).setLauncher(address(launcher));

        PonderFactory(state.factory).setLauncher(address(launcher));
        PonderFactory(state.factory).setPonder(state.ponder);
        PonderFactory(state.factory).setFeeTo(address(feeDistributor));

        state.initialized = true;

        emit ConfigurationFinalized(
            state.ponder,
            address(masterChef),
            address(feeDistributor)
        );
    }

    // Interface implementations
    function deployCore(
        address deployer,
        address teamReserve,
        address marketing,
        DeployConfig calldata config
    ) external override returns (DeploymentState memory) {
        return _deployCore(deployer, teamReserve, marketing, config);
    }

    function setupInitialPrices(
        DeploymentState memory state,
        DeployConfig calldata config
    ) external override {
        _setupInitialPrices(state, config);
    }

    function finalizeConfiguration(
        DeploymentState memory state,
        address deployer,
        DeployConfig calldata config
    ) external override {
        _finalizeConfiguration(state, deployer, config);
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
            revert("InvalidAddress()");
        }
    }

    function verifyContract(
        string memory name,
        address contractAddress
    ) public view override {
        uint256 size;
        assembly {
            size := extcodesize(contractAddress)
        }
        if (size == 0) revert("DeploymentFailed()");
    }

    function _logDeployment(DeploymentState memory state) internal view {
        console.log("\n=== Ponder Protocol Deployment ===");
        console.log("Deployer:", state.deployer);
        console.log("PONDER Token:", state.ponder);
        console.log("Factory:", state.factory);
        console.log("Router:", state.router);
        console.log("Oracle:", state.oracle);
        console.log("Staking:", state.staking);
        console.log("MasterChef:", state.masterChef);
        console.log("FeeDistributor:", state.feeDistributor);
        console.log("Launcher:", state.launcher);
        console.log("PONDER-KUB Pair:", state.ponderKubPair);
    }

    receive() external payable {}
}
