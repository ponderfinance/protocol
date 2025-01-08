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
    uint256 constant PONDER_PER_SECOND = 3168000000000000000; // 3.168 ether
    uint256 constant INITIAL_KUB_AMOUNT = 1000 ether;
    uint256 constant LIQUIDITY_ALLOCATION = 200_000_000 ether;

    address constant USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
    address constant KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;

    error InvalidAddress();
    error PairCreationFailed();
    error DeploymentFailed(string name);
    error LiquidityAddFailed();

    struct DeploymentState {
        address deployer;
        address teamReserve;
        address marketing;
        PonderToken ponder;
        PonderFactory factory;
        KKUBUnwrapper kkubUnwrapper;
        PonderRouter router;
        PonderPriceOracle oracle;
        address ponderKubPair;
        PonderMasterChef masterChef;
        FiveFiveFiveLauncher launcher;
        PonderStaking staking;
        FeeDistributor feeDistributor;
    }

    function validateAddresses(
        address teamReserve,
        address marketing,
        address deployer
    ) internal pure {
        if (
        teamReserve == address(0) ||
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

        vm.startBroadcast(deployerPrivateKey);

        DeploymentState memory state = deployCore(deployer, teamReserve, marketing);
        setupInitialPrices(state);
        finalizeConfiguration(state);

        vm.stopBroadcast();

        logDeployment(state);
    }

    function deployCore(
        address deployer,
        address teamReserve,
        address marketing
    ) internal returns (DeploymentState memory state) {
        state.deployer = deployer;
        state.teamReserve = teamReserve;
        state.marketing = marketing;

        // Deploy factory and periphery
        state.factory = new PonderFactory(deployer, address(0), address(0));
        _verifyContract("PonderFactory", address(state.factory));

        state.kkubUnwrapper = new KKUBUnwrapper(KKUB);
        _verifyContract("KKUBUnwrapper", address(state.kkubUnwrapper));

        state.router = new PonderRouter(
            address(state.factory),
            KKUB,
            address(state.kkubUnwrapper)
        );
        _verifyContract("PonderRouter", address(state.router));

        // Deploy PONDER - initial liquidity will be minted to msg.sender (deployer)
        state.ponder = new PonderToken(teamReserve, marketing, address(0));
        _verifyContract("PonderToken", address(state.ponder));

        // Create pair
        state.factory.createPair(address(state.ponder), KKUB);
        state.ponderKubPair = state.factory.getPair(address(state.ponder), KKUB);
        if (state.ponderKubPair == address(0)) revert PairCreationFailed();

        // Deploy remaining contracts
        state.oracle = new PonderPriceOracle(address(state.factory), KKUB, USDT);
        _verifyContract("PonderPriceOracle", address(state.oracle));

        state.staking = new PonderStaking(
            address(state.ponder),
            address(state.router),
            address(state.factory)
        );
        _verifyContract("PonderStaking", address(state.staking));

        state.feeDistributor = new FeeDistributor(
            address(state.factory),
            address(state.router),
            address(state.ponder),
            address(state.staking),
            teamReserve
        );
        _verifyContract("FeeDistributor", address(state.feeDistributor));

        state.launcher = new FiveFiveFiveLauncher(
            address(state.factory),
            payable(address(state.router)),
            teamReserve,
            address(state.ponder),
            address(state.oracle)
        );
        _verifyContract("Launcher", address(state.launcher));

        state.masterChef = new PonderMasterChef(
            state.ponder,
            state.factory,
            teamReserve,
            PONDER_PER_SECOND
        );
        _verifyContract("MasterChef", address(state.masterChef));

        return state;
    }

    function setupInitialPrices(DeploymentState memory state) internal {
        // Tokens are already minted to deployer, just need to approve router
        state.ponder.approve(address(state.router), LIQUIDITY_ALLOCATION);

        // Approve the router to spend PONDER
        state.ponder.approve(address(state.router), LIQUIDITY_ALLOCATION);

        // Add liquidity
        state.router.addLiquidityETH{value: INITIAL_KUB_AMOUNT}(
            address(state.ponder),
            LIQUIDITY_ALLOCATION,
            LIQUIDITY_ALLOCATION,
            INITIAL_KUB_AMOUNT,
            state.deployer,
            block.timestamp + 1 hours
        );

        console.log("Initial liquidity added successfully");
    }

    function finalizeConfiguration(DeploymentState memory state) internal {
        state.ponder.setMinter(address(state.masterChef));
        state.ponder.setLauncher(address(state.launcher));
        state.factory.setLauncher(address(state.launcher));
        state.factory.setPonder(address(state.ponder));
        state.factory.setFeeTo(address(state.feeDistributor));
    }

    function _verifyContract(string memory name, address contractAddress) internal view {
        uint256 size;
        assembly {
            size := extcodesize(contractAddress)
        }
        if (size == 0) revert DeploymentFailed(name);
        console.log(name, "deployed at:", contractAddress);
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

        console.log("\nProtocol Fee Configuration:");
        console.log("--------------------------------");
        console.log("Protocol fees enabled: Yes");
        console.log("Fee collector: FeeDistributor");
        console.log("Distribution: 80% xPONDER, 20% Team");

        console.log("\nInitial Liquidity Details:");
        console.log("--------------------------------");
        console.log("Initial KUB:", INITIAL_KUB_AMOUNT / 1e18);
        console.log("Initial PONDER:", LIQUIDITY_ALLOCATION / 1e18);
        console.log("Initial PONDER/KUB Rate:", LIQUIDITY_ALLOCATION / INITIAL_KUB_AMOUNT);

        console.log("\nToken Allocation Summary:");
        console.log("--------------------------------");
        console.log("Liquidity Mining (40%):", uint256(400_000_000 * 1e18));
        console.log("Team/Reserve (25%):", uint256(250_000_000 * 1e18));
        console.log("Marketing/Community (15%):", uint256(150_000_000 * 1e18));
    }

    receive() external payable {}
}
