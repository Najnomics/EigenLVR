// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ProductionPriceFeedConfig} from "../src/ProductionPriceFeedConfig.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";

contract ProductionPriceFeedConfigTest is Test {
    ProductionPriceFeedConfig public config;
    ChainlinkPriceOracle public oracle;
    
    address public owner = address(0x1);
    address public nonOwner = address(0x2);
    
    event NetworkConfigured(uint256 indexed chainId, uint256 feedCount);
    event PriceFeedAdded(address indexed token0, address indexed token1, address priceFeed);
    event PriceFeedRemoved(address indexed token0, address indexed token1);
    
    function setUp() public {
        vm.startPrank(owner);
        oracle = new ChainlinkPriceOracle(owner);
        config = new ProductionPriceFeedConfig(oracle);
        
        // Transfer oracle ownership to config contract so it can manage price feeds
        oracle.transferOwnership(address(config));
        vm.stopPrank();
    }
    
    function test_Constructor() public view {
        assertEq(address(config.priceOracle()), address(oracle));
        assertEq(config.owner(), owner);
    }
    
    function test_ConfigureMainnet() public {
        vm.chainId(1); // Mainnet
        
        vm.expectEmit(true, false, false, true);
        emit NetworkConfigured(1, 6);
        
        vm.prank(owner);
        config.configureMainnet();
        
        assertTrue(config.networkConfigured(1));
    }
    
    function test_ConfigureMainnet_AlreadyConfigured() public {
        vm.chainId(1);
        
        vm.startPrank(owner);
        config.configureMainnet();
        
        vm.expectRevert("Mainnet already configured");
        config.configureMainnet();
        vm.stopPrank();
    }
    
    function test_ConfigureSepolia() public {
        vm.chainId(11155111); // Sepolia
        
        vm.expectEmit(true, false, false, true);
        emit NetworkConfigured(11155111, 3);
        
        vm.prank(owner);
        config.configureSepolia();
        
        assertTrue(config.networkConfigured(11155111));
    }
    
    function test_ConfigureSepolia_AlreadyConfigured() public {
        vm.chainId(11155111);
        
        vm.startPrank(owner);
        config.configureSepolia();
        
        vm.expectRevert("Sepolia already configured");
        config.configureSepolia();
        vm.stopPrank();
    }
    
    function test_ConfigureBase() public {
        vm.chainId(8453); // Base
        
        vm.expectEmit(true, false, false, true);
        emit NetworkConfigured(8453, 3);
        
        vm.prank(owner);
        config.configureBase();
        
        assertTrue(config.networkConfigured(8453));
    }
    
    function test_ConfigureBase_AlreadyConfigured() public {
        vm.chainId(8453);
        
        vm.startPrank(owner);
        config.configureBase();
        
        vm.expectRevert("Base already configured");
        config.configureBase();
        vm.stopPrank();
    }
    
    function test_ConfigureArbitrum() public {
        vm.chainId(42161); // Arbitrum
        
        vm.expectEmit(true, false, false, true);
        emit NetworkConfigured(42161, 4);
        
        vm.prank(owner);
        config.configureArbitrum();
        
        assertTrue(config.networkConfigured(42161));
    }
    
    function test_ConfigureArbitrum_AlreadyConfigured() public {
        vm.chainId(42161);
        
        vm.startPrank(owner);
        config.configureArbitrum();
        
        vm.expectRevert("Arbitrum already configured");
        config.configureArbitrum();
        vm.stopPrank();
    }
    
    function test_AutoConfigureNetwork_Mainnet() public {
        vm.chainId(1);
        
        vm.prank(owner);
        config.autoConfigureNetwork();
        
        assertTrue(config.networkConfigured(1));
    }
    
    function test_AutoConfigureNetwork_Sepolia() public {
        vm.chainId(11155111);
        
        vm.prank(owner);
        config.autoConfigureNetwork();
        
        assertTrue(config.networkConfigured(11155111));
    }
    
    function test_AutoConfigureNetwork_Base() public {
        vm.chainId(8453);
        
        vm.prank(owner);
        config.autoConfigureNetwork();
        
        assertTrue(config.networkConfigured(8453));
    }
    
    function test_AutoConfigureNetwork_Arbitrum() public {
        vm.chainId(42161);
        
        vm.prank(owner);
        config.autoConfigureNetwork();
        
        assertTrue(config.networkConfigured(42161));
    }
    
    function test_AutoConfigureNetwork_UnsupportedNetwork() public {
        vm.chainId(999); // Unsupported network
        
        vm.prank(owner);
        vm.expectRevert("Unsupported network for auto-configuration");
        config.autoConfigureNetwork();
    }
    
    function test_AutoConfigureNetwork_OnlyOwner() public {
        vm.chainId(1);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.autoConfigureNetwork();
    }
    
    function test_AddCustomPriceFeed() public {
        address token0 = address(0x100);
        address token1 = address(0x200);
        address priceFeed = address(0x300);
        
        vm.expectEmit(true, true, false, true);
        emit PriceFeedAdded(token0, token1, priceFeed);
        
        vm.prank(owner);
        config.addCustomPriceFeed(token0, token1, priceFeed);
    }
    
    function test_AddCustomPriceFeed_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        config.addCustomPriceFeed(address(0x100), address(0x200), address(0x300));
    }
    
    function test_RemovePriceFeed() public {
        // First add a custom feed
        address token0 = address(0x100);
        address token1 = address(0x200);
        address priceFeed = address(0x300);
        
        vm.startPrank(owner);
        config.addCustomPriceFeed(token0, token1, priceFeed);
        
        vm.expectEmit(true, true, false, true);
        emit PriceFeedRemoved(token0, token1);
        
        config.removePriceFeed(token0, token1);
        vm.stopPrank();
    }
    
    function test_RemovePriceFeed_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        config.removePriceFeed(address(0x100), address(0x200));
    }
    
    function test_IsCurrentNetworkConfigured_True() public {
        vm.chainId(1);
        
        vm.prank(owner);
        config.configureMainnet();
        
        assertTrue(config.isCurrentNetworkConfigured());
    }
    
    function test_IsCurrentNetworkConfigured_False() public {
        vm.chainId(999);
        
        assertFalse(config.isCurrentNetworkConfigured());
    }
    
    function test_GetCurrentNetworkName() public {
        vm.chainId(1);
        assertEq(config.getCurrentNetworkName(), "Ethereum Mainnet");
        
        vm.chainId(11155111);
        assertEq(config.getCurrentNetworkName(), "Sepolia Testnet");
        
        vm.chainId(8453);
        assertEq(config.getCurrentNetworkName(), "Base");
        
        vm.chainId(42161);
        assertEq(config.getCurrentNetworkName(), "Arbitrum One");
        
        vm.chainId(31337);
        assertEq(config.getCurrentNetworkName(), "Localhost");
        
        vm.chainId(999);
        assertEq(config.getCurrentNetworkName(), "Unknown Network");
    }
    
    function test_BatchAddPriceFeeds() public {
        ProductionPriceFeedConfig.PriceFeedConfig[] memory configs = 
            new ProductionPriceFeedConfig.PriceFeedConfig[](2);
        
        configs[0] = ProductionPriceFeedConfig.PriceFeedConfig({
            token0: address(0x100),
            token1: address(0x200),
            priceFeed: address(0x300),
            description: "Test Feed 1",
            isActive: true
        });
        
        configs[1] = ProductionPriceFeedConfig.PriceFeedConfig({
            token0: address(0x400),
            token1: address(0x500),
            priceFeed: address(0x600),
            description: "Test Feed 2",
            isActive: true
        });
        
        vm.expectEmit(true, true, false, true);
        emit PriceFeedAdded(address(0x100), address(0x200), address(0x300));
        
        vm.expectEmit(true, true, false, true);
        emit PriceFeedAdded(address(0x400), address(0x500), address(0x600));
        
        vm.prank(owner);
        config.batchAddPriceFeeds(configs);
    }
    
    function test_BatchAddPriceFeeds_OnlyOwner() public {
        ProductionPriceFeedConfig.PriceFeedConfig[] memory configs = 
            new ProductionPriceFeedConfig.PriceFeedConfig[](1);
        
        configs[0] = ProductionPriceFeedConfig.PriceFeedConfig({
            token0: address(0x100),
            token1: address(0x200),
            priceFeed: address(0x300),
            description: "Test Feed",
            isActive: true
        });
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.batchAddPriceFeeds(configs);
    }
    
    function test_BatchAddPriceFeeds_EmptyArray() public {
        ProductionPriceFeedConfig.PriceFeedConfig[] memory configs = 
            new ProductionPriceFeedConfig.PriceFeedConfig[](0);
        
        vm.prank(owner);
        config.batchAddPriceFeeds(configs); // Should not revert
    }
    
    function test_EmergencyReconfigure() public {
        vm.chainId(1);
        
        // First configure normally
        vm.startPrank(owner);
        config.configureMainnet();
        assertTrue(config.networkConfigured(1));
        
        // Emergency reconfigure should reset and reconfigure
        config.emergencyReconfigure();
        assertTrue(config.networkConfigured(1)); // Should still be configured after emergency reconfigure
        vm.stopPrank();
    }
    
    function test_EmergencyReconfigure_OnlyOwner() public {
        vm.chainId(1);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.emergencyReconfigure();
    }
    
    function test_EmergencyReconfigure_UnsupportedNetwork() public {
        vm.chainId(999);
        
        vm.prank(owner);
        vm.expectRevert("Unsupported network for auto-configuration");
        config.emergencyReconfigure();
    }
    
    function test_ConfigureMainnet_OnlyOwner() public {
        vm.chainId(1);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.configureMainnet();
    }
    
    function test_ConfigureSepolia_OnlyOwner() public {
        vm.chainId(11155111);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.configureSepolia();
    }
    
    function test_ConfigureBase_OnlyOwner() public {
        vm.chainId(8453);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.configureBase();
    }
    
    function test_ConfigureArbitrum_OnlyOwner() public {
        vm.chainId(42161);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        config.configureArbitrum();
    }
    
    function test_MultipleNetworkConfiguration() public {
        // Test configuring multiple networks
        vm.chainId(1);
        vm.prank(owner);
        config.configureMainnet();
        assertTrue(config.networkConfigured(1));
        
        vm.chainId(11155111);
        vm.prank(owner);
        config.configureSepolia();
        assertTrue(config.networkConfigured(11155111));
        
        vm.chainId(8453);
        vm.prank(owner);
        config.configureBase();
        assertTrue(config.networkConfigured(8453));
        
        vm.chainId(42161);
        vm.prank(owner);
        config.configureArbitrum();
        assertTrue(config.networkConfigured(42161));
        
        // All networks should remain configured
        assertTrue(config.networkConfigured(1));
        assertTrue(config.networkConfigured(11155111));
        assertTrue(config.networkConfigured(8453));
        assertTrue(config.networkConfigured(42161));
    }
    
    function test_NetworkConfigurationIndependence() public {
        // Configure one network
        vm.chainId(1);
        vm.prank(owner);
        config.configureMainnet();
        
        // Other networks should not be affected
        assertFalse(config.networkConfigured(11155111));
        assertFalse(config.networkConfigured(8453));
        assertFalse(config.networkConfigured(42161));
        
        // Current network should be configured
        assertTrue(config.networkConfigured(1));
    }
    
    function test_ChainIdHandling() public {
        // Test all supported chain IDs
        uint256[] memory supportedChains = new uint256[](4);
        supportedChains[0] = 1;       // Mainnet
        supportedChains[1] = 11155111; // Sepolia
        supportedChains[2] = 8453;    // Base
        supportedChains[3] = 42161;   // Arbitrum
        
        for (uint256 i = 0; i < supportedChains.length; i++) {
            vm.chainId(supportedChains[i]);
            // Should not revert for supported chains
            string memory networkName = config.getCurrentNetworkName();
            assertTrue(bytes(networkName).length > 0);
        }
    }
    
    function test_AddCustomPriceFeed_ZeroAddresses() public {
        // Test behavior with zero addresses - should revert
        vm.prank(owner);
        vm.expectRevert("Invalid price feed address");
        config.addCustomPriceFeed(address(0), address(0), address(0));
    }
    
    function test_BatchOperations_LargeArray() public {
        // Test with a larger array to ensure gas efficiency
        uint256 arraySize = 10;
        ProductionPriceFeedConfig.PriceFeedConfig[] memory configs = 
            new ProductionPriceFeedConfig.PriceFeedConfig[](arraySize);
        
        for (uint256 i = 0; i < arraySize; i++) {
            configs[i] = ProductionPriceFeedConfig.PriceFeedConfig({
                token0: address(uint160(0x100 + i)),
                token1: address(uint160(0x200 + i)),
                priceFeed: address(uint160(0x300 + i)),
                description: "Batch Test Feed",
                isActive: true
            });
        }
        
        vm.prank(owner);
        config.batchAddPriceFeeds(configs);
    }
    
    function test_ReconfigurationAfterEmergency() public {
        vm.chainId(1);
        
        vm.startPrank(owner);
        // Configure initially
        config.configureMainnet();
        assertTrue(config.networkConfigured(1));
        
        // Emergency reconfigure
        config.emergencyReconfigure();
        
        // Should still be configured after emergency reconfigure
        assertTrue(config.networkConfigured(1));
        vm.stopPrank();
    }
}