// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    uint256 constant public INITIAL_PONDER_PER_SECOND = 3168000000000000000;
    uint256 constant public INITIAL_KUB_AMOUNT = 1000 ether;
    uint256 constant public INITIAL_LIQUIDITY_ALLOCATION = 1_000_000 ether;

    address constant public TRANSFER_ROUTER = 0xFbf5b70ef07AE6F64D3796f8a0fE83A3579FAb6f;
    uint256 constant public ACCEPTED_KYC_LEVEL = 4;

    // KAP20 specific parameters - Bitkub Mainnet checksummed addresses
    address constant public ADMIN_PROJECT_ROUTER = 0x15122c945763da4435b45E082234108361B64eBA;
    address constant public COMMITTEE = 0xA755a1F6a35ba92835c0A23d3e5292e101d32716;
    address constant public KYC = 0x409CF41ee862Df7024f289E9F2Ea2F5d0D7f3eb4;
    address constant public KKUB =0x67eBD850304c70d983B2d1b93ea79c7CD6c3F6b5;


    //// TEST NET Bitkub Chain
//    address constant public ADMIN_PROJECT_ROUTER = 0xE4088E1f199287B1146832352aE5Fc3726171d41;
//    address constant public COMMITTEE = 0xEE4464a2055d2346FacF7813E862B92ffa91dcaE;
//    address constant public KYC = 0x2C8aBd9c61D4E973CA8db5545C54c90E44A2445c;
//    address constant public KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
//


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

    function initialize(address deployer, address teamReserve) public {
        require(!state.initialized, "Already initialized");
        require(deployer != address(0), "Invalid deployer address");
        require(teamReserve != address(0), "Invalid team reserve address");

        console.log("Initializing with:");
        console.log("Deployer:", deployer);
        console.log("Team Reserve:", teamReserve);

        state.participants = ParticipantAddresses({
            deployer: deployer,
            teamReserve: teamReserve
        });
        state.deploymentStartTime = block.timestamp;
        state.initialized = true;
    }

    function deployCoreProtocol() internal {
        require(state.initialized, "Not initialized");
        require(state.participants.deployer != address(0), "Deployer not set");
        console.log("Starting deployment with deployer:", state.participants.deployer);

        // Deploy KKUBUnwrapper first (no complex dependencies)
        console.log("Deploying KKUBUnwrapper...");
        state.core.kkubUnwrapper = address(new KKUBUnwrapper(KKUB));
        emit ContractDeployed("KKUBUnwrapper", state.core.kkubUnwrapper);

        // Deploy PONDER token with temporary staking address
        console.log("Deploying PONDER token...");
        state.core.ponder = address(new PonderToken(
            state.participants.teamReserve,
            state.participants.deployer,
            address(1)  // temporary staking address
        ));
        emit ContractDeployed("PONDER", state.core.ponder);

        // Set KAP20 parameters for the token
        console.log("Setting KAP20 parameters...");
        PonderToken ponderToken = PonderToken(state.core.ponder);
        ponderToken.setAdminProjectRouter(ADMIN_PROJECT_ROUTER);
        ponderToken.setCommittee(COMMITTEE);
        ponderToken.setKYC(KYC);
        ponderToken.setTransferRouter(TRANSFER_ROUTER);
        ponderToken.setAcceptedKYCLevel(ACCEPTED_KYC_LEVEL);
        console.log("KAP20 parameters set successfully");

        // Deploy Factory
        console.log("Deploying Factory...");
        state.core.factory = address(new PonderFactory(
            state.participants.deployer,  // feeToSetter
            state.participants.deployer,  // temporary launcher
            state.core.ponder
        ));
        emit ContractDeployed("Factory", state.core.factory);

        // Deploy Router
        console.log("Deploying Router...");
        state.core.router = address(new PonderRouter(
            state.core.factory,
            KKUB,
            state.core.kkubUnwrapper
        ));
        emit ContractDeployed("Router", state.core.router);

        // Deploy Oracle
        console.log("Deploying Oracle...");
        state.core.oracle = address(new PonderPriceOracle(state.core.factory, KKUB));
        emit ContractDeployed("Oracle", state.core.oracle);

        // Deploy Staking with actual PONDER
        console.log("Deploying Staking...");
        state.core.staking = address(new PonderStaking(
            state.core.ponder,
            state.core.router,
            state.core.factory
        ));
        emit ContractDeployed("Staking", state.core.staking);

        // Deploy FeeDistributor
        console.log("Deploying FeeDistributor...");
        state.core.feeDistributor = address(new FeeDistributor(
            state.core.factory,
            state.core.router,
            state.core.ponder,
            state.core.staking
        ));
        emit ContractDeployed("FeeDistributor", state.core.feeDistributor);

        // Deploy Launcher
        console.log("Deploying Launcher...");
        state.core.launcher = address(new FiveFiveFiveLauncher(
            state.core.factory,
            payable(state.core.router),
            state.participants.teamReserve,
            state.core.ponder,
            state.core.oracle
        ));
        emit ContractDeployed("Launcher", state.core.launcher);

        // Deploy MasterChef
        console.log("Deploying MasterChef...");
        state.core.masterChef = address(new PonderMasterChef(
            PonderToken(state.core.ponder),
            PonderFactory(state.core.factory),
            state.participants.teamReserve,
            INITIAL_PONDER_PER_SECOND
        ));
        emit ContractDeployed("MasterChef", state.core.masterChef);

        // Create and initialize PONDER-KUB pair
        console.log("Creating PONDER-KUB pair...");
        PonderFactory(state.core.factory).createPair(state.core.ponder, KKUB);
        state.core.ponderKubPair = PonderFactory(state.core.factory).getPair(state.core.ponder, KKUB);
        require(state.core.ponderKubPair != address(0), "Pair creation failed");
        emit ContractDeployed("PONDER-KUB Pair", state.core.ponderKubPair);

        // Setup initial liquidity
        setupInitialLiquidity();
    }

    function setupInitialLiquidity() internal {
        console.log("Setting up initial liquidity...");
        require(state.core.ponder != address(0), "PONDER token not deployed");
        require(state.core.router != address(0), "Router not deployed");

        // Define KKUB token amount
        uint256 kkubAmount = INITIAL_KUB_AMOUNT;

        // Approve router for PONDER spending
        PonderToken(state.core.ponder).approve(state.core.router, INITIAL_LIQUIDITY_ALLOCATION);

        // Approve router for KKUB spending
        IERC20(KKUB).approve(state.core.router, kkubAmount);

        try IPonderRouter(state.core.router).addLiquidity(
            state.core.ponder,
            KKUB,  // Use KKUB address directly
            INITIAL_LIQUIDITY_ALLOCATION,
            kkubAmount,
            INITIAL_LIQUIDITY_ALLOCATION,
            kkubAmount,
            state.participants.deployer,
            block.timestamp + 300
        ) returns (uint256 amountToken, uint256 amountKKUB, uint256 liquidity) {
            emit LiquidityAdded(amountKKUB, amountToken);
            console.log("Initial liquidity added successfully:");
            console.log("- KKUB added:", amountKKUB);
            console.log("- PONDER added:", amountToken);
            console.log("- LP tokens received:", liquidity);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Liquidity addition failed: ", reason)));
        }
    }

    function finalizeConfiguration() internal {
        require(state.initialized, "Not initialized");
        console.log("Finalizing configuration...");

        // Update PONDER's staking and other settings
        PonderToken(state.core.ponder).setStaking(state.core.staking);
        PonderToken(state.core.ponder).initializeStaking();
        PonderToken(state.core.ponder).setMinter(state.core.masterChef);
        PonderToken(state.core.ponder).setLauncher(state.core.launcher);

        // Update Factory settings
        PonderFactory(state.core.factory).setFeeTo(state.core.feeDistributor);

        emit ConfigurationFinalized(
            state.core.factory,
            state.core.masterChef,
            state.core.feeDistributor
        );

        logDeploymentSummary();
    }

    function logDeploymentSummary() internal view {
        console.log("=== Deployment Summary ===");
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
        console.log("=== KAP20 Configuration ===");
        console.log("Admin Project Router:", ADMIN_PROJECT_ROUTER);
        console.log("Committee:", COMMITTEE);
        console.log("KYC:", KYC);
        console.log("Transfer Router:", TRANSFER_ROUTER);
        console.log("Accepted KYC Level:", ACCEPTED_KYC_LEVEL);
    }

    function run() external {
        console.log("Starting deployment script...");

        // Get deployment parameters
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");

        console.log("Retrieved addresses:");
        console.log("Deployer:", deployer);
        console.log("Team Reserve:", teamReserve);

        // Initialize state
        initialize(deployer, teamReserve);

        // Start deployment
        vm.startBroadcast(deployerPrivateKey);

        deployCoreProtocol();
        finalizeConfiguration();

        vm.stopBroadcast();
    }
}
