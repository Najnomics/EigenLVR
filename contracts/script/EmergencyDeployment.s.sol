// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BaseDeployment.s.sol";

/**
 * @title EmergencyDeployment
 * @notice Emergency deployment script for critical updates
 * @dev Use this for urgent fixes and security updates
 */
contract EmergencyDeployment is BaseDeployment {
    
    /*//////////////////////////////////////////////////////////////
                           EMERGENCY SETTINGS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emergency pause flag
    bool public emergencyPause = true;
    
    /// @notice Emergency LVR threshold (higher for safety)
    uint256 public emergencyLvrThreshold = 200; // 2%
    
    /// @notice Emergency deployer
    address public emergencyDeployer;
    
    /*//////////////////////////////////////////////////////////////
                               DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("EMERGENCY_PRIVATE_KEY");
        emergencyDeployer = vm.addr(deployerPrivateKey);
        address feeRecipient = vm.envOr("EMERGENCY_FEE_RECIPIENT", emergencyDeployer);
        
        require(isNetworkSupported(), "Network not supported");
        
        console.log("=== EMERGENCY DEPLOYMENT ===");
        console.log("Emergency deployer:", emergencyDeployer);
        console.log("Emergency pause enabled:", emergencyPause);
        console.log("Emergency LVR threshold:", emergencyLvrThreshold);
        
        vm.startBroadcast(deployerPrivateKey);
        
        DeploymentResult memory result = deployAllContracts(emergencyDeployer, feeRecipient);
        
        // Apply emergency configuration
        _applyEmergencyConfiguration(result);
        
        vm.stopBroadcast();
        
        logDeploymentSummary(result);
        _logEmergencyWarnings();
        saveDeploymentResults(result);
        
        return result;
    }
    
    /**
     * @notice Apply emergency configuration
     */
    function _applyEmergencyConfiguration(DeploymentResult memory result) internal {
        console.log("\n=== Applying Emergency Configuration ===");
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Set emergency LVR threshold
        hook.setLVRThreshold(emergencyLvrThreshold);
        console.log("Set emergency LVR threshold:", emergencyLvrThreshold);
        
        // Pause if required
        if (emergencyPause) {
            hook.pause();
            console.log("Emergency pause activated");
        }
        
        // Authorize only emergency deployer initially
        hook.setOperatorAuthorization(emergencyDeployer, true);
        console.log("Authorized emergency deployer as operator");
        
        // Set emergency fee recipient
        hook.setFeeRecipient(emergencyDeployer);
        console.log("Set emergency fee recipient");
        
        console.log("Emergency configuration applied");
    }
    
    /**
     * @notice Deploy hook with emergency salt
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        // Use emergency salt pattern
        bytes32 salt = keccak256(abi.encodePacked(
            "EigenLVR-EMERGENCY",
            block.chainid,
            block.timestamp
        ));
        
        console.log("Deploying emergency hook with salt:", vm.toString(salt));
        
        // Override config for emergency deployment
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            feeRecipient,
            emergencyLvrThreshold // Use emergency threshold
        );
        
        return hook;
    }
    
    /**
     * @notice Log emergency warnings
     */
    function _logEmergencyWarnings() internal view {
        console.log("\n=== EMERGENCY DEPLOYMENT WARNINGS ===");
        console.log("*** THIS IS AN EMERGENCY DEPLOYMENT ***");
        console.log("");
        console.log("Emergency settings applied:");
        console.log("- Higher LVR threshold (2%) for safety");
        console.log("- System paused by default");
        console.log("- Only emergency deployer authorized");
        console.log("- Emergency fee recipient set");
        console.log("");
        console.log("REQUIRED ACTIONS:");
        console.log("1. Verify deployment security");
        console.log("2. Test all critical functions");
        console.log("3. Gradually restore normal operations");
        console.log("4. Update monitoring and alerts");
        console.log("5. Communicate with users about changes");
        console.log("");
        console.log("TO RESTORE NORMAL OPERATIONS:");
        console.log("1. Unpause the contract: hook.unpause()");
        console.log("2. Set normal LVR threshold: hook.setLVRThreshold(50)");
        console.log("3. Authorize normal operators");
        console.log("4. Update fee recipient if needed");
        console.log("");
        console.log("MONITORING:");
        console.log("- Watch for unusual activity");
        console.log("- Monitor gas costs and performance");
        console.log("- Check operator responses");
        console.log("- Verify auction mechanisms");
        console.log("=====================================");
    }
    
    /**
     * @notice Emergency unpause function
     */
    function emergencyUnpause() external {
        require(msg.sender == emergencyDeployer, "Only emergency deployer");
        
        EigenLVRHook hook = EigenLVRHook(payable(deploymentResult.hook));
        hook.unpause();
        
        console.log("Emergency unpause executed by:", msg.sender);
    }
    
    /**
     * @notice Emergency re-pause function
     */
    function emergencyRePause() external {
        require(msg.sender == emergencyDeployer, "Only emergency deployer");
        
        EigenLVRHook hook = EigenLVRHook(payable(deploymentResult.hook));
        hook.pause();
        
        console.log("Emergency re-pause executed by:", msg.sender);
    }
    
    /**
     * @notice Restore normal threshold
     */
    function restoreNormalThreshold() external {
        require(msg.sender == emergencyDeployer, "Only emergency deployer");
        
        EigenLVRHook hook = EigenLVRHook(payable(deploymentResult.hook));
        hook.setLVRThreshold(50); // Normal 0.5%
        
        console.log("Normal LVR threshold restored by:", msg.sender);
    }
}