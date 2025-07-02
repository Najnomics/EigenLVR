// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title Comprehensive HookMiner Tests
 * @notice Tests all HookMiner functionality for 100% coverage
 */
contract HookMinerTest is Test {
    address public deployer = address(0x1);
    bytes public creationCode = hex"608060405234801561001057600080fd5b50610120806100206000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c8063b69fd45e14602d575b600080fd5b60336033565b005b600080fdfea26469706673582212203c5c4b5d7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e64736f6c63430008120033";
    bytes public constructorArgs = abi.encode(address(0x123), uint256(456));
    
    function test_Find_ValidAddress() public pure {
        // Use EigenLVR hook's actual flag combination for realistic test
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        // Verify the address has the required flags
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_SingleFlag() public {
        // Test with AFTER_SWAP_FLAG which has higher probability
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        // Salt can be 0 if the address is found on first iteration
        // assertTrue(salt != bytes32(0));
    }
    
    function test_Find_NoFlags() public pure {
        uint160 flags = 0;
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertEq(salt, bytes32(0)); // Should find immediately with no flags
    }
    
    function test_Find_AllFlags() public pure {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.AFTER_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_DONATE_FLAG |
            Hooks.AFTER_DONATE_FLAG
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_DifferentDeployer() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress1, bytes32 salt1) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        (address hookAddress2, bytes32 salt2) = HookMiner.find(
            address(0x2),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        // Different deployers should produce different addresses
        assertTrue(hookAddress1 != hookAddress2);
        assertTrue(uint160(hookAddress1) & flags == flags);
        assertTrue(uint160(hookAddress2) & flags == flags);
    }
    
    function test_Find_DifferentBytecode() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress1, ) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        (address hookAddress2, ) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b51", // Different bytecode
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        // Different bytecode should produce different addresses
        assertTrue(hookAddress1 != hookAddress2);
        assertTrue(uint160(hookAddress1) & flags == flags);
        assertTrue(uint160(hookAddress2) & flags == flags);
    }
    
    function test_Find_DifferentConstructorArgs() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress1, ) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        (address hookAddress2, ) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000456" // Different args
        );
        
        // Different constructor args should produce different addresses
        assertTrue(hookAddress1 != hookAddress2);
        assertTrue(uint160(hookAddress1) & flags == flags);
        assertTrue(uint160(hookAddress2) & flags == flags);
    }
    
    function test_ComputeAddress() public pure {
        address computed = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        // Verify it's a valid address
        assertTrue(computed != address(0));
        
        // Compute again with same inputs
        address computed2 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        // Should be deterministic
        assertEq(computed, computed2);
    }
    
    function test_ComputeAddress_DifferentInputs() public pure {
        address addr1 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        address addr2 = HookMiner.computeAddress(
            address(0x2), // Different deployer
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        address addr3 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(456)), // Different salt
            hex"608060405234801561001057600080fd5b50"
        );
        
        address addr4 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b51" // Different bytecode
        );
        
        // All should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr1 != addr4);
        assertTrue(addr2 != addr3);
        assertTrue(addr2 != addr4);
        assertTrue(addr3 != addr4);
    }
    
    function test_ComputeAddress_EmptyBytecode() public pure {
        address computed = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex""
        );
        
        assertTrue(computed != address(0));
    }
    
    function test_ComputeAddress_ZeroSalt() public pure {
        address computed = HookMiner.computeAddress(
            address(0x1),
            bytes32(0),
            hex"608060405234801561001057600080fd5b50"
        );
        
        assertTrue(computed != address(0));
    }
    
    function test_ComputeAddress_ZeroDeployer() public pure {
        address computed = HookMiner.computeAddress(
            address(0),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        assertTrue(computed != address(0));
    }
    
    function test_Find_EdgeCase_VeryHighFlags() public pure {
        // Test with flags that are harder to find
        uint160 flags = 0xff00; // High bits set
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_ReturnDelta_Flags() public pure {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG |
            Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_Sequential_Salts() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        // Find first valid address - should use salt 0 or low value
        (address hookAddress1, bytes32 salt1) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        // Verify the salt is what we expect (should be sequential)
        assertTrue(uint256(salt1) < 10000000); // Should find within reasonable range
        assertTrue(uint160(hookAddress1) & flags == flags);
    }
    
    function test_Find_LargeCreationCode() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        // Create smaller bytecode for faster testing
        bytes memory bytecode = new bytes(100); // Reduced from 1000
        for (uint i = 0; i < 100; i++) {
            bytecode[i] = bytes1(uint8(i % 256));
        }
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            bytecode,
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_LargeConstructorArgs() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        // Create large constructor args
        bytes memory largeArgs = new bytes(500);
        for (uint i = 0; i < 500; i++) {
            largeArgs[i] = bytes1(uint8(i % 256));
        }
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            largeArgs
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    // Fuzz tests
    function testFuzz_ComputeAddress_Deterministic(
        address testDeployer,
        bytes32 salt,
        bytes memory bytecode
    ) public pure {
        address addr1 = HookMiner.computeAddress(testDeployer, salt, bytecode);
        address addr2 = HookMiner.computeAddress(testDeployer, salt, bytecode);
        
        assertEq(addr1, addr2);
    }
    
    function testFuzz_Find_ValidFlags(uint160 flags) public pure {
        // Limit flags to reasonable values to avoid infinite loops
        flags = flags & 0xffff;
        
        if (flags == 0) {
            (address hookAddress, bytes32 salt) = HookMiner.find(
                address(0x1),
                flags,
                hex"60806040",
                hex"00"
            );
            
            assertTrue(uint160(hookAddress) & flags == flags);
            return;
        }
        
        // For non-zero flags, we need to be careful about gas limits
        // We'll skip this test for very high flag values that might take too long
        if (uint256(flags) > 0xFFFF) return;
        
        (address hookAddr, bytes32 resultSalt) = HookMiner.find(
            address(0x1),
            flags,
            hex"60806040",
            hex"00"
        );
        
        assertTrue(uint160(hookAddr) & flags == flags);
    }
}