// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BaseDeployment.s.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/**
 * @title ProductionDeployment
 * @notice Production deployment script with proper hook address mining
 * @dev Use this for mainnet and production deployments
 */
contract ProductionDeployment is BaseDeployment {
    
    /// @notice CREATE2 Deployer (same on all networks)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    /// @notice Required hook permissions
    uint160 public constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
        Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
        Hooks.BEFORE_SWAP_FLAG |
        Hooks.AFTER_SWAP_FLAG
    );
    
    /// @notice Mined salt for hook deployment
    bytes32 public minedSalt;
    
    /// @notice Target hook address
    address public targetHookAddress;
    
    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        
        require(isNetworkSupported(), "Network not supported");
        
        // Mine hook address before deployment
        console.log("Mining hook address...");
        _mineHookAddress(deployer, feeRecipient);
        
        vm.startBroadcast(deployerPrivateKey);
        
        DeploymentResult memory result = deployAllContracts(deployer, feeRecipient);
        
        vm.stopBroadcast();
        
        // Verify hook was deployed at the correct address
        require(result.hook == targetHookAddress, "Hook deployed at wrong address");
        
        logDeploymentSummary(result);
        saveDeploymentResults(result);
        _saveProductionArtifacts(result);
        
        return result;
    }
    
    /**
     * @notice Mine a valid hook address
     */
    function _mineHookAddress(address deployer, address feeRecipient) internal {
        NetworkConfig memory config = getCurrentNetworkConfig();
        
        // Prepare constructor arguments for mining
        bytes memory constructorArgs = abi.encode(
            config.poolManager,
            config.avsDirectory,
            address(0), // Placeholder for price oracle (deployed separately)
            feeRecipient,
            config.lvrThreshold
        );
        
        console.log("Required hook flags:", HOOK_FLAGS);
        console.log("Mining address with CREATE2...");
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            HOOK_FLAGS,
            type(EigenLVRHook).creationCode,
            constructorArgs
        );
        
        minedSalt = salt;
        targetHookAddress = hookAddress;
        
        console.log("Found valid hook address:", hookAddress);
        console.log("Mined salt:", vm.toString(salt));
        console.log("Address flags:", uint160(hookAddress) & HookMiner.FLAG_MASK);
        
        // Verify the flags match
        require(
            (uint160(hookAddress) & HookMiner.FLAG_MASK) == HOOK_FLAGS,
            "Invalid hook address flags"
        );
    }
    
    /**
     * @notice Deploy hook with mined address
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        require(minedSalt != bytes32(0), "Hook address not mined");
        
        console.log("Deploying hook at mined address:", targetHookAddress);
        
        EigenLVRHook hook = new EigenLVRHook{salt: minedSalt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            feeRecipient,
            config.lvrThreshold
        );
        
        require(address(hook) == targetHookAddress, "Hook address mismatch");
        
        return hook;
    }
    
    /**
     * @notice Save production-specific artifacts
     */
    function _saveProductionArtifacts(DeploymentResult memory result) internal {
        // Save JSON artifact for programmatic access
        string memory jsonData = string(abi.encodePacked(
            "{\n",
            '  "network": "', result.networkName, '",\n',
            '  "chainId": ', vm.toString(result.chainId), ',\n',
            '  "deploymentTime": ', vm.toString(result.deploymentTime), ',\n',
            '  "contracts": {\n',
            '    "hook": "', vm.toString(result.hook), '",\n',
            '    "priceOracle": "', vm.toString(result.priceOracle), '",\n',
            '    "serviceManager": "', vm.toString(result.serviceManager), '",\n',
            '    "priceFeedConfig": "', vm.toString(result.priceFeedConfig), '"\n',
            '  },\n',
            '  "hookFlags": ', vm.toString(HOOK_FLAGS), ',\n',
            '  "minedSalt": "', vm.toString(minedSalt), '"\n',
            "}"
        ));
        
        string memory jsonFilename = string(abi.encodePacked(
            "./deployments/",
            result.networkName,
            "_production.json"
        ));
        
        vm.writeFile(jsonFilename, jsonData);
        console.log("Production artifacts saved to:", jsonFilename);
        
        // Save environment file for frontend
        string memory envData = string(abi.encodePacked(
            "# EigenLVR Contract Addresses - ", result.networkName, "\n",
            "REACT_APP_HOOK_ADDRESS=", vm.toString(result.hook), "\n",
            "REACT_APP_PRICE_ORACLE_ADDRESS=", vm.toString(result.priceOracle), "\n",
            "REACT_APP_SERVICE_MANAGER_ADDRESS=", vm.toString(result.serviceManager), "\n",
            "REACT_APP_PRICE_FEED_CONFIG_ADDRESS=", vm.toString(result.priceFeedConfig), "\n",
            "REACT_APP_CHAIN_ID=", vm.toString(result.chainId), "\n",
            "REACT_APP_NETWORK_NAME=", result.networkName, "\n"
        ));
        
        string memory envFilename = string(abi.encodePacked(
            "./deployments/.",
            result.networkName,
            ".env"
        ));
        
        vm.writeFile(envFilename, envData);
        console.log("Environment file saved to:", envFilename);
    }
}