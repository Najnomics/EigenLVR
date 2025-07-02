// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title HookMiner
 * @notice Utility for mining valid hook addresses for Uniswap v4
 */
library HookMiner {
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
        
        // If no flags are required, return the first valid address
        if (flags == 0) {
            salt = bytes32(0);
            hookAddress = computeAddress(deployer, salt, bytecode);
            return (hookAddress, salt);
        }
        
        // Increase iteration limit for flag mining
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = computeAddress(deployer, salt, bytecode);
            
            if (uint160(hookAddress) & flags == flags) {
                return (hookAddress, salt);
            }
        }
        
        revert("HookMiner: Could not find valid address");
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
}