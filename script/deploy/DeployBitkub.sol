// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderMasterChef.sol";
import "../../src/core/PonderPriceOracle.sol";
import "../../src/core/PonderToken.sol";
import "../../src/core/PonderStaking.sol";
import "../../src/core/FeeDistributor.sol";
import "../../src/launch/FiveFiveFiveLauncher.sol";
import "../../src/periphery/KKUBUnwrapper.sol";
import "../../src/periphery/PonderRouter.sol";
import "forge-std/Script.sol";

contract DeployBitkubScript is Script {
    // Total farming allocation is 400M PONDER over 4 years
    // This equals approximately 3.168 PONDER per second (400M / (4 * 365 * 24 * 60 * 60))
    uint256 constant PONDER_PER_SECOND = 3168000000000000000; // 3.168 ether

    address constant USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
    // testnet - 0xBa71efd94be63bD47B78eF458DE982fE29f552f7
    // mainnet - 0x7d984C24d2499D840eB3b7016077164e15E5faA6

    address constant KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
    // testnet - 0xBa71efd94be63bD47B78eF458DE982fE29f552f7
    // mainnet - 0x67eBD850304c70d983B2d1b93ea79c7CD6c3F6b5

    // Initial liquidity constants (PONDER = $0.0001, KUB = $2.80)
    uint256 constant INITIAL_KUB_AMOUNT = 1000 ether;                 // 1000 KUB
    uint256 constant INITIAL_PONDER_AMOUNT = 28_000_000 ether;       // 28M PONDER

    error InvalidAddress();
    error PairCreationFailed();
    error DeploymentFailed(string name);
    error LiquidityAddFailed();

    struct DeploymentAddresses {
        address ponder;
        address factory;
        address kkubUnwrapper;
        address router;
        address oracle;
        address ponderKubPair;
        address masterChef;
        address launcher;
        address staking;
        address feeDistributor;
    }

    function validateAddresses(
        address treasury,
        address teamReserve,
        address marketing,
        address deployer
    ) internal pure {
        if (treasury == address(0) ||
        teamReserve == address(0) ||
        marketing == address(0) ||
            deployer == address(0)
        ) {
            revert InvalidAddress();
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address teamReserve = vm.envAddress("TEAM_RESERVE_ADDRESS");
        address marketing = vm.envAddress("MARKETING_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        // Validate addresses
        validateAddresses(treasury, teamReserve, marketing, deployer);

        vm.startBroadcast(deployerPrivateKey);

        DeploymentAddresses memory addresses = deployContracts(
            deployer,
            treasury,
            teamReserve,
            marketing
        );

        vm.stopBroadcast();

        logDeployment(addresses, treasury);
    }

    function deployContracts(
        address deployer,
        address treasury,
        address teamReserve,
        address marketing
    ) internal returns (DeploymentAddresses memory addresses) {
        // 1. Deploy core factory and periphery
        PonderFactory factory = new PonderFactory(deployer, address(0), address(0));
        _verifyContract("PonderFactory", address(factory));

        KKUBUnwrapper kkubUnwrapper = new KKUBUnwrapper(KKUB);
        _verifyContract("KKUBUnwrapper", address(kkubUnwrapper));

        PonderRouter router = new PonderRouter(
            address(factory),
            KKUB,
            address(kkubUnwrapper)
        );
        _verifyContract("PonderRouter", address(router));

        // 2. Deploy PONDER with no launcher initially
        PonderToken ponder = new PonderToken(
            teamReserve,
            marketing,
            address(0)  // No launcher initially
        );
        _verifyContract("PonderToken", address(ponder));

        // 3. Create PONDER/KKUB pair
        factory.createPair(address(ponder), KKUB);
        address ponderKubPair = factory.getPair(address(ponder), KKUB);
        if (ponderKubPair == address(0)) revert PairCreationFailed();

        // 4. Deploy oracle
        PonderPriceOracle oracle = new PonderPriceOracle(
            address(factory),
            KKUB,
            USDT
        );
        _verifyContract("PonderPriceOracle", address(oracle));

        // 5. Deploy PonderStaking (xPONDER)
        PonderStaking staking = new PonderStaking(
            address(ponder),
            address(router),
            address(factory)
        );
        _verifyContract("PonderStaking", address(staking));

        // 6. Deploy fee distributor
        FeeDistributor feeDistributor = new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(staking),
            teamReserve
        );
        _verifyContract("FeeDistributor", address(feeDistributor));

        // 7. Deploy launcher
        FiveFiveFiveLauncher launcher = new FiveFiveFiveLauncher(
            address(factory),
            payable(address(router)),
            treasury,
            address(ponder),
            address(oracle)
        );
        _verifyContract("Launcher", address(launcher));

        // 8. Deploy MasterChef
        PonderMasterChef masterChef = new PonderMasterChef(
            ponder,
            factory,
            treasury,
            PONDER_PER_SECOND,
            block.timestamp
        );
        _verifyContract("MasterChef", address(masterChef));

        // 9. Setup initial prices and liquidity
        setupInitialPrices(ponder, router, oracle, ponderKubPair);

        // 10. Final configuration
        ponder.setMinter(address(masterChef));
        ponder.setLauncher(address(launcher));
        factory.setLauncher(address(launcher));
        factory.setPonder(address(ponder));
        factory.setFeeTo(address(feeDistributor));

        addresses = DeploymentAddresses({
            ponder: address(ponder),
            factory: address(factory),
            kkubUnwrapper: address(kkubUnwrapper),
            router: address(router),
            oracle: address(oracle),
            ponderKubPair: ponderKubPair,
            masterChef: address(masterChef),
            launcher: address(launcher),
            staking: address(staking),
            feeDistributor: address(feeDistributor)
        });

        return addresses;
    }

    function setupInitialPrices(
        PonderToken ponder,
        PonderRouter router,
        PonderPriceOracle oracle,
        address ponderKubPair
    ) internal {
        console.log("Initial timestamp:", block.timestamp);

        // Add liquidity
        ponder.approve(address(router), INITIAL_PONDER_AMOUNT);
        router.addLiquidityETH{value: INITIAL_KUB_AMOUNT}(
            address(ponder),
            INITIAL_PONDER_AMOUNT,
            INITIAL_PONDER_AMOUNT,
            INITIAL_KUB_AMOUNT,
            address(this),
            block.timestamp + 1 hours
        );
    }

    function _verifyContract(string memory name, address contractAddress) internal view {
        uint256 size;
        assembly {
            size := extcodesize(contractAddress)
        }
        if (size == 0) revert DeploymentFailed(name);
        console.log(name, "deployed at:", contractAddress);
    }

    function logDeployment(DeploymentAddresses memory addresses, address treasury) internal view {
        console.log("\nDeployment Summary on Bitkub Chain:");
        console.log("--------------------------------");
        console.log("KKUB Address:", KKUB);
        console.log("PonderToken:", addresses.ponder);
        console.log("Factory:", addresses.factory);
        console.log("KKUBUnwrapper:", addresses.kkubUnwrapper);
        console.log("Router:", addresses.router);
        console.log("PriceOracle:", addresses.oracle);
        console.log("PONDER/KKUB Pair:", addresses.ponderKubPair);
        console.log("MasterChef:", addresses.masterChef);
        console.log("FiveFiveFiveLauncher:", addresses.launcher);
        console.log("PonderStaking (xPONDER):", addresses.staking);
        console.log("FeeDistributor:", addresses.feeDistributor);
        console.log("Treasury:", treasury);

        console.log("\nProtocol Fee Configuration:");
        console.log("--------------------------------");
        console.log("Protocol fees enabled: Yes");
        console.log("Fee collector: FeeDistributor");
        console.log("Distribution: 80% xPONDER, 20% Team");

        console.log("\nInitial Liquidity Details:");
        console.log("--------------------------------");
        console.log("Initial KUB:", INITIAL_KUB_AMOUNT / 1e18);
        console.log("Initial PONDER:", INITIAL_PONDER_AMOUNT / 1e18);
        console.log("Initial PONDER Price in USD: $0.0001");
        console.log("Initial PONDER/KUB Rate:", INITIAL_PONDER_AMOUNT / INITIAL_KUB_AMOUNT);

        console.log("\nToken Allocation Summary:");
        console.log("--------------------------------");
        console.log("Liquidity Mining (40%):", uint256(400_000_000 * 1e18));
        console.log("Team/Reserve (15%):", uint256(150_000_000 * 1e18));
        console.log("Marketing/Community (10%):", uint256(100_000_000 * 1e18));
        console.log("Treasury/DAO (25%):", uint256(250_000_000 * 1e18));
    }

    receive() external payable {}
}
