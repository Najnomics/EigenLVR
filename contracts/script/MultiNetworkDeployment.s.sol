// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BaseDeployment.s.sol";

/**
 * @title MultiNetworkDeployment
 * @notice Deploy across multiple networks with consistent configuration
 * @dev Handles cross-chain deployment coordination
 */
contract MultiNetworkDeployment is BaseDeployment {
    
    /*//////////////////////////////////////////////////////////////
                           MULTI-NETWORK STATE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Deployment results per network
    mapping(uint256 => DeploymentResult) public networkDeployments;
    
    /// @notice Supported networks for this deployment
    uint256[] public supportedNetworks = [1, 11155111, 8453, 42161]; // Mainnet, Sepolia, Base, Arbitrum
    
    /// @notice Cross-network configuration
    struct CrossNetworkConfig {
        bool useConsistentSalts;
        bytes32 baseSalt;
        bool syncConfiguration;
        address globalFeeRecipient;
    }
    
    CrossNetworkConfig public crossNetworkConfig;
    
    /*//////////////////////////////////////////////////////////////
                               DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    function run() external returns (DeploymentResult[] memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Setup cross-network configuration
        _setupCrossNetworkConfig(deployer);
        
        DeploymentResult[] memory results = new DeploymentResult[](supportedNetworks.length);
        
        console.log("=== Multi-Network Deployment Started ===");
        console.log("Deployer:", deployer);
        console.log("Networks:", supportedNetworks.length);
        
        for (uint256 i = 0; i < supportedNetworks.length; i++) {
            uint256 chainId = supportedNetworks[i];
            
            console.log("\n--- Deploying to", getNetworkName(chainId), "---");
            
            // Switch to target network (in real deployment, this would be manual)
            // vm.createSelectFork(getRpcUrl(chainId));
            
            if (isNetworkSupported()) {
                vm.startBroadcast(deployerPrivateKey);
                
                DeploymentResult memory result = deployAllContracts(
                    deployer,
                    crossNetworkConfig.globalFeeRecipient
                );
                
                networkDeployments[chainId] = result;
                results[i] = result;
                
                vm.stopBroadcast();
                
                console.log("Deployment complete for", result.networkName);
            } else {
                console.log("Network not supported, skipping...");
            }
        }
        
        // Generate cross-network summary
        _generateCrossNetworkSummary(results);
        
        return results;
    }
    
    /**
     * @notice Setup cross-network configuration
     */
    function _setupCrossNetworkConfig(address deployer) internal {
        crossNetworkConfig = CrossNetworkConfig({
            useConsistentSalts: true,
            baseSalt: keccak256(abi.encodePacked("EigenLVR-MultiNetwork", block.timestamp)),
            syncConfiguration: true,
            globalFeeRecipient: deployer
        });
        
        console.log("Cross-network configuration:");
        console.log("- Consistent salts:", crossNetworkConfig.useConsistentSalts);
        console.log("- Base salt:", vm.toString(crossNetworkConfig.baseSalt));
        console.log("- Global fee recipient:", crossNetworkConfig.globalFeeRecipient);
    }
    
    /**
     * @notice Deploy hook with network-specific salt
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        bytes32 salt;
        
        if (crossNetworkConfig.useConsistentSalts) {
            // Create network-specific but predictable salt
            salt = keccak256(abi.encodePacked(
                crossNetworkConfig.baseSalt,
                block.chainid
            ));
        } else {
            salt = keccak256(abi.encodePacked("EigenLVR", block.chainid, block.timestamp));
        }
        
        console.log("Deploying hook with salt:", vm.toString(salt));
        
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
     * @notice Generate cross-network deployment summary
     */
    function _generateCrossNetworkSummary(DeploymentResult[] memory results) internal {
        console.log("\n=== Cross-Network Deployment Summary ===");
        
        string memory summary = "# EigenLVR Multi-Network Deployment\n\n";
        summary = string(abi.encodePacked(
            summary,
            "**Deployment Time:** ", vm.toString(block.timestamp), "\n",
            "**Networks Deployed:** ", vm.toString(results.length), "\n\n",
            "## Network Deployments\n\n"
        ));
        
        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].hook != address(0)) {
                summary = string(abi.encodePacked(
                    summary,
                    "### ", results[i].networkName, " (Chain ID: ", vm.toString(results[i].chainId), ")\n\n",
                    "| Contract | Address |\n",
                    "|----------|----------|\n",
                    "| EigenLVRHook | `", vm.toString(results[i].hook), "` |\n",
                    "| ChainlinkPriceOracle | `", vm.toString(results[i].priceOracle), "` |\n",
                    "| EigenLVRAVSServiceManager | `", vm.toString(results[i].serviceManager), "` |\n",
                    "| ProductionPriceFeedConfig | `", vm.toString(results[i].priceFeedConfig), "` |\n\n"
                ));
                
                console.log(results[i].networkName, "- Hook:", results[i].hook);
            }
        }
        
        // Add cross-network configuration section
        summary = string(abi.encodePacked(
            summary,
            "## Cross-Network Configuration\n\n",
            "- **Consistent Salts:** ", crossNetworkConfig.useConsistentSalts ? "Yes" : "No", "\n",
            "- **Base Salt:** `", vm.toString(crossNetworkConfig.baseSalt), "`\n",
            "- **Global Fee Recipient:** `", vm.toString(crossNetworkConfig.globalFeeRecipient), "`\n\n",
            
            "## Next Steps\n\n",
            "1. Verify all deployments on respective networks\n",
            "2. Configure frontend for multi-network support\n",
            "3. Setup cross-network monitoring\n",
            "4. Test inter-network compatibility\n",
            "5. Update documentation with all addresses\n"
        ));
        
        vm.writeFile("./deployments/multi-network-deployment.md", summary);
        console.log("Cross-network summary saved to: ./deployments/multi-network-deployment.md");
        
        // Save JSON for programmatic access
        _saveMultiNetworkJSON(results);
    }
    
    /**
     * @notice Save multi-network deployment as JSON
     */
    function _saveMultiNetworkJSON(DeploymentResult[] memory results) internal {
        string memory json = "{\n";
        json = string(abi.encodePacked(
            json,
            '  "deploymentTime": ', vm.toString(block.timestamp), ',\n',
            '  "deployer": "', vm.toString(crossNetworkConfig.globalFeeRecipient), '",\n',
            '  "baseSalt": "', vm.toString(crossNetworkConfig.baseSalt), '",\n',
            '  "networks": {\n'
        ));
        
        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].hook != address(0)) {
                json = string(abi.encodePacked(
                    json,
                    '    "', vm.toString(results[i].chainId), '": {\n',
                    '      "name": "', results[i].networkName, '",\n',
                    '      "hook": "', vm.toString(results[i].hook), '",\n',
                    '      "priceOracle": "', vm.toString(results[i].priceOracle), '",\n',
                    '      "serviceManager": "', vm.toString(results[i].serviceManager), '",\n',
                    '      "priceFeedConfig": "', vm.toString(results[i].priceFeedConfig), '"\n',
                    '    }',
                    i < results.length - 1 ? ",\n" : "\n"
                ));
            }
        }
        
        json = string(abi.encodePacked(json, "  }\n}"));
        
        vm.writeFile("./deployments/multi-network-deployment.json", json);
        console.log("Multi-network JSON saved to: ./deployments/multi-network-deployment.json");
    }
    
    /**
     * @notice Get deployment for specific network
     */
    function getNetworkDeployment(uint256 chainId) external view returns (DeploymentResult memory) {
        return networkDeployments[chainId];
    }
    
    /**
     * @notice Check if all networks are deployed
     */
    function areAllNetworksDeployed() external view returns (bool) {
        for (uint256 i = 0; i < supportedNetworks.length; i++) {
            if (networkDeployments[supportedNetworks[i]].hook == address(0)) {
                return false;
            }
        }
        return true;
    }
}