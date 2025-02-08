// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, Vm } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { DeployBitkubScript } from "../../script/deploy/DeployBitkub.sol";
import { PonderToken } from "../../src/core/token/PonderToken.sol";
import { PonderFactory } from "../../src/core/factory/PonderFactory.sol";
import { PonderMasterChef } from "../../src/core/masterchef/PonderMasterChef.sol";
import { PonderRouter } from "../../src/periphery/router/PonderRouter.sol";
import { PonderPriceOracle } from "../../src/core/oracle/PonderPriceOracle.sol";
import { PonderStaking } from "../../src/core/staking/PonderStaking.sol";
import { FeeDistributor } from "../../src/core/distributor/FeeDistributor.sol";
import { KKUBUnwrapper } from "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import { FiveFiveFiveLauncher } from "../../src/launch/FiveFiveFiveLauncher.sol";

contract DeployBitkubTest is Test {
    DeployBitkubScript public deployer;
    address constant KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;

    event ContractDeployed(string indexed name, address indexed addr);
    event ConfigurationFinalized(address indexed factory, address indexed masterChef, address indexed feeDistributor);

    uint256 constant DEPLOYER_PRIVATE_KEY = 0xBEEF;
    address deployerAddress;

    function setUp() public {
        // Setup deployer
        deployerAddress = vm.addr(DEPLOYER_PRIVATE_KEY);
        vm.deal(deployerAddress, 100 ether);

        // Remove "0x" prefix for private key environment variable
        string memory pkString = vm.toString(DEPLOYER_PRIVATE_KEY);
        vm.setEnv("PRIVATE_KEY", pkString);
        vm.setEnv("TEAM_RESERVE_ADDRESS", "0xb9991047fAAFe64F56F981b0CC829494Add5bD54");
        vm.setEnv("MARKETING_ADDRESS", "0xC07B3f9471A4036b1B577483fC51aC04c6885730");

        // Mock KKUB
        vm.etch(KKUB, address(0xBEEF).code);

        deployer = new DeployBitkubScript();
    }

    function test_InvalidAddresses() public {
        vm.setEnv("TEAM_RESERVE_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.expectRevert("Invalid addresses");
        deployer.run();
    }

    function test_DeploymentAndConfiguration() public {
        vm.startPrank(deployerAddress);
        vm.recordLogs();

        deployer.run();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Track all contracts that should be deployed
        address[10] memory contracts;
        string[10] memory expectedNames = [
                    "PONDER",
                    "Factory",
                    "KKUBUnwrapper",
                    "Router",
                    "Oracle",
                    "Staking",
                    "FeeDistributor",
                    "Launcher",
                    "MasterChef",
                    "PONDER-KUB Pair"
            ];
        uint256 found = 0;

        // Process logs to find contract deployments
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("ContractDeployed(string,address)")) {
                string memory name = abi.decode(logs[i].data, (string));
                address addr = address(uint160(uint256(logs[i].topics[1])));

                for (uint j = 0; j < expectedNames.length; j++) {
                    if (keccak256(bytes(name)) == keccak256(bytes(expectedNames[j]))) {
                        contracts[j] = addr;
                        found++;
                        break;
                    }
                }
            }
        }

        assertEq(found, 10, "Not all contracts deployed");

        // Verify configurations
        PonderToken ponder = PonderToken(contracts[0]);
        PonderFactory factory = PonderFactory(contracts[1]);

        assertEq(ponder.minter(), contracts[8], "Wrong minter"); // MasterChef
        assertEq(ponder.launcher(), contracts[7], "Wrong launcher"); // Launcher
        assertEq(factory.ponder(), address(ponder), "Wrong factory token");
        assertEq(factory.feeTo(), contracts[6], "Wrong fee recipient"); // FeeDistributor

        vm.stopPrank();
    }

    function test_PairCreation() public {
        vm.startPrank(deployerAddress);
        vm.recordLogs();

        deployer.run();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        address ponderKubPair;

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("ContractDeployed(string,address)")) {
                string memory name = abi.decode(logs[i].data, (string));
                if (keccak256(bytes(name)) == keccak256(bytes("PONDER-KUB Pair"))) {
                    ponderKubPair = address(uint160(uint256(logs[i].topics[1])));
                    break;
                }
            }
        }

        assertTrue(ponderKubPair != address(0), "PONDER-KUB pair not created");
        assertTrue(ponderKubPair.code.length > 0, "PONDER-KUB pair has no code");

        vm.stopPrank();
    }

    function test_DeployerPrivileges() public {
        vm.expectRevert();
        vm.prank(address(0xDEAD));
        deployer.run();

        // Should work with deployer address
        vm.prank(deployerAddress);
        deployer.run();
    }

    function test_FeeConfiguration() public {
        vm.startPrank(deployerAddress);
        vm.recordLogs();

        deployer.run();

        bool foundConfigFinalized = false;
        for (uint i = 0; i < vm.getRecordedLogs().length; i++) {
            Vm.Log memory log = vm.getRecordedLogs()[i];
            if (log.topics[0] == keccak256("ConfigurationFinalized(address,address,address)")) {
                foundConfigFinalized = true;
                break;
            }
        }

        assertTrue(foundConfigFinalized, "Configuration finalization event not emitted");
        vm.stopPrank();
    }

    function testGas_Deployment() public {
        vm.prank(deployerAddress);
        deployer.run();
    }
}
