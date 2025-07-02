// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {EigenLVRAVSServiceManager} from "../src/EigenLVRAVSServiceManager.sol";
import {ProductionPriceFeedConfig} from "../src/ProductionPriceFeedConfig.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title BaseDeployment
 * @notice Base contract for EigenLVR deployments with common functionality
 */
abstract contract BaseDeployment is Script {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Network configuration
    struct NetworkConfig {
        address poolManager;
        address avsDirectory;
        address delegationManager;
        uint256 lvrThreshold;
        uint256 minimumStake;
        string networkName;
    }
    
    /// @notice Deployment result
    struct DeploymentResult {
        address hook;
        address priceOracle;
        address serviceManager;
        address priceFeedConfig;
        address deployer;
        uint256 chainId;
        string networkName;
        uint256 deploymentTime;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT STATE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Deployment results
    DeploymentResult public deploymentResult;
    
    /// @notice Network configurations
    mapping(uint256 => NetworkConfig) public networkConfigs;
    
    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier validNetwork() {
        require(
            networkConfigs[block.chainid].poolManager != address(0),
            "Network not configured"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor() {
        _setupNetworkConfigs();
    }

    /*//////////////////////////////////////////////////////////////
                           CORE DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deploy all EigenLVR contracts
     * @param deployer The deployer address
     * @param feeRecipient The fee recipient address
     * @return result The deployment result
     */
    function deployAllContracts(
        address deployer,
        address feeRecipient
    ) internal validNetwork returns (DeploymentResult memory result) {
        NetworkConfig memory config = networkConfigs[block.chainid];
        
        console.log("=== EigenLVR Deployment Starting ===");
        console.log("Network:", config.networkName);
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Fee Recipient:", feeRecipient);
        
        // 1. Deploy ChainlinkPriceOracle
        console.log("\n1. Deploying ChainlinkPriceOracle...");
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle(deployer);
        console.log("ChainlinkPriceOracle deployed at:", address(priceOracle));
        
        // 2. Deploy EigenLVRAVSServiceManager
        console.log("\n2. Deploying EigenLVRAVSServiceManager...");
        EigenLVRAVSServiceManager serviceManager = new EigenLVRAVSServiceManager(
            IAVSDirectory(config.avsDirectory)
        );
        console.log("EigenLVRAVSServiceManager deployed at:", address(serviceManager));
        
        // 3. Deploy ProductionPriceFeedConfig
        console.log("\n3. Deploying ProductionPriceFeedConfig...");
        ProductionPriceFeedConfig priceFeedConfig = new ProductionPriceFeedConfig(
            priceOracle
        );
        console.log("ProductionPriceFeedConfig deployed at:", address(priceFeedConfig));
        
        // 4. Deploy EigenLVRHook (handled by specific implementations)
        console.log("\n4. Deploying EigenLVRHook...");
        EigenLVRHook hook = _deployHook(
            config,
            priceOracle,
            deployer,
            feeRecipient
        );
        console.log("EigenLVRHook deployed at:", address(hook));
        
        // 5. Configure the system
        _configureSystem(hook, priceOracle, serviceManager, priceFeedConfig, deployer);
        
        // Return deployment result
        result = DeploymentResult({
            hook: address(hook),
            priceOracle: address(priceOracle),
            serviceManager: address(serviceManager),
            priceFeedConfig: address(priceFeedConfig),
            deployer: deployer,
            chainId: block.chainid,
            networkName: config.networkName,
            deploymentTime: block.timestamp
        });
        
        deploymentResult = result;
        
        console.log("\n=== EigenLVR Deployment Complete ===");
        return result;
    }
    
    /**
     * @notice Configure the deployed system
     */
    function _configureSystem(
        EigenLVRHook hook,
        ChainlinkPriceOracle priceOracle,
        EigenLVRAVSServiceManager serviceManager,
        ProductionPriceFeedConfig priceFeedConfig,
        address deployer
    ) internal {
        console.log("\n=== System Configuration ===");
        
        // Configure price feeds for current network
        console.log("Configuring price feeds...");
        priceFeedConfig.autoConfigureNetwork();
        
        // Set up operator authorization
        console.log("Setting up operator authorization...");
        hook.setOperatorAuthorization(deployer, true);
        hook.setOperatorAuthorization(address(serviceManager), true);
        
        // Fund service manager for rewards
        console.log("Funding service manager...");
        serviceManager.fundRewardPool{value: 1 ether}();
        
        console.log("System configuration complete!");
    }

    /*//////////////////////////////////////////////////////////////
                          NETWORK CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Setup network configurations
     */
    function _setupNetworkConfigs() internal {
        // Ethereum Mainnet
        networkConfigs[1] = NetworkConfig({
            poolManager: 0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967, // Placeholder - update with real address
            avsDirectory: 0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF, // EigenLayer AVS Directory
            delegationManager: 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A, // EigenLayer Delegation Manager
            lvrThreshold: 50, // 0.5%
            minimumStake: 32 ether,
            networkName: "Ethereum Mainnet"
        });
        
        // Sepolia Testnet
        networkConfigs[11155111] = NetworkConfig({
            poolManager: 0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967, // Placeholder - update with real address
            avsDirectory: 0xD614b51eFF0C11aAe5F0af16ee1a5dd9996eeBD4, // EigenLayer AVS Directory Sepolia
            delegationManager: 0xA44151489861Fe9e3055d95adC98FbD462B948e7, // EigenLayer Delegation Manager Sepolia
            lvrThreshold: 100, // 1% (higher for testnet)
            minimumStake: 1 ether, // Lower for testnet
            networkName: "Sepolia Testnet"
        });
        
        // Base
        networkConfigs[8453] = NetworkConfig({
            poolManager: 0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967, // Placeholder - update with real address
            avsDirectory: address(0), // Not available on Base yet
            delegationManager: address(0), // Not available on Base yet
            lvrThreshold: 75, // 0.75%
            minimumStake: 16 ether,
            networkName: "Base"
        });
        
        // Arbitrum One
        networkConfigs[42161] = NetworkConfig({
            poolManager: 0x38EB8B22Df3Ae7fb21e92881151B365Df14ba967, // Placeholder - update with real address
            avsDirectory: address(0), // Not available on Arbitrum yet
            delegationManager: address(0), // Not available on Arbitrum yet
            lvrThreshold: 75, // 0.75%
            minimumStake: 16 ether,
            networkName: "Arbitrum One"
        });
        
        // Local/Anvil
        networkConfigs[31337] = NetworkConfig({
            poolManager: 0x5FbDB2315678afecb367f032d93F642f64180aa3, // Default anvil deployment
            avsDirectory: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, // Mock deployment
            delegationManager: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0, // Mock deployment
            lvrThreshold: 50, // 0.5%
            minimumStake: 1 ether,
            networkName: "Local/Anvil"
        });
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get current network configuration
     */
    function getCurrentNetworkConfig() public view returns (NetworkConfig memory) {
        return networkConfigs[block.chainid];
    }
    
    /**
     * @notice Check if current network is supported
     */
    function isNetworkSupported() public view returns (bool) {
        return networkConfigs[block.chainid].poolManager != address(0);
    }
    
    /**
     * @notice Get network name for chain ID
     */
    function getNetworkName(uint256 chainId) public view returns (string memory) {
        if (bytes(networkConfigs[chainId].networkName).length > 0) {
            return networkConfigs[chainId].networkName;
        }
        return "Unknown Network";
    }

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deploy the hook - must be implemented by derived contracts
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal virtual returns (EigenLVRHook);

    /*//////////////////////////////////////////////////////////////
                            LOGGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Log deployment summary
     */
    function logDeploymentSummary(DeploymentResult memory result) internal view {
        console.log("\n=== Final Deployment Summary ===");
        console.log("Network:", result.networkName);
        console.log("Chain ID:", result.chainId);
        console.log("Deployment Time:", result.deploymentTime);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- EigenLVRHook:", result.hook);
        console.log("- ChainlinkPriceOracle:", result.priceOracle);
        console.log("- EigenLVRAVSServiceManager:", result.serviceManager);
        console.log("- ProductionPriceFeedConfig:", result.priceFeedConfig);
        console.log("");
        console.log("Deployer:", result.deployer);
        console.log("===============================");
    }
    
    /**
     * @notice Save deployment results to file
     */
    function saveDeploymentResults(DeploymentResult memory result) internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "# EigenLVR Deployment Results\n\n",
            "**Network:** ", result.networkName, "\n",
            "**Chain ID:** ", vm.toString(result.chainId), "\n",
            "**Deployment Time:** ", vm.toString(result.deploymentTime), "\n",
            "**Deployer:** ", vm.toString(result.deployer), "\n\n",
            
            "## Contract Addresses\n\n",
            "| Contract | Address |\n",
            "|----------|----------|\n",
            "| EigenLVRHook | `", vm.toString(result.hook), "` |\n",
            "| ChainlinkPriceOracle | `", vm.toString(result.priceOracle), "` |\n",
            "| EigenLVRAVSServiceManager | `", vm.toString(result.serviceManager), "` |\n",
            "| ProductionPriceFeedConfig | `", vm.toString(result.priceFeedConfig), "` |\n\n",
            
            "## Verification Commands\n\n",
            "```bash\n",
            "# Verify EigenLVRHook\n",
            "forge verify-contract ", vm.toString(result.hook), " src/EigenLVRHook.sol:EigenLVRHook --chain-id ", vm.toString(result.chainId), "\n\n",
            "# Verify ChainlinkPriceOracle\n",
            "forge verify-contract ", vm.toString(result.priceOracle), " src/ChainlinkPriceOracle.sol:ChainlinkPriceOracle --chain-id ", vm.toString(result.chainId), "\n",
            "```\n"
        ));
        
        string memory filename = string(abi.encodePacked(
            "./deployments/",
            result.networkName,
            "_deployment_",
            vm.toString(result.deploymentTime),
            ".md"
        ));
        
        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment results saved to:", filename);
    }
}