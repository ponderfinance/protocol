// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { PonderFactory } from "../../src/core/factory/PonderFactory.sol";
import { PonderToken } from "../../src/core/token/PonderToken.sol";
import { PonderMasterChef } from "../../src/core/masterchef/PonderMasterChef.sol";
import { PonderPriceOracle } from "../../src/core/oracle/PonderPriceOracle.sol";
import { PonderStaking } from "../../src/core/staking/PonderStaking.sol";
import { FeeDistributor } from "../../src/core/distributor/FeeDistributor.sol";
import { KKUBUnwrapper } from "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import { PonderRouter } from "../../src/periphery/router/PonderRouter.sol";
import { IPonderRouter } from "../../src/periphery/router/IPonderRouter.sol";
import { FiveFiveFiveLauncher } from "../../src/launch/FiveFiveFiveLauncher.sol";

contract DeployBitkubScript is Script {
    address constant public KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
    uint256 constant public INITIAL_PONDER_PER_SECOND = 3168000000000000000;
    uint256 constant public INITIAL_KUB_AMOUNT = 1000 ether;
    uint256 constant public INITIAL_LIQUIDITY_ALLOCATION = 200_000_000 ether;

    struct CoreAddresses {
        address ponder;
        address factory;
        address kkubUnwrapper;
        address router;
        address oracle;
        address staking;
        address masterChef;
        address feeDistributor;
        address launcher;
        address ponderKubPair;
    }

    struct ParticipantAddresses {
        address deployer;
        address teamReserve;
        address marketing;
    }

    struct DeploymentState {
        ParticipantAddresses participants;
        CoreAddresses core;
        uint256 deploymentStartTime;
        bool initialized;
    }

    DeploymentState private state;

    event ContractDeployed(string indexed name, address indexed addr);
    event ConfigurationFinalized(address indexed factory, address indexed masterChef, address indexed feeDistributor);
    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);

    function initialize(address deployer, address teamReserve, address marketing) internal {
        require(!state.initialized, "Already initialized");
        require(deployer != address(0) && teamReserve != address(0) && marketing != address(0), "Invalid addresses");

        state.participants = ParticipantAddresses({
            deployer: deployer,
            teamReserve: teamReserve,
            marketing: marketing
        });
        state.deploymentStartTime = block.timestamp;
        state.initialized = true;
    }

    function deployCoreProtocol() internal {
        // Deploy factory and peripherals first
        state.core.factory = address(new PonderFactory(
            state.participants.deployer,
            address(0),  // feeTo set later
            address(0)   // ponder set later
        ));

        state.core.kkubUnwrapper = address(new KKUBUnwrapper(KKUB));
        state.core.router = address(new PonderRouter(
            state.core.factory,
            KKUB,
            state.core.kkubUnwrapper
        ));

        // First deploy token with temporary staking address
        state.core.ponder = address(new PonderToken(
            state.participants.teamReserve,
            state.participants.deployer,  // launcher
            address(1)  // temporary staking address
        ));

        // Now deploy staking with actual PONDER address
        state.core.staking = address(new PonderStaking(
            state.core.ponder,
            state.core.router,
            state.core.factory
        ));

        // Set up remaining contracts
        state.core.oracle = address(new PonderPriceOracle(state.core.factory, KKUB));
        emit ContractDeployed("Oracle", state.core.oracle);

        state.core.feeDistributor = address(new FeeDistributor(
            state.core.factory,
            state.core.router,
            state.core.ponder,
            state.core.staking
        ));
        emit ContractDeployed("FeeDistributor", state.core.feeDistributor);

        state.core.launcher = address(new FiveFiveFiveLauncher(
            state.core.factory,
            payable(state.core.router),
            state.participants.teamReserve,
            state.core.ponder,
            state.core.oracle
        ));
        emit ContractDeployed("Launcher", state.core.launcher);

        state.core.masterChef = address(new PonderMasterChef(
            PonderToken(state.core.ponder),
            PonderFactory(state.core.factory),
            state.participants.teamReserve,
            INITIAL_PONDER_PER_SECOND
        ));
        emit ContractDeployed("MasterChef", state.core.masterChef);

        // Create PONDER-KUB pair
        console.log("Creating PONDER-KUB pair...");
        PonderFactory(state.core.factory).createPair(state.core.ponder, KKUB);
        state.core.ponderKubPair = PonderFactory(state.core.factory).getPair(state.core.ponder, KKUB);
        require(state.core.ponderKubPair != address(0), "Pair creation failed");
        emit ContractDeployed("PONDER-KUB Pair", state.core.ponderKubPair);

        // Setup initial liquidity
        setupInitialLiquidity();
    }

    function setupInitialLiquidity() internal {
        // Add approvals
        PonderToken(state.core.ponder).approve(state.core.router, INITIAL_LIQUIDITY_ALLOCATION);

        // Add liquidity
        try IPonderRouter(state.core.router).addLiquidityETH{value: INITIAL_KUB_AMOUNT}(
            state.core.ponder,
            INITIAL_LIQUIDITY_ALLOCATION,
            INITIAL_LIQUIDITY_ALLOCATION,
            INITIAL_KUB_AMOUNT,
            state.participants.deployer,
            block.timestamp + 300
        ) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
            emit LiquidityAdded(amountETH, amountToken);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Liquidity addition failed: ", reason)));
        }
    }

    function finalizeConfiguration() internal {
        // Update staking address in token
        PonderToken(state.core.ponder).setStaking(state.core.staking);

        // Set remaining configurations
        PonderToken(state.core.ponder).setMinter(state.core.masterChef);
        PonderToken(state.core.ponder).setLauncher(state.core.launcher);
        PonderFactory(state.core.factory).setFeeTo(state.core.feeDistributor);
        PonderFactory(state.core.factory).setPonder(state.core.ponder);

        // Ensure liquidity is added before initializing oracle
        console.log("Skipping Oracle initialization, run manually after liquidity is added.");

        emit ConfigurationFinalized(state.core.factory, state.core.masterChef, state.core.feeDistributor);

        console.log("Deployment Summary:");
        console.log("Deployer:", state.participants.deployer);
        console.log("PONDER Token:", state.core.ponder);
        console.log("Factory:", state.core.factory);
        console.log("Router:", state.core.router);
        console.log("Oracle:", state.core.oracle);
        console.log("Staking:", state.core.staking);
        console.log("MasterChef:", state.core.masterChef);
        console.log("FeeDistributor:", state.core.feeDistributor);
        console.log("Launcher:", state.core.launcher);
        console.log("KKUBUnwrapper:", state.core.kkubUnwrapper);
        console.log("PONDER-KUB Pair:", state.core.ponderKubPair);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");
        address marketing = vm.envAddress("MARKETING_ADDRESS");

        initialize(deployer, teamReserve, marketing);
        vm.startBroadcast(deployerPrivateKey);
        deployCoreProtocol();
        finalizeConfiguration();
        vm.stopBroadcast();
    }
}
