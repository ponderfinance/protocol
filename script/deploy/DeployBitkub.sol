// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IPonderPair } from "../../src/core/pair/IPonderPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PonderRouterLiquidityLib } from "../../src/periphery/router/libraries/PonderRouterLiquidityLib.sol";
import { PonderRouterMathLib } from "../../src/periphery/router/libraries/PonderRouterMathLib.sol";
import { PonderRouterSwapLib } from "../../src/periphery/router/libraries/PonderRouterSwapLib.sol";


// Core Protocol
import { PonderFactory } from "../../src/core/factory/PonderFactory.sol";
import { PonderToken } from "../../src/core/token/PonderToken.sol";
import { PonderMasterChef } from "../../src/core/masterchef/PonderMasterChef.sol";
import { PonderPriceOracle } from "../../src/core/oracle/PonderPriceOracle.sol";
import { PonderStaking } from "../../src/core/staking/PonderStaking.sol";
import { FeeDistributor } from "../../src/core/distributor/FeeDistributor.sol";

// Launch System
import { FiveFiveFiveLauncher } from "../../src/launch/FiveFiveFiveLauncher.sol";
// Launch System Libraries
import { FiveFiveFiveContributionLib } from "../../src/launch/libraries/FiveFiveFiveContributionLib.sol";
import { FiveFiveFiveFinalizationLib } from "../../src/launch/libraries/FiveFiveFiveFinalizationLib.sol";
import { FiveFiveFiveInitLib } from "../../src/launch/libraries/FiveFiveFiveInitLib.sol";
import { FiveFiveFivePoolLib } from "../../src/launch/libraries/FiveFiveFivePoolLib.sol";
import { FiveFiveFiveRefundLib } from "../../src/launch/libraries/FiveFiveFiveRefundLib.sol";
import { FiveFiveFiveValidation } from "../../src/launch/libraries/FiveFiveFiveValidation.sol";
import { FiveFiveFiveViewLib } from "../../src/launch/libraries/FiveFiveFiveViewLib.sol";
import { KKUBUnwrapper } from "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import { PonderRouter } from "../../src/periphery/router/PonderRouter.sol";
import { IPonderRouter } from "../../src/periphery/router/IPonderRouter.sol";

contract DeployBitkubScript is Script {
    // Protocol Constants
    address constant public USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
    address constant public KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
    uint256 constant public INITIAL_PONDER_PER_SECOND = 3168000000000000000;
    uint256 constant public DEPLOYMENT_TIMEOUT = 1 hours;
    uint256 constant public INITIAL_KUB_AMOUNT = 1000 ether;
    uint256 constant public INITIAL_LIQUIDITY_ALLOCATION = 200_000_000 ether;

    // Library References
    struct RouterLibraries {
        address liquidityLib;
        address mathLib;
        address swapLib;
    }

    struct LauncherLibraries {
        address contributionLib;
        address finalizationLib;
        address initLib;
        address poolLib;
        address refundLib;
        address validationLib;
        address viewLib;
    }

    // Core Protocol Addresses
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

    // Deployment Participants
    struct ParticipantAddresses {
        address deployer;
        address teamReserve;
        address marketing;
    }

    // Complete Deployment State
    struct DeploymentState {
        ParticipantAddresses participants;
        CoreAddresses core;
        RouterLibraries routerLibs;
        LauncherLibraries launcherLibs;
        uint256 deploymentStartTime;
        bool initialized;
    }

    // State Variables
    DeploymentState private state;
    mapping(bytes32 => address) internal deployedLibraries;

    // Events
    event DeploymentStarted(address indexed deployer, uint256 deadline);
    event LibraryDeployed(string indexed name, address indexed addr, bytes32 codehash);
    event ContractDeployed(string indexed name, address indexed addr);
    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
    event ConfigurationFinalized(address indexed factory, address indexed masterChef, address indexed feeDistributor);
    event DeploymentPhaseCompleted(string phase, bool success);

    function initialize(
        address deployer,
        address teamReserve,
        address marketing
    ) internal {
        require(!state.initialized, "Already initialized");
        require(
            deployer != address(0) &&
            teamReserve != address(0) &&
            marketing != address(0),
            "Invalid addresses"
        );

        state.participants = ParticipantAddresses({
            deployer: deployer,
            teamReserve: teamReserve,
            marketing: marketing
        });

        state.deploymentStartTime = block.timestamp;
        state.initialized = true;

        emit DeploymentStarted(deployer, block.timestamp + DEPLOYMENT_TIMEOUT);
    }

    // Add this after initialize() and before run()

    function deployAllLibraries() internal {
        console.log("\nDeploying libraries...");

        // Deploy Router Libraries
        state.routerLibs = RouterLibraries({
            liquidityLib: deployLibrary(type(PonderRouterLiquidityLib).creationCode, "RouterLiquidityLib"),
            mathLib: deployLibrary(type(PonderRouterMathLib).creationCode, "RouterMathLib"),
            swapLib: deployLibrary(type(PonderRouterSwapLib).creationCode, "RouterSwapLib")
        });

        // Deploy Launcher Libraries
        state.launcherLibs = LauncherLibraries({
            contributionLib: deployLibrary(type(FiveFiveFiveContributionLib).creationCode, "ContributionLib"),
            finalizationLib: deployLibrary(type(FiveFiveFiveFinalizationLib).creationCode, "FinalizationLib"),
            initLib: deployLibrary(type(FiveFiveFiveInitLib).creationCode, "InitLib"),
            poolLib: deployLibrary(type(FiveFiveFivePoolLib).creationCode, "PoolLib"),
            refundLib: deployLibrary(type(FiveFiveFiveRefundLib).creationCode, "RefundLib"),
            validationLib: deployLibrary(type(FiveFiveFiveValidation).creationCode, "ValidationLib"),
            viewLib: deployLibrary(type(FiveFiveFiveViewLib).creationCode, "ViewLib")
        });

        emit DeploymentPhaseCompleted("Library Deployment", true);
    }

    function deployLibrary(bytes memory bytecode, string memory name) internal returns (address lib) {
        console.log("Deploying %s...", name);

        bytes32 codeHash = keccak256(bytecode);
        if (deployedLibraries[codeHash] != address(0)) {
            lib = deployedLibraries[codeHash];
            console.log("Already deployed at: %s", lib);
            emit LibraryDeployed(name, lib, codeHash);
            return lib;
        }

        assembly {
            lib := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(lib)) { revert(0, 0) }
        }

        require(lib != address(0), string(abi.encodePacked("Failed to deploy ", name)));
        deployedLibraries[codeHash] = lib;

        console.log("Deployed at: %s", lib);
        emit LibraryDeployed(name, lib, codeHash);
        return lib;
    }

    function linkLibrary(
        bytes memory bytecode,
        string memory libraryName,
        address libraryAddress
    ) internal pure returns (bytes memory) {
        bytes32 libraryHash = keccak256(abi.encodePacked(libraryName));

        for (uint256 i = 0; i < bytecode.length - 33; i++) {
            // Look for placeholder pattern __$<hash>__
            if (bytecode[i] == 0x5f && bytecode[i + 1] == 0x5f && bytecode[i + 2] == 0x24) {
                bytes32 hash;
                for (uint256 j = 0; j < 32; j++) {
                    hash |= bytes32(bytecode[i + j + 3] & 0xFF) >> (8 * (31 - j));
                }

                if (hash == libraryHash) {
                    // Replace placeholder with actual address
                    for (uint256 j = 0; j < 20; j++) {
                        bytecode[i + j] = bytes1(uint8(uint160(libraryAddress) >> (8 * (19 - j))));
                    }
                }
            }
        }
        return bytecode;
    }

    function deployCoreProtocol() internal {
        console.log("\nDeploying core protocol...");

        // 1. Deploy PONDER Token first (no dependencies)
        state.core.ponder = address(new PonderToken(
            state.participants.teamReserve,
            state.participants.marketing,
            state.participants.deployer
        ));
        emit ContractDeployed("PONDER", state.core.ponder);
        console.log("PONDER Token deployed at: %s", state.core.ponder);

        // 2. Deploy Factory (depends on PONDER)
        state.core.factory = address(new PonderFactory(
            state.participants.deployer,
            address(0),
            state.core.ponder
        ));
        emit ContractDeployed("Factory", state.core.factory);
        console.log("Factory deployed at: %s", state.core.factory);

        // 3. Deploy KKUBUnwrapper (depends on KKUB)
        state.core.kkubUnwrapper = address(new KKUBUnwrapper(KKUB));
        emit ContractDeployed("KKUBUnwrapper", state.core.kkubUnwrapper);
        console.log("KKUBUnwrapper deployed at: %s", state.core.kkubUnwrapper);

        // 4. Deploy Router (depends on Factory, KKUB, KKUBUnwrapper + libraries)
        state.core.router = deployRouterWithLibraries(
            state.routerLibs,
            state.core.factory,
            KKUB,
            state.core.kkubUnwrapper
        );
        emit ContractDeployed("Router", state.core.router);
        console.log("Router deployed at: %s", state.core.router);

        // Create PONDER-KUB pair
        PonderFactory(state.core.factory).createPair(state.core.ponder, KKUB);
        state.core.ponderKubPair = PonderFactory(state.core.factory).getPair(state.core.ponder, KKUB);
        require(state.core.ponderKubPair != address(0), "Pair creation failed");
        emit ContractDeployed("PONDER-KUB Pair", state.core.ponderKubPair);
        console.log("PONDER-KUB Pair created at: %s", state.core.ponderKubPair);

        // 5. Deploy Oracle (depends on Factory, KKUB, USDT)
        state.core.oracle = address(new PonderPriceOracle(
            state.core.factory,
            KKUB,
            USDT
        ));
        emit ContractDeployed("Oracle", state.core.oracle);
        console.log("Oracle deployed at: %s", state.core.oracle);

        // 6. Deploy Staking (depends on PONDER, Router, Factory)
        state.core.staking = address(new PonderStaking(
            state.core.ponder,
            state.core.router,
            state.core.factory
        ));
        emit ContractDeployed("Staking", state.core.staking);
        console.log("Staking deployed at: %s", state.core.staking);

        // 7. Deploy FeeDistributor
        state.core.feeDistributor = address(new FeeDistributor(
            state.core.factory,
            state.core.router,
            state.core.ponder,
            state.core.staking,
            state.participants.teamReserve
        ));
        emit ContractDeployed("FeeDistributor", state.core.feeDistributor);
        console.log("FeeDistributor deployed at: %s", state.core.feeDistributor);

        // 8. Deploy Launcher
        state.core.launcher = deployLauncherWithLibraries(
            state.launcherLibs,
            state.core.factory,
            state.core.router,
            state.participants.teamReserve,
            state.core.ponder,
            state.core.oracle
        );
        emit ContractDeployed("Launcher", state.core.launcher);
        console.log("Launcher deployed at: %s", state.core.launcher);

        // 9. Deploy MasterChef
        state.core.masterChef = address(new PonderMasterChef(
            PonderToken(state.core.ponder),
            PonderFactory(state.core.factory),
            state.participants.teamReserve,
            INITIAL_PONDER_PER_SECOND
        ));
        emit ContractDeployed("MasterChef", state.core.masterChef);
        console.log("MasterChef deployed at: %s", state.core.masterChef);

        emit DeploymentPhaseCompleted("Core Protocol Deployment", true);
    }

    function deployRouterWithLibraries(
        RouterLibraries memory libs,
        address factory,
        address kkub,
        address kkubUnwrapper
    ) internal returns (address routerAddress) {
        bytes memory bytecode = type(PonderRouter).creationCode;
        bytecode = linkLibrary(bytecode, "PonderRouterLiquidityLib", libs.liquidityLib);
        bytecode = linkLibrary(bytecode, "PonderRouterMathLib", libs.mathLib);
        bytecode = linkLibrary(bytecode, "PonderRouterSwapLib", libs.swapLib);

        bytes memory constructorArgs = abi.encode(factory, kkub, kkubUnwrapper);
        bytes memory deploymentBytecode = abi.encodePacked(bytecode, constructorArgs);

        assembly {
            routerAddress := create(0, add(deploymentBytecode, 0x20), mload(deploymentBytecode))
            if iszero(extcodesize(routerAddress)) { revert(0, 0) }
        }

        require(routerAddress != address(0), "Router deployment failed");
        return routerAddress;
    }

    function deployLauncherWithLibraries(
        LauncherLibraries memory libs,
        address factory,
        address router,
        address teamReserve,
        address ponder,
        address oracle
    ) internal returns (address launcherAddress) {
        bytes memory bytecode = type(FiveFiveFiveLauncher).creationCode;
        bytecode = linkLibrary(bytecode, "FiveFiveFiveContributionLib", libs.contributionLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveFinalizationLib", libs.finalizationLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveInitLib", libs.initLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFivePoolLib", libs.poolLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveRefundLib", libs.refundLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveValidation", libs.validationLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveViewLib", libs.viewLib);

        bytes memory constructorArgs = abi.encode(
            factory,
            router,
            teamReserve,
            ponder,
            oracle
        );

        bytes memory deploymentBytecode = abi.encodePacked(bytecode, constructorArgs);
        assembly {
            launcherAddress := create(0, add(deploymentBytecode, 0x20), mload(deploymentBytecode))
            if iszero(extcodesize(launcherAddress)) { revert(0, 0) }
        }

        require(launcherAddress != address(0), "Launcher deployment failed");
        return launcherAddress;
    }

    function setupInitialLiquidity() internal {
        console.log("\nSetting up initial liquidity...");

        // Approve router for PONDER transfers
        console.log("Approving router for PONDER transfers...");
        require(
            PonderToken(state.core.ponder).approve(
                state.core.router,
                INITIAL_LIQUIDITY_ALLOCATION
            ),
            "Router approval failed"
        );

        // Add initial liquidity
        console.log("Adding initial liquidity...");
        console.log("KUB Amount: %s", INITIAL_KUB_AMOUNT);
        console.log("PONDER Amount: %s", INITIAL_LIQUIDITY_ALLOCATION);

        try IPonderRouter(state.core.router).addLiquidityETH{value: INITIAL_KUB_AMOUNT}(
            state.core.ponder,
            INITIAL_LIQUIDITY_ALLOCATION,
            INITIAL_LIQUIDITY_ALLOCATION,  // min PONDER
            INITIAL_KUB_AMOUNT,            // min ETH
            state.participants.deployer,    // LP tokens recipient
            block.timestamp + 300          // deadline
        ) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
            console.log("Liquidity added successfully:");
            console.log("- PONDER added: %s", amountToken);
            console.log("- KUB added: %s", amountETH);
            console.log("- LP tokens received: %s", liquidity);

            emit LiquidityAdded(amountETH, amountToken);
        } catch Error(string memory reason) {
            console.log("Liquidity addition failed: %s", reason);
            revert(string(abi.encodePacked("Liquidity addition failed: ", reason)));
        }

        // Validate liquidity was added correctly
        validateLiquiditySetup();

        emit DeploymentPhaseCompleted("Liquidity Setup", true);
    }

    function validateLiquiditySetup() internal view {
        // Get pair address
        address pair = PonderFactory(state.core.factory).getPair(
            state.core.ponder,
            KKUB
        );
        require(pair == state.core.ponderKubPair, "Pair address mismatch");

        // Check reserves
        (uint112 reserve0, uint112 reserve1,) = IPonderPair(pair).getReserves();
        require(reserve0 > 0 && reserve1 > 0, "Zero reserves");

        // Verify deployer received LP tokens
        uint256 lpBalance = IERC20(pair).balanceOf(state.participants.deployer);
        require(lpBalance > 0, "No LP tokens minted");

        console.log("Liquidity setup validated successfully");
        console.log("- Pair reserves: %s / %s", reserve0, reserve1);
        console.log("- Deployer LP balance: %s", lpBalance);
    }

    function finalizeConfiguration() internal {
        console.log("\nFinalizing protocol configuration...");

        // Configure PONDER token permissions
        console.log("Configuring PONDER token permissions...");
        PonderToken ponder = PonderToken(state.core.ponder);
        ponder.setMinter(state.core.masterChef);
        ponder.setLauncher(state.core.launcher);
        console.log("- MasterChef set as minter");
        console.log("- Launcher permissions configured");

        // Configure Factory permissions
        console.log("Configuring Factory permissions...");
        PonderFactory factory = PonderFactory(state.core.factory);
        factory.setFeeTo(state.core.feeDistributor);
        factory.setLauncher(state.core.launcher);
        factory.setPonder(state.core.ponder);
        console.log("- FeeDistributor set as fee recipient");
        console.log("- Launcher permissions configured");
        console.log("- PONDER token configured");

        // Initialize Oracle for PONDER-KUB pair
        console.log("Initializing Oracle for PONDER-KUB pair...");
        PonderPriceOracle(state.core.oracle).initializePair(state.core.ponderKubPair);
        console.log("- Oracle initialized for PONDER-KUB pair");

        emit ConfigurationFinalized(
            state.core.factory,
            state.core.masterChef,
            state.core.feeDistributor
        );

        // Validate final configuration
        validateFinalConfiguration();

        emit DeploymentPhaseCompleted("Configuration Finalization", true);
    }


    function validateFinalConfiguration() internal view {
        // Validate PONDER configuration
        PonderToken ponder = PonderToken(state.core.ponder);
        require(ponder.minter() == state.core.masterChef, "Invalid minter");
        require(ponder.launcher() == state.core.launcher, "Invalid launcher");

        // Validate Factory configuration
        PonderFactory factory = PonderFactory(state.core.factory);
        require(factory.feeTo() == state.core.feeDistributor, "Invalid fee recipient");
        require(factory.ponder() == state.core.ponder, "Invalid factory ponder");

        // Validate Oracle initialization
        require(
            PonderPriceOracle(state.core.oracle).isPairInitialized(state.core.ponderKubPair),
            "Oracle pair not initialized"
        );

        console.log("Final configuration validated successfully");
    }

    function logDeployment() internal view {
        console.log("\n=== Ponder Protocol Deployment Summary ===");
        console.log("Deployer:", state.participants.deployer);
        console.log("\nCore Protocol:");
        console.log("- PONDER Token:", state.core.ponder);
        console.log("- Factory:", state.core.factory);
        console.log("- Router:", state.core.router);
        console.log("- Oracle:", state.core.oracle);
        console.log("- Staking:", state.core.staking);
        console.log("- MasterChef:", state.core.masterChef);
        console.log("- FeeDistributor:", state.core.feeDistributor);
        console.log("- Launcher:", state.core.launcher);
        console.log("- PONDER-KUB Pair:", state.core.ponderKubPair);
        console.log("- KKUBUnwrapper:", state.core.kkubUnwrapper);

        console.log("\nRouter Libraries:");
        console.log("- LiquidityLib:", state.routerLibs.liquidityLib);
        console.log("- MathLib:", state.routerLibs.mathLib);
        console.log("- SwapLib:", state.routerLibs.swapLib);

        console.log("\nLauncher Libraries:");
        console.log("- ContributionLib:", state.launcherLibs.contributionLib);
        console.log("- FinalizationLib:", state.launcherLibs.finalizationLib);
        console.log("- InitLib:", state.launcherLibs.initLib);
        console.log("- PoolLib:", state.launcherLibs.poolLib);
        console.log("- RefundLib:", state.launcherLibs.refundLib);
        console.log("- ValidationLib:", state.launcherLibs.validationLib);
        console.log("- ViewLib:", state.launcherLibs.viewLib);
    }

    // Updated run function
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");
        address marketing = vm.envAddress("MARKETING_ADDRESS");

        // Initialize deployment state
        initialize(deployer, teamReserve, marketing);

        // Start deployment
        vm.startBroadcast(deployerPrivateKey);

        deployAllLibraries();
        deployCoreProtocol();
        setupInitialLiquidity();
        finalizeConfiguration();

        // Log final deployment information
        logDeployment();

        vm.stopBroadcast();
    }
}
