// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {EigenLVRAVSServiceManager} from "../src/EigenLVRAVSServiceManager.sol";
import {ProductionPriceFeedConfig} from "../src/ProductionPriceFeedConfig.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

/**
 * @title DeploymentUtils
 * @notice Utility functions for deployment management and verification
 */
contract DeploymentUtils is Script {
    
    /*//////////////////////////////////////////////////////////////
                           VERIFICATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Verify a deployment by checking contract functionality
     */
    function verifyDeployment(
        address hook,
        address priceOracle,
        address serviceManager,
        address priceFeedConfig
    ) external view returns (bool success, string memory report) {
        // Check hook
        (bool hookOk, string memory hookReport) = this.verifyHook(hook);
        if (!hookOk) {
            return (false, string(abi.encodePacked("Hook: ", hookReport)));
        }
        
        // Check price oracle
        (bool oracleOk, string memory oracleReport) = this.verifyPriceOracle(priceOracle);
        if (!oracleOk) {
            return (false, string(abi.encodePacked("Oracle: ", oracleReport)));
        }
        
        // Check service manager
        (bool smOk, string memory smReport) = this.verifyServiceManager(serviceManager);
        if (!smOk) {
            return (false, string(abi.encodePacked("ServiceManager: ", smReport)));
        }
        
        // Check price feed config
        (bool pfcOk, string memory pfcReport) = this.verifyPriceFeedConfig(priceFeedConfig);
        if (!pfcOk) {
            return (false, string(abi.encodePacked("PriceFeedConfig: ", pfcReport)));
        }
        
        return (true, "All contracts verified successfully");
    }
    
    /**
     * @notice Verify hook contract
     */
    function verifyHook(address hookAddr) external view returns (bool success, string memory report) {
        if (hookAddr == address(0)) {
            return (false, "Hook address is zero");
        }
        
        try EigenLVRHook(payable(hookAddr)).avsDirectory() returns (IAVSDirectory avsDir) {
            if (address(avsDir) == address(0)) {
                return (false, "AVS directory not set");
            }
        } catch {
            return (false, "Not a valid EigenLVRHook contract");
        }
        
        try EigenLVRHook(payable(hookAddr)).priceOracle() returns (IPriceOracle oracle) {
            if (address(oracle) == address(0)) {
                return (false, "Price oracle not set");
            }
        } catch {
            return (false, "Price oracle check failed");
        }
        
        try EigenLVRHook(payable(hookAddr)).lvrThreshold() returns (uint256 threshold) {
            if (threshold == 0 || threshold > 1000) { // 0% to 10% range
                return (false, "Invalid LVR threshold");
            }
        } catch {
            return (false, "LVR threshold check failed");
        }
        
        return (true, "Hook verified");
    }
    
    /**
     * @notice Verify price oracle contract
     */
    function verifyPriceOracle(address oracleAddr) external view returns (bool success, string memory report) {
        if (oracleAddr == address(0)) {
            return (false, "Oracle address is zero");
        }
        
        // Try to call a function to verify it's the right contract
        try ChainlinkPriceOracle(oracleAddr).MAX_PRICE_STALENESS() returns (uint256) {
            // If this succeeds, it's likely our contract
            return (true, "Price oracle verified");
        } catch {
            return (false, "Not a valid ChainlinkPriceOracle contract");
        }
    }
    
    /**
     * @notice Verify service manager contract
     */
    function verifyServiceManager(address smAddr) external view returns (bool success, string memory report) {
        if (smAddr == address(0)) {
            return (false, "Service manager address is zero");
        }
        
        try EigenLVRAVSServiceManager(payable(smAddr)).avsDirectory() returns (IAVSDirectory avsDir) {
            if (address(avsDir) == address(0)) {
                return (false, "AVS directory not set in service manager");
            }
        } catch {
            return (false, "Not a valid EigenLVRAVSServiceManager contract");
        }
        
        try EigenLVRAVSServiceManager(payable(smAddr)).MINIMUM_STAKE() returns (uint256 stake) {
            if (stake == 0) {
                return (false, "Invalid minimum stake");
            }
        } catch {
            return (false, "Minimum stake check failed");
        }
        
        return (true, "Service manager verified");
    }
    
    /**
     * @notice Verify price feed config contract
     */
    function verifyPriceFeedConfig(address pfcAddr) external view returns (bool success, string memory report) {
        if (pfcAddr == address(0)) {
            return (false, "Price feed config address is zero");
        }
        
        try ProductionPriceFeedConfig(pfcAddr).priceOracle() returns (ChainlinkPriceOracle oracle) {
            if (address(oracle) == address(0)) {
                return (false, "Price oracle not set in config");
            }
        } catch {
            return (false, "Not a valid ProductionPriceFeedConfig contract");
        }
        
        return (true, "Price feed config verified");
    }
    
    /*//////////////////////////////////////////////////////////////
                           DIAGNOSTIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get deployment diagnostics
     */
    function getDiagnostics(
        address hook,
        address priceOracle,
        address serviceManager,
        address priceFeedConfig
    ) external view returns (string memory report) {
        string memory diagnostics = "=== EigenLVR Deployment Diagnostics ===\n\n";
        
        // Hook diagnostics
        diagnostics = string(abi.encodePacked(diagnostics, "Hook Contract (", vm.toString(hook), "):\n"));
        if (hook != address(0)) {
            try EigenLVRHook(payable(hook)).lvrThreshold() returns (uint256 threshold) {
                diagnostics = string(abi.encodePacked(diagnostics, "- LVR Threshold: ", vm.toString(threshold), " bps\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- LVR Threshold: ERROR\n"));
            }
            
            try EigenLVRHook(payable(hook)).paused() returns (bool paused) {
                diagnostics = string(abi.encodePacked(diagnostics, "- Paused: ", paused ? "Yes" : "No", "\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- Paused: ERROR\n"));
            }
            
            try EigenLVRHook(payable(hook)).feeRecipient() returns (address recipient) {
                diagnostics = string(abi.encodePacked(diagnostics, "- Fee Recipient: ", vm.toString(recipient), "\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- Fee Recipient: ERROR\n"));
            }
        }
        
        // Service Manager diagnostics
        diagnostics = string(abi.encodePacked(diagnostics, "\nService Manager (", vm.toString(serviceManager), "):\n"));
        if (serviceManager != address(0)) {
            try EigenLVRAVSServiceManager(payable(serviceManager)).latestTaskNum() returns (uint32 taskNum) {
                diagnostics = string(abi.encodePacked(diagnostics, "- Latest Task: ", vm.toString(taskNum), "\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- Latest Task: ERROR\n"));
            }
            
            try EigenLVRAVSServiceManager(payable(serviceManager)).getOperatorCount() returns (uint256 count) {
                diagnostics = string(abi.encodePacked(diagnostics, "- Operator Count: ", vm.toString(count), "\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- Operator Count: ERROR\n"));
            }
            
            diagnostics = string(abi.encodePacked(diagnostics, "- Balance: ", vm.toString(serviceManager.balance), " wei\n"));
        }
        
        // Price Feed Config diagnostics
        diagnostics = string(abi.encodePacked(diagnostics, "\nPrice Feed Config (", vm.toString(priceFeedConfig), "):\n"));
        if (priceFeedConfig != address(0)) {
            try ProductionPriceFeedConfig(priceFeedConfig).isCurrentNetworkConfigured() returns (bool configured) {
                diagnostics = string(abi.encodePacked(diagnostics, "- Network Configured: ", configured ? "Yes" : "No", "\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- Network Configured: ERROR\n"));
            }
            
            try ProductionPriceFeedConfig(priceFeedConfig).getCurrentNetworkName() returns (string memory name) {
                diagnostics = string(abi.encodePacked(diagnostics, "- Network Name: ", name, "\n"));
            } catch {
                diagnostics = string(abi.encodePacked(diagnostics, "- Network Name: ERROR\n"));
            }
        }
        
        diagnostics = string(abi.encodePacked(diagnostics, "\n========================================="));
        
        return diagnostics;
    }
    
    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Emergency pause all contracts
     */
    function emergencyPauseAll(
        address hook,
        uint256 deployerPrivateKey
    ) external {
        vm.startBroadcast(deployerPrivateKey);
        
        if (hook != address(0)) {
            try EigenLVRHook(payable(hook)).pause() {
                console.log("Hook paused successfully");
            } catch {
                console.log("Failed to pause hook");
            }
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Emergency unpause all contracts
     */
    function emergencyUnpauseAll(
        address hook,
        uint256 deployerPrivateKey
    ) external {
        vm.startBroadcast(deployerPrivateKey);
        
        if (hook != address(0)) {
            try EigenLVRHook(payable(hook)).unpause() {
                console.log("Hook unpaused successfully");
            } catch {
                console.log("Failed to unpause hook");
            }
        }
        
        vm.stopBroadcast();
    }
    
    /**
     * @notice Update LVR threshold
     */
    function updateLVRThreshold(
        address hook,
        uint256 newThreshold,
        uint256 deployerPrivateKey
    ) external {
        require(newThreshold <= 1000, "Threshold too high");
        
        vm.startBroadcast(deployerPrivateKey);
        
        if (hook != address(0)) {
            try EigenLVRHook(payable(hook)).setLVRThreshold(newThreshold) {
                console.log("LVR threshold updated to:", newThreshold);
            } catch {
                console.log("Failed to update LVR threshold");
            }
        }
        
        vm.stopBroadcast();
    }
    
    /*//////////////////////////////////////////////////////////////
                            MONITORING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check system health
     */
    function checkSystemHealth(
        address hook,
        address serviceManager
    ) external view returns (bool healthy, string memory issues) {
        string memory healthIssues = "";
        bool isHealthy = true;
        
        // Check hook health
        if (hook != address(0)) {
            try EigenLVRHook(payable(hook)).paused() returns (bool paused) {
                if (paused) {
                    isHealthy = false;
                    healthIssues = string(abi.encodePacked(healthIssues, "Hook is paused; "));
                }
            } catch {
                isHealthy = false;
                healthIssues = string(abi.encodePacked(healthIssues, "Hook check failed; "));
            }
        }
        
        // Check service manager health
        if (serviceManager != address(0)) {
            try EigenLVRAVSServiceManager(payable(serviceManager)).hasQuorum() returns (bool hasQuorum) {
                if (!hasQuorum) {
                    isHealthy = false;
                    healthIssues = string(abi.encodePacked(healthIssues, "Insufficient operator quorum; "));
                }
            } catch {
                isHealthy = false;
                healthIssues = string(abi.encodePacked(healthIssues, "Service manager check failed; "));
            }
            
            // Check if service manager has funds
            if (serviceManager.balance < 0.1 ether) {
                isHealthy = false;
                healthIssues = string(abi.encodePacked(healthIssues, "Service manager low on funds; "));
            }
        }
        
        if (isHealthy) {
            return (true, "System healthy");
        } else {
            return (false, healthIssues);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Generate deployment report
     */
    function generateDeploymentReport(
        address hook,
        address priceOracle,
        address serviceManager,
        address priceFeedConfig,
        address deployer
    ) external view returns (string memory) {
        return string(abi.encodePacked(
            "# EigenLVR Deployment Report\n\n",
            "**Generated:** ", vm.toString(block.timestamp), "\n",
            "**Chain ID:** ", vm.toString(block.chainid), "\n",
            "**Deployer:** ", vm.toString(deployer), "\n\n",
            
            "## Contract Addresses\n\n",
            "- **EigenLVRHook:** ", vm.toString(hook), "\n",
            "- **ChainlinkPriceOracle:** ", vm.toString(priceOracle), "\n",
            "- **EigenLVRAVSServiceManager:** ", vm.toString(serviceManager), "\n",
            "- **ProductionPriceFeedConfig:** ", vm.toString(priceFeedConfig), "\n\n"
        ));
    }
}