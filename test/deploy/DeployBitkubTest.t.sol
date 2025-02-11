//// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
//
//import { Test, Vm } from "forge-std/Test.sol";
//import { console } from "forge-std/console.sol";
//import { DeployBitkubScript } from "../../script/deploy/DeployBitkub.sol";
//import { PonderToken } from "../../src/core/token/PonderToken.sol";
//import { PonderFactory } from "../../src/core/factory/PonderFactory.sol";
//import { PonderStaking } from "../../src/core/staking/PonderStaking.sol";
//import { FeeDistributor } from "../../src/core/distributor/FeeDistributor.sol";
//import { KKUBUnwrapper } from "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
//import { IPonderRouter } from "../../src/periphery/router/IPonderRouter.sol";
//
//contract DeployBitkubTest is Test {
//    address constant KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
//    address constant VALID_TEAM = 0xb9991047fAAFe64F56F981b0CC829494Add5bD54;
//    uint256 constant VALID_PRIVATE_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
//
//    DeployBitkubScript deployer;
//    address deployerAddress;
//
//    event ContractDeployed(string indexed name, address indexed addr);
//    event ConfigurationFinalized(address indexed factory, address indexed masterChef, address indexed feeDistributor);
//    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
//
//    function setUp() public {
//        deployerAddress = vm.addr(VALID_PRIVATE_KEY);
//        vm.deal(deployerAddress, 100 ether);
//
//        // Mock KKUB contract
//        vm.etch(KKUB, address(0xBEEF).code);
//
//        // Create deployer
//        deployer = new DeployBitkubScript();
//
//        // Set up valid environment variables
//        vm.setEnv("PRIVATE_KEY", "0x1234567890123456789012345678901234567890123456789012345678901234");
//        vm.setEnv("TEAM_RESERVE_ADDRESS", vm.toString(VALID_TEAM));
//    }
//
//    function test_Initialization() public {
//        // Test invalid initialization cases
//        vm.expectRevert("Invalid deployer address");
//        deployer.initialize(address(0), VALID_TEAM);
//
//        vm.expectRevert("Invalid team reserve address");
//        deployer.initialize(deployerAddress, address(0));
//
//        // Test successful initialization
//        deployer.initialize(deployerAddress, VALID_TEAM);
//
//        // Test double initialization
//        vm.expectRevert("Already initialized");
//        deployer.initialize(deployerAddress, VALID_TEAM);
//    }
//
//    function test_EnvironmentVariables() public {
//        // Test missing PRIVATE_KEY
//        vm.setEnv("PRIVATE_KEY", "");
//        vm.expectRevert("PRIVATE_KEY environment variable not set");
//        deployer.run();
//
//        // Test invalid PRIVATE_KEY format
//        vm.setEnv("PRIVATE_KEY", "invalid");
//        vm.expectRevert();
//        deployer.run();
//
//        // Test missing TEAM_RESERVE_ADDRESS
//        vm.setEnv("PRIVATE_KEY", "0x1234567890123456789012345678901234567890123456789012345678901234");
//        vm.setEnv("TEAM_RESERVE_ADDRESS", "");
//        vm.expectRevert("TEAM_RESERVE_ADDRESS environment variable not set");
//        deployer.run();
//
//        // Reset environment for other tests
//        vm.setEnv("TEAM_RESERVE_ADDRESS", vm.toString(VALID_TEAM));
//    }
//
//    function test_FullDeployment() public {
//        vm.recordLogs();
//
//        // Execute deployment script
//        deployer.run();
//
//        Vm.Log[] memory logs = vm.getRecordedLogs();
//        address ponderAddr;
//        address factoryAddr;
//        address routerAddr;
//        address stakingAddr;
//        address pairAddr;
//
//        for (uint i = 0; i < logs.length; i++) {
//            if (logs[i].topics[0] == keccak256("ContractDeployed(string,address)")) {
//                (string memory name) = abi.decode(logs[i].data, (string));
//                address addr = address(uint160(uint256(logs[i].topics[1])));
//
//                if (keccak256(bytes(name)) == keccak256(bytes("PONDER"))) {
//                    ponderAddr = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("Factory"))) {
//                    factoryAddr = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("Router"))) {
//                    routerAddr = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("Staking"))) {
//                    stakingAddr = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("PONDER-KUB Pair"))) {
//                    pairAddr = addr;
//                }
//            }
//        }
//
//        // Verify core contracts were deployed
//        assertTrue(ponderAddr != address(0), "PONDER not deployed");
//        assertTrue(factoryAddr != address(0), "Factory not deployed");
//        assertTrue(routerAddr != address(0), "Router not deployed");
//        assertTrue(stakingAddr != address(0), "Staking not deployed");
//        assertTrue(pairAddr != address(0), "PONDER-KUB pair not created");
//
//        // Verify contract configurations
//        PonderToken ponder = PonderToken(ponderAddr);
//        PonderFactory factory = PonderFactory(factoryAddr);
//        PonderStaking staking = PonderStaking(stakingAddr);
//
//        assertEq(factory.ponder(), ponderAddr, "Wrong factory token");
//        assertEq(ponder.staking(), stakingAddr, "Wrong staking address");
//        assertTrue(ponder.launcher() != address(0), "Launcher not set");
//        assertTrue(factory.feeTo() != address(0), "FeeDistributor not set");
//    }
//
//    function test_LiquidityAddition() public {
//        vm.recordLogs();
//        deployer.run();
//
//        Vm.Log[] memory logs = vm.getRecordedLogs();
//        bool foundLiquidityEvent = false;
//
//        for (uint i = 0; i < logs.length; i++) {
//            if (logs[i].topics[0] == keccak256("LiquidityAdded(uint256,uint256)")) {
//                foundLiquidityEvent = true;
//                (uint256 kubAmount, uint256 ponderAmount) = abi.decode(logs[i].data, (uint256, uint256));
//                assertTrue(kubAmount > 0, "No KUB added to liquidity");
//                assertTrue(ponderAmount > 0, "No PONDER added to liquidity");
//                break;
//            }
//        }
//
//        assertTrue(foundLiquidityEvent, "Liquidity addition event not found");
//    }
//
//    function test_ConfigurationFinalization() public {
//        vm.recordLogs();
//        deployer.run();
//
//        bool foundConfigEvent = false;
//        address feeDistributor;
//        address masterChef;
//
//        Vm.Log[] memory logs = vm.getRecordedLogs();
//        for (uint i = 0; i < logs.length; i++) {
//            if (logs[i].topics[0] == keccak256("ConfigurationFinalized(address,address,address)")) {
//                foundConfigEvent = true;
//                feeDistributor = address(uint160(uint256(logs[i].topics[2])));
//                masterChef = address(uint160(uint256(logs[i].topics[1])));
//                break;
//            }
//        }
//
//        assertTrue(foundConfigEvent, "Configuration finalization event not found");
//        assertTrue(feeDistributor != address(0), "FeeDistributor not set");
//        assertTrue(masterChef != address(0), "MasterChef not set");
//    }
//
//    function test_ContractInteractions() public {
//        vm.recordLogs();
//        deployer.run();
//
//        address[] memory deployedAddresses = new address[](4);
//        Vm.Log[] memory logs = vm.getRecordedLogs();
//
//        for (uint i = 0; i < logs.length; i++) {
//            if (logs[i].topics[0] == keccak256("ContractDeployed(string,address)")) {
//                (string memory name) = abi.decode(logs[i].data, (string));
//                address addr = address(uint160(uint256(logs[i].topics[1])));
//
//                if (keccak256(bytes(name)) == keccak256(bytes("PONDER"))) {
//                    deployedAddresses[0] = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("Factory"))) {
//                    deployedAddresses[1] = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("Router"))) {
//                    deployedAddresses[2] = addr;
//                } else if (keccak256(bytes(name)) == keccak256(bytes("PONDER-KUB Pair"))) {
//                    deployedAddresses[3] = addr;
//                }
//            }
//        }
//
//        // Test basic contract interactions
//        PonderToken ponder = PonderToken(deployedAddresses[0]);
//        PonderFactory factory = PonderFactory(deployedAddresses[1]);
//        IPonderRouter router = IPonderRouter(payable(deployedAddresses[2]));
//
//        // Verify expected state
//        assertEq(ponder.allowance(deployerAddress, address(router)), 0);
//        assertTrue(factory.feeToSetter() == deployerAddress);
//        assertTrue(factory.getPair(address(ponder), KKUB) == deployedAddresses[3]);
//    }
//
//    function testGas_Deployment() public {
//        deployer.run();
//    }
//}
