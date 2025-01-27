// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "../../src/core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../src/periphery/router/IPonderRouter.sol";
import { PonderFactory } from "../../src/core/factory/PonderFactory.sol";
import { PonderMasterChef } from "../../src/core/masterchef/PonderMasterChef.sol";
import { PonderPriceOracle } from "../../src/core/oracle/PonderPriceOracle.sol";
import { PonderToken } from "../../src/core/token/PonderToken.sol";
import { PonderStaking } from "../../src/core/staking/PonderStaking.sol";
import { FeeDistributor } from "../../src/core/distributor/FeeDistributor.sol";
import { FiveFiveFiveLauncher } from "../../src/launch/FiveFiveFiveLauncher.sol";
import { KKUBUnwrapper } from "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import { PonderRouter } from "../../src/periphery/router/PonderRouter.sol";

// Libraries
import { FiveFiveFiveContributionLib } from "../../src/launch/libraries/FiveFiveFiveContributionLib.sol";
import { FiveFiveFiveFinalizationLib } from "../../src/launch/libraries/FiveFiveFiveFinalizationLib.sol";
import { FiveFiveFiveInitLib } from "../../src/launch/libraries/FiveFiveFiveInitLib.sol";
import { FiveFiveFivePoolLib } from "../../src/launch/libraries/FiveFiveFivePoolLib.sol";
import { FiveFiveFiveRefundLib } from "../../src/launch/libraries/FiveFiveFiveRefundLib.sol";
import { FiveFiveFiveValidation } from "../../src/launch/libraries/FiveFiveFiveValidation.sol";
import { FiveFiveFiveViewLib } from "../../src/launch/libraries/FiveFiveFiveViewLib.sol";
import { PonderLaunchGuard } from "../../src/launch/libraries/PonderLaunchGuard.sol";
import "forge-std/Script.sol";

contract DeployBitkubScript is Script {
    // Constants
    address constant public USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
    address constant public KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
    uint256 constant public INITIAL_PONDER_PER_SECOND = 3168000000000000000;
    uint256 constant public DEPLOYMENT_TIMEOUT = 1 hours;

    struct LibraryAddresses {
        address contributionLib;
        address finalizationLib;
        address initLib;
        address poolLib;
        address refundLib;
        address validationLib;
        address viewLib;
        address launchGuard;
    }

    struct DeploymentState {
        address deployer;
        address teamReserve;
        address marketing;
        uint256 deploymentStartTime;
        address factory;
        address ponder;
        address router;
        address oracle;
        address staking;
        address masterChef;
        address feeDistributor;
        address launcher;
        address kkubUnwrapper;
        address ponderKubPair;
        uint256 initialKubAmount;
        uint256 liquidityAllocation;
    }

    // Events
    event DeploymentStarted(address indexed deployer, uint256 deadline);
    event LibraryDeployed(string indexed name, address indexed addr, bytes32 codehash);
    event ContractDeployed(string indexed name, address indexed addr);
    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
    event ConfigurationFinalized(address indexed factory, address indexed masterChef, address indexed feeDistributor);
    event DeploymentProgress(string step, bool success);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");
        address marketing = vm.envAddress("MARKETING_ADDRESS");

        if (teamReserve == address(0) || marketing == address(0) || deployer == address(0)) {
            revert("Invalid addresses");
        }

        emit DeploymentStarted(deployer, block.timestamp + DEPLOYMENT_TIMEOUT);

        vm.startBroadcast(deployerPrivateKey);

        // Create deployment state
        DeploymentState memory state = DeploymentState({
            deployer: deployer,
            teamReserve: teamReserve,
            marketing: marketing,
            deploymentStartTime: block.timestamp,
            factory: address(0),
            ponder: address(0),
            router: address(0),
            oracle: address(0),
            staking: address(0),
            masterChef: address(0),
            feeDistributor: address(0),
            launcher: address(0),
            kkubUnwrapper: address(0),
            ponderKubPair: address(0),
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether
        });

        // Deploy libraries first (single deployment)
        LibraryAddresses memory libs = deployLibraries();
        emit DeploymentProgress("Libraries deployed", true);

        // Deploy core contracts
        state = deployCore(state, libs);
        emit DeploymentProgress("Core contracts deployed", true);

        // Setup initial liquidity
        setupInitialLiquidity(state);
        emit DeploymentProgress("Initial liquidity added", true);

        // Finalize deployment
        finalizeDeployment(state);
        emit DeploymentProgress("Deployment finalized", true);

        logDeployment(state);

        vm.stopBroadcast();
    }

    function deployLibraries() internal returns (LibraryAddresses memory libs) {
        libs.contributionLib = deployLibrary(
            type(FiveFiveFiveContributionLib).creationCode,
            "ContributionLib"
        );

        libs.finalizationLib = deployLibrary(
            type(FiveFiveFiveFinalizationLib).creationCode,
            "FinalizationLib"
        );

        libs.initLib = deployLibrary(
            type(FiveFiveFiveInitLib).creationCode,
            "InitLib"
        );

        libs.poolLib = deployLibrary(
            type(FiveFiveFivePoolLib).creationCode,
            "PoolLib"
        );

        libs.refundLib = deployLibrary(
            type(FiveFiveFiveRefundLib).creationCode,
            "RefundLib"
        );

        libs.validationLib = deployLibrary(
            type(FiveFiveFiveValidation).creationCode,
            "ValidationLib"
        );

        libs.viewLib = deployLibrary(
            type(FiveFiveFiveViewLib).creationCode,
            "ViewLib"
        );

        libs.launchGuard = deployLibrary(
            type(PonderLaunchGuard).creationCode,
            "LaunchGuard"
        );

        return libs;
    }

    function deployLibrary(bytes memory bytecode, string memory name) internal returns (address lib) {
        // Check if the library already exists by its bytecode hash
        bytes32 codeHash = keccak256(bytecode);
        if (deployedLibraries[codeHash] != address(0)) {
            lib = deployedLibraries[codeHash];
            emit LibraryDeployed(name, lib, codeHash);
            return lib; // Library already deployed, reuse it
        }

        // Deploy the library
        assembly {
            lib := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(lib)) { revert(0, 0) }
        }

        // Track the deployed library address
        deployedLibraries[codeHash] = lib;
        emit LibraryDeployed(name, lib, codeHash);
        return lib;
    }

// Storage for deployed library addresses
    mapping(bytes32 => address) internal deployedLibraries;

    function deployCore(DeploymentState memory state, LibraryAddresses memory libs) internal returns (DeploymentState memory) {
        // Deploy Factory
        state.factory = address(new PonderFactory(state.deployer, address(0), address(0)));
        emit ContractDeployed("Factory", state.factory);

        // Deploy PONDER Token
        state.ponder = address(new PonderToken(state.teamReserve, state.marketing, state.deployer));
        emit ContractDeployed("PONDER", state.ponder);

        // Deploy KKUBUnwrapper
        state.kkubUnwrapper = address(new KKUBUnwrapper(KKUB));
        emit ContractDeployed("KKUBUnwrapper", state.kkubUnwrapper);

        // Deploy Router
        state.router = address(new PonderRouter(
            state.factory,
            KKUB,
            state.kkubUnwrapper
        ));
        emit ContractDeployed("Router", state.router);

        // Create initial PONDER-KUB pair
        PonderFactory(state.factory).createPair(state.ponder, KKUB);
        state.ponderKubPair = PonderFactory(state.factory).getPair(state.ponder, KKUB);
        require(state.ponderKubPair != address(0), "Pair creation failed");
        emit ContractDeployed("PONDER-KUB Pair", state.ponderKubPair);

        // Deploy Oracle
        state.oracle = address(new PonderPriceOracle(
            state.factory,
            KKUB,
            USDT
        ));
        emit ContractDeployed("Oracle", state.oracle);

        // Deploy Staking
        state.staking = address(new PonderStaking(
            state.ponder,
            state.router,
            state.factory
        ));
        emit ContractDeployed("Staking", state.staking);

        // Deploy FeeDistributor
        state.feeDistributor = address(new FeeDistributor(
            state.factory,
            state.router,
            state.ponder,
            state.staking,
            state.teamReserve
        ));
        emit ContractDeployed("FeeDistributor", state.feeDistributor);

        // Deploy Launcher
        state.launcher = deployLauncherWithLibraries(
            libs,
            state.factory,
            state.router,
            state.teamReserve,
            state.ponder,
            state.oracle
        );
        emit ContractDeployed("Launcher", state.launcher);

        // Deploy MasterChef
        state.masterChef = address(new PonderMasterChef(
            PonderToken(state.ponder),
            PonderFactory(state.factory),
            state.teamReserve,
            INITIAL_PONDER_PER_SECOND
        ));
        emit ContractDeployed("MasterChef", state.masterChef);

        // Initial configuration
        PonderToken(state.ponder).setLauncher(state.launcher);
        PonderToken(state.ponder).setMinter(state.masterChef);
        PonderFactory(state.factory).setLauncher(state.launcher);

        return state;
    }

    function deployLauncherWithLibraries(
        LibraryAddresses memory libs,
        address factory,
        address router,
        address teamReserve,
        address ponder,
        address oracle
    ) internal returns (address launcherAddress) {
        // Verify all libraries are deployed
        require(libs.contributionLib != address(0), "ContributionLib not deployed");
        require(libs.finalizationLib != address(0), "FinalizationLib not deployed");
        require(libs.initLib != address(0), "InitLib not deployed");
        require(libs.poolLib != address(0), "PoolLib not deployed");
        require(libs.refundLib != address(0), "RefundLib not deployed");
        require(libs.validationLib != address(0), "ValidationLib not deployed");
        require(libs.viewLib != address(0), "ViewLib not deployed");
        require(libs.launchGuard != address(0), "LaunchGuard not deployed");

        // Link libraries
        bytes memory bytecode = type(FiveFiveFiveLauncher).creationCode;
        bytecode = linkLibrary(bytecode, "FiveFiveFiveContributionLib", libs.contributionLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveFinalizationLib", libs.finalizationLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveInitLib", libs.initLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFivePoolLib", libs.poolLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveRefundLib", libs.refundLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveValidation", libs.validationLib);
        bytecode = linkLibrary(bytecode, "FiveFiveFiveViewLib", libs.viewLib);
        bytecode = linkLibrary(bytecode, "PonderLaunchGuard", libs.launchGuard);

        // Encode constructor arguments
        bytes memory constructorArgs = abi.encode(
            factory,
            router,
            teamReserve,
            ponder,
            oracle
        );

        // Deploy launcher
        bytes memory deploymentBytecode = abi.encodePacked(bytecode, constructorArgs);
        assembly {
            launcherAddress := create(0, add(deploymentBytecode, 0x20), mload(deploymentBytecode))
            if iszero(extcodesize(launcherAddress)) { revert(0, 0) }
        }
        require(launcherAddress != address(0), "Launcher deployment failed");

        return launcherAddress;
    }

    function setupInitialLiquidity(DeploymentState memory state) internal {
        // Add approvals
        PonderToken(state.ponder).approve(state.router, state.liquidityAllocation);

        // Add liquidity
        try IPonderRouter(state.router).addLiquidityETH{value: state.initialKubAmount}(
            state.ponder,
            state.liquidityAllocation,
            state.liquidityAllocation,
            state.initialKubAmount,
            state.deployer,
            block.timestamp + 300
        ) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
            emit LiquidityAdded(amountETH, amountToken);
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Liquidity addition failed: ", reason)));
        }
    }

    function finalizeDeployment(DeploymentState memory state) internal {
        // Configure PONDER token permissions
        PonderToken(state.ponder).setMinter(state.masterChef);
        PonderToken(state.ponder).setLauncher(state.launcher);

        // Configure Factory permissions
        PonderFactory(state.factory).setLauncher(state.launcher);
        PonderFactory(state.factory).setPonder(state.ponder);
        PonderFactory(state.factory).setFeeTo(state.feeDistributor);

        emit ConfigurationFinalized(
            state.factory,
            state.masterChef,
            state.feeDistributor
        );
    }

    function linkLibrary(
        bytes memory bytecode,
        string memory libraryName,
        address libraryAddress
    ) internal pure returns (bytes memory) {
        bytes32 libraryHash = keccak256(abi.encodePacked(libraryName));
        for (uint256 i = 0; i < bytecode.length - 33; i++) {
            // Find placeholders in the bytecode (they start with __$)
            if (bytecode[i] == 0x5f && bytecode[i + 1] == 0x5f && bytecode[i + 2] == 0x24) {
                bytes32 hash;
                for (uint256 j = 0; j < 32; j++) {
                    hash |= bytes32(bytecode[i + j + 3] & 0xFF) >> (8 * (31 - j));
                }
                // If this is our library's placeholder
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

    function logDeployment(DeploymentState memory state) internal view {
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
