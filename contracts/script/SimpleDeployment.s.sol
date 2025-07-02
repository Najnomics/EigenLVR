// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BaseDeployment.s.sol";

/**
 * @title SimpleDeployment
 * @notice Simple deployment script for EigenLVR without hook address mining
 * @dev Use this for testing and development environments
 */
contract SimpleDeployment is BaseDeployment {
    
    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        
        require(isNetworkSupported(), "Network not supported");
        
        vm.startBroadcast(deployerPrivateKey);
        
        DeploymentResult memory result = deployAllContracts(deployer, feeRecipient);
        
        vm.stopBroadcast();
        
        logDeploymentSummary(result);
        saveDeploymentResults(result);
        
        return result;
    }
    
    /**
     * @notice Deploy hook without address mining (for testing)
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        // Simple deployment without address mining
        // Note: This may not work with actual Uniswap v4 due to hook address validation
        bytes32 salt = keccak256(abi.encodePacked("EigenLVR", block.timestamp));
        
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            feeRecipient,
            config.lvrThreshold
        );
        
        return hook;
    }
}