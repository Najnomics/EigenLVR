// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title Deploy EigenLVRHook with Correct Address Mining
 * @notice This script mines the correct hook address and deploys the contract
 */
contract DeployHookWithMining is Script {
    // Required flags for EigenLVRHook
    uint160 public constant REQUIRED_FLAGS = 
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |      // 1 << 11 = 2048
        Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |   // 1 << 9 = 512
        Hooks.BEFORE_SWAP_FLAG |               // 1 << 7 = 128
        Hooks.AFTER_SWAP_FLAG;                 // 1 << 6 = 64
        // Total = 2752
    
    function run() external {
        vm.startBroadcast();
        
        address deployer = msg.sender;
        console.log("Deployer address:", deployer);
        console.log("Required flags:", REQUIRED_FLAGS);
        
        // Mock addresses for testing (replace with real addresses for mainnet)
        address poolManager = address(0x1111111111111111111111111111111111111111);
        address avsDirectory = address(0x2222222222222222222222222222222222222222);
        address priceOracle = address(0x3333333333333333333333333333333333333333);
        address feeRecipient = address(0x4444444444444444444444444444444444444444);
        uint256 lvrThreshold = 50; // 0.5%
        
        // Get contract creation code
        bytes memory creationCode = type(EigenLVRHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            IPoolManager(poolManager),
            IAVSDirectory(avsDirectory),
            IPriceOracle(priceOracle),
            feeRecipient,
            lvrThreshold
        );
        
        console.log("Mining hook address with required flags...");
        
        // Mine the correct address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            REQUIRED_FLAGS,
            creationCode,
            constructorArgs
        );
        
        console.log("Found valid hook address:", hookAddress);
        console.log("Salt used:", vm.toString(salt));
        
        // Verify the address has correct flags
        require(uint160(hookAddress) & REQUIRED_FLAGS == REQUIRED_FLAGS, "Invalid hook address mined");
        
        // Deploy using CREATE2 with the mined salt
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(poolManager),
            IAVSDirectory(avsDirectory),
            IPriceOracle(priceOracle),
            feeRecipient,
            lvrThreshold
        );
        
        console.log("Hook deployed at:", address(hook));
        console.log("Deployment successful!");
        
        // Verify permissions match
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        console.log("Hook permissions:");
        console.log("- beforeAddLiquidity:", permissions.beforeAddLiquidity);
        console.log("- beforeRemoveLiquidity:", permissions.beforeRemoveLiquidity);
        console.log("- beforeSwap:", permissions.beforeSwap);
        console.log("- afterSwap:", permissions.afterSwap);
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Get the mined hook address for testing (without deployment)
     */
    function getMinerResult() external pure returns (address hookAddress, bytes32 salt) {
        address deployer = address(0x1234567890123456789012345678901234567890); // Test deployer
        
        // Mock constructor args for testing
        bytes memory creationCode = type(EigenLVRHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(0x1111111111111111111111111111111111111111)),
            IAVSDirectory(address(0x2222222222222222222222222222222222222222)),
            IPriceOracle(address(0x3333333333333333333333333333333333333333)),
            address(0x4444444444444444444444444444444444444444),
            uint256(50)
        );
        
        return HookMiner.find(deployer, REQUIRED_FLAGS, creationCode, constructorArgs);
    }
}