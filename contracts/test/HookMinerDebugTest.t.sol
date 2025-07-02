// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract HookMinerDebugTest is Test {
    function test_DebugFlags() public {
        uint160 BEFORE_ADD_LIQUIDITY_FLAG = Hooks.BEFORE_ADD_LIQUIDITY_FLAG;
        uint160 BEFORE_REMOVE_LIQUIDITY_FLAG = Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;
        uint160 BEFORE_SWAP_FLAG = Hooks.BEFORE_SWAP_FLAG;
        uint160 AFTER_SWAP_FLAG = Hooks.AFTER_SWAP_FLAG;
        
        console.log("BEFORE_ADD_LIQUIDITY_FLAG:", BEFORE_ADD_LIQUIDITY_FLAG);
        console.log("BEFORE_REMOVE_LIQUIDITY_FLAG:", BEFORE_REMOVE_LIQUIDITY_FLAG);
        console.log("BEFORE_SWAP_FLAG:", BEFORE_SWAP_FLAG);
        console.log("AFTER_SWAP_FLAG:", AFTER_SWAP_FLAG);
        
        uint160 REQUIRED_FLAGS = BEFORE_ADD_LIQUIDITY_FLAG | BEFORE_REMOVE_LIQUIDITY_FLAG | BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG;
        console.log("REQUIRED_FLAGS:", REQUIRED_FLAGS);
        
        // Test with simple bytecode
        bytes memory creationCode = hex"608060405234801561001057600080fd5b50";
        bytes memory constructorArgs = hex"";
        
        address deployer = address(0x1234567890123456789012345678901234567890);
        
        console.log("Starting mining...");
        
        // Try with just BEFORE_SWAP_FLAG first
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            BEFORE_SWAP_FLAG,
            creationCode,
            constructorArgs
        );
        
        console.log("Found address for BEFORE_SWAP_FLAG:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        console.log("Address has flag:", uint160(hookAddress) & BEFORE_SWAP_FLAG == BEFORE_SWAP_FLAG);
    }
}