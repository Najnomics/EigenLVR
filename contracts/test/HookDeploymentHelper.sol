// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title Hook Deployment Helper for Tests
 * @notice Utility for deploying EigenLVRHook with correct address mining in tests
 */
library HookDeploymentHelper {
    // Required flags for EigenLVRHook
    uint160 public constant REQUIRED_FLAGS = 
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |      // 1 << 11 = 2048
        Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |   // 1 << 9 = 512
        Hooks.BEFORE_SWAP_FLAG |               // 1 << 7 = 128
        Hooks.AFTER_SWAP_FLAG;                 // 1 << 6 = 64

    /**
     * @notice Deploy EigenLVRHook with properly mined address
     * @param deployer The address that will deploy the hook
     * @param poolManager The pool manager address
     * @param avsDirectory The AVS directory address
     * @param priceOracle The price oracle address
     * @param feeRecipient The fee recipient address
     * @param lvrThreshold The LVR threshold
     * @return hook The deployed hook contract
     * @return hookAddress The deployed hook address
     */
    function deployHookWithMining(
        address deployer,
        IPoolManager poolManager,
        IAVSDirectory avsDirectory,
        IPriceOracle priceOracle,
        address feeRecipient,
        uint256 lvrThreshold
    ) internal returns (EigenLVRHook hook, address hookAddress) {
        // Get contract creation code
        bytes memory creationCode = type(EigenLVRHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            avsDirectory,
            priceOracle,
            feeRecipient,
            lvrThreshold
        );
        
        // Mine the correct address
        bytes32 salt;
        (hookAddress, salt) = HookMiner.find(
            deployer,
            REQUIRED_FLAGS,
            creationCode,
            constructorArgs
        );
        
        // Deploy using CREATE2 with the mined salt
        hook = new EigenLVRHook{salt: salt}(
            poolManager,
            avsDirectory,
            priceOracle,
            feeRecipient,
            lvrThreshold
        );
        
        // Verify deployment
        require(address(hook) == hookAddress, "Hook deployment address mismatch");
        require(uint160(address(hook)) & REQUIRED_FLAGS == REQUIRED_FLAGS, "Hook address does not have required flags");
        
        return (hook, hookAddress);
    }
    
    /**
     * @notice Get a pre-mined hook address for testing (without deployment)
     * @param deployer The deployer address
     * @param poolManager The pool manager address
     * @param avsDirectory The AVS directory address
     * @param priceOracle The price oracle address
     * @param feeRecipient The fee recipient address
     * @param lvrThreshold The LVR threshold
     * @return hookAddress The mined hook address
     * @return salt The salt used for mining
     */
    function getMinedHookAddress(
        address deployer,
        IPoolManager poolManager,
        IAVSDirectory avsDirectory,
        IPriceOracle priceOracle,
        address feeRecipient,
        uint256 lvrThreshold
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory creationCode = type(EigenLVRHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            avsDirectory,
            priceOracle,
            feeRecipient,
            lvrThreshold
        );
        
        return HookMiner.find(deployer, REQUIRED_FLAGS, creationCode, constructorArgs);
    }
    
    /**
     * @notice Verify that an address has the required hook flags
     * @param hookAddress The address to verify
     * @return isValid Whether the address has the required flags
     */
    function verifyHookAddress(address hookAddress) internal pure returns (bool isValid) {
        return uint160(hookAddress) & REQUIRED_FLAGS == REQUIRED_FLAGS;
    }
}