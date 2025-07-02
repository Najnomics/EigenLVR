// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title HookMinerFixed
 * @notice Fixed utility for mining valid hook addresses for Uniswap v4
 */
library HookMinerFixed {
    /**
     * @notice Find a valid hook address with required permissions
     * @param deployer The address that will deploy the hook
     * @param flags The required permission flags
     * @param creationCode The contract creation bytecode
     * @param constructorArgs The constructor arguments
     * @return hookAddress The valid hook address
     * @return salt The salt used to generate the address
     */
    function find(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        
        // If no flags required, return immediately
        if (flags == 0) {
            salt = bytes32(0);
            hookAddress = computeAddress(deployer, salt, bytecode);
            return (hookAddress, salt);
        }
        
        // For non-zero flags, try different salts
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, bytecode);
            
            // Check if this address has the required flags
            if ((uint160(hookAddress) & flags) == flags) {
                return (hookAddress, salt);
            }
        }
        
        // If we can't find a valid address within reasonable iterations,
        // try with a more systematic approach
        for (uint256 i = 0; i < 1000000; i++) {
            salt = keccak256(abi.encodePacked(deployer, flags, i));
            hookAddress = computeAddress(deployer, salt, bytecode);
            
            if ((uint160(hookAddress) & flags) == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMinerFixed: Could not find valid address");
    }
    
    /**
     * @notice Compute CREATE2 address
     * @param deployer The deployer address
     * @param salt The salt value
     * @param bytecode The contract bytecode
     * @return The computed address
     */
    function computeAddress(
        address deployer,
        bytes32 salt,
        bytes memory bytecode
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                keccak256(bytecode)
            )
        );
        return address(uint160(uint256(hash)));
    }
    
    /**
     * @notice Check if an address has the required flags
     * @param addr The address to check
     * @param flags The required flags
     * @return Whether the address has all required flags
     */
    function hasValidFlags(address addr, uint160 flags) internal pure returns (bool) {
        return (uint160(addr) & flags) == flags;
    }
    
    /**
     * @notice Mine hook address with specific flag requirements
     * @param deployer The deployer address
     * @param beforeSwap Whether BEFORE_SWAP flag is needed
     * @param afterSwap Whether AFTER_SWAP flag is needed
     * @param beforeAddLiquidity Whether BEFORE_ADD_LIQUIDITY flag is needed
     * @param beforeRemoveLiquidity Whether BEFORE_REMOVE_LIQUIDITY flag is needed
     * @param creationCode The contract creation bytecode
     * @param constructorArgs The constructor arguments
     * @return hookAddress The valid hook address
     * @return salt The salt used
     */
    function mineAddress(
        address deployer,
        bool beforeSwap,
        bool afterSwap,
        bool beforeAddLiquidity,
        bool beforeRemoveLiquidity,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        uint160 flags = 0;
        
        if (beforeSwap) {
            flags |= Hooks.BEFORE_SWAP_FLAG;
        }
        if (afterSwap) {
            flags |= Hooks.AFTER_SWAP_FLAG;
        }
        if (beforeAddLiquidity) {
            flags |= Hooks.BEFORE_ADD_LIQUIDITY_FLAG;
        }
        if (beforeRemoveLiquidity) {
            flags |= Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;
        }
        
        return find(deployer, flags, creationCode, constructorArgs);
    }
}