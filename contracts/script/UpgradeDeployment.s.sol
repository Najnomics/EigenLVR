// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BaseDeployment.s.sol";

/**
 * @title UpgradeDeployment
 * @notice Script for upgrading existing EigenLVR deployments
 * @dev Handles migration of data and configuration
 */
contract UpgradeDeployment is BaseDeployment {
    
    /*//////////////////////////////////////////////////////////////
                              OLD CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    struct OldContracts {
        address hook;
        address priceOracle;
        address serviceManager;
        address priceFeedConfig;
    }
    
    OldContracts public oldContracts;
    
    /*//////////////////////////////////////////////////////////////
                               MIGRATION
    //////////////////////////////////////////////////////////////*/
    
    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        
        // Load old contract addresses
        _loadOldContracts();
        
        require(isNetworkSupported(), "Network not supported");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Backup old state
        _backupOldState();
        
        // Deploy new contracts
        DeploymentResult memory result = deployAllContracts(deployer, feeRecipient);
        
        // Migrate data
        _migrateData(result);
        
        vm.stopBroadcast();
        
        logDeploymentSummary(result);
        _logMigrationSummary();
        saveDeploymentResults(result);
        
        return result;
    }
    
    /**
     * @notice Load old contract addresses from environment or file
     */
    function _loadOldContracts() internal {
        // Try to load from environment variables first
        oldContracts.hook = vm.envOr("OLD_HOOK_ADDRESS", address(0));
        oldContracts.priceOracle = vm.envOr("OLD_PRICE_ORACLE_ADDRESS", address(0));
        oldContracts.serviceManager = vm.envOr("OLD_SERVICE_MANAGER_ADDRESS", address(0));
        oldContracts.priceFeedConfig = vm.envOr("OLD_PRICE_FEED_CONFIG_ADDRESS", address(0));
        
        // If not found in env, try to load from latest deployment file
        if (oldContracts.hook == address(0)) {
            _loadFromDeploymentFile();
        }
        
        console.log("Old contracts loaded:");
        console.log("- Hook:", oldContracts.hook);
        console.log("- Price Oracle:", oldContracts.priceOracle);
        console.log("- Service Manager:", oldContracts.serviceManager);
        console.log("- Price Feed Config:", oldContracts.priceFeedConfig);
    }
    
    /**
     * @notice Load from deployment file (simplified - in production use JSON parsing)
     */
    function _loadFromDeploymentFile() internal {
        // In a real implementation, you'd parse the JSON deployment file
        // For now, this is a placeholder
        console.log("Attempting to load from deployment file...");
        console.log("Note: Implement JSON parsing for production use");
    }
    
    /**
     * @notice Backup old contract state
     */
    function _backupOldState() internal view {
        console.log("\n=== Backing up old state ===");
        
        if (oldContracts.hook != address(0)) {
            EigenLVRHook oldHook = EigenLVRHook(payable(oldContracts.hook));
            
            console.log("Old hook state:");
            console.log("- LVR Threshold:", oldHook.lvrThreshold());
            console.log("- Fee Recipient:", oldHook.feeRecipient());
            console.log("- Paused:", oldHook.paused());
            
            // In production, you'd save this to a file
        }
        
        console.log("State backup complete");
    }
    
    /**
     * @notice Migrate data from old contracts to new ones
     */
    function _migrateData(DeploymentResult memory result) internal {
        console.log("\n=== Migrating data ===");
        
        if (oldContracts.hook != address(0)) {
            EigenLVRHook oldHook = EigenLVRHook(payable(oldContracts.hook));
            EigenLVRHook newHook = EigenLVRHook(payable(result.hook));
            
            // Migrate operator authorizations
            _migrateOperatorAuthorizations(oldHook, newHook);
            
            // Migrate configuration
            _migrateConfiguration(oldHook, newHook);
            
            // Migrate price feeds
            if (oldContracts.priceFeedConfig != address(0)) {
                _migratePriceFeeds(result);
            }
        }
        
        console.log("Data migration complete");
    }
    
    /**
     * @notice Migrate operator authorizations
     */
    function _migrateOperatorAuthorizations(EigenLVRHook oldHook, EigenLVRHook newHook) internal {
        console.log("Migrating operator authorizations...");
        
        // Note: In production, you'd need to track authorized operators
        // This would require either events parsing or maintaining a list
        
        // For now, migrate the deployer and common operators
        address deployer = tx.origin;
        if (oldHook.authorizedOperators(deployer)) {
            newHook.setOperatorAuthorization(deployer, true);
            console.log("Migrated deployer authorization");
        }
        
        // Migrate service manager authorization
        if (oldContracts.serviceManager != address(0)) {
            if (oldHook.authorizedOperators(oldContracts.serviceManager)) {
                newHook.setOperatorAuthorization(oldContracts.serviceManager, true);
                console.log("Migrated service manager authorization");
            }
        }
    }
    
    /**
     * @notice Migrate configuration settings
     */
    function _migrateConfiguration(EigenLVRHook oldHook, EigenLVRHook newHook) internal {
        console.log("Migrating configuration...");
        
        // Migrate LVR threshold if different
        uint256 oldThreshold = oldHook.lvrThreshold();
        uint256 newThreshold = newHook.lvrThreshold();
        
        if (oldThreshold != newThreshold) {
            console.log("LVR threshold changed from", oldThreshold, "to", newThreshold);
            // Optionally set to old value: newHook.setLVRThreshold(oldThreshold);
        }
        
        // Migrate fee recipient
        address oldFeeRecipient = oldHook.feeRecipient();
        address newFeeRecipient = newHook.feeRecipient();
        
        if (oldFeeRecipient != newFeeRecipient) {
            newHook.setFeeRecipient(oldFeeRecipient);
            console.log("Migrated fee recipient:", oldFeeRecipient);
        }
        
        // Maintain paused state if needed
        if (oldHook.paused() && !newHook.paused()) {
            newHook.pause();
            console.log("Maintained paused state");
        }
    }
    
    /**
     * @notice Migrate price feeds configuration
     */
    function _migratePriceFeeds(DeploymentResult memory result) internal {
        console.log("Migrating price feeds...");
        
        ProductionPriceFeedConfig newConfig = ProductionPriceFeedConfig(result.priceFeedConfig);
        
        // Check if old network was configured
        ProductionPriceFeedConfig oldConfig = ProductionPriceFeedConfig(oldContracts.priceFeedConfig);
        
        if (oldConfig.networkConfigured(block.chainid)) {
            console.log("Old network was configured, auto-configuring new network");
            newConfig.autoConfigureNetwork();
        }
    }
    
    /**
     * @notice Deploy hook with upgrade considerations
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        // For upgrades, use a predictable salt based on previous deployment
        bytes32 salt = keccak256(abi.encodePacked(
            "EigenLVR-Upgrade",
            block.chainid,
            block.timestamp
        ));
        
        console.log("Deploying upgraded hook with salt:", vm.toString(salt));
        
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            feeRecipient,
            config.lvrThreshold
        );
        
        return hook;
    }
    
    /**
     * @notice Log migration summary
     */
    function _logMigrationSummary() internal view {
        console.log("\n=== Migration Summary ===");
        console.log("Migration completed successfully!");
        console.log("");
        console.log("Old contracts:");
        console.log("- Hook:", oldContracts.hook);
        console.log("- Price Oracle:", oldContracts.priceOracle);
        console.log("- Service Manager:", oldContracts.serviceManager);
        console.log("- Price Feed Config:", oldContracts.priceFeedConfig);
        console.log("");
        console.log("New contracts deployed with migrated configuration");
        console.log("");
        console.log("IMPORTANT: Update frontend and off-chain components");
        console.log("with new contract addresses!");
        console.log("========================");
    }
}