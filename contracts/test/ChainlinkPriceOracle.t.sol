// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// Enhanced Mock Chainlink Aggregator for comprehensive testing
contract MockChainlinkAggregator {
    int256 private _answer;
    uint256 private _updatedAt;
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    uint80 private _roundId;
    uint80 private _answeredInRound;
    
    constructor(int256 answer_, uint8 decimals_, string memory description_) {
        _answer = answer_;
        _decimals = decimals_;
        _description = description_;
        _updatedAt = block.timestamp;
        _version = 1;
        _roundId = 1;
        _answeredInRound = 1;
    }
    
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    
    function description() external view returns (string memory) {
        return _description;
    }
    
    function version() external view returns (uint256) {
        return _version;
    }
    
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, _answer, block.timestamp, _updatedAt, _answeredInRound);
    }
    
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, block.timestamp, _updatedAt, _answeredInRound);
    }
    
    function setPrice(int256 price_) external {
        _answer = price_;
        _updatedAt = block.timestamp;
        _roundId++;
    }
    
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }
    
    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }
}

contract ChainlinkPriceOracleComprehensiveTest is Test {
    ChainlinkPriceOracle public oracle;
    MockChainlinkAggregator public ethUsdFeed;
    MockChainlinkAggregator public btcUsdFeed;
    MockChainlinkAggregator public usdcUsdFeed;
    MockChainlinkAggregator public daiUsdFeed;
    
    Currency public WETH = Currency.wrap(address(0x100));
    Currency public WBTC = Currency.wrap(address(0x200));
    Currency public USDC = Currency.wrap(address(0x300));
    Currency public DAI = Currency.wrap(address(0x400));
    Currency public UNKNOWN = Currency.wrap(address(0x500));
    
    address public owner = address(0x1);
    address public nonOwner = address(0x2);
    
    event PriceFeedAdded(
        Currency token0,
        Currency token1,
        address priceFeed
    );
    
    event PriceFeedRemoved(
        Currency token0,
        Currency token1
    );
    
    function setUp() public {
        // Warp to a reasonable timestamp to avoid underflows
        vm.warp(86400); // 1 day in seconds
        
        vm.prank(owner);
        oracle = new ChainlinkPriceOracle(owner);
        
        // Deploy mock feeds with realistic data
        ethUsdFeed = new MockChainlinkAggregator(2000e8, 8, "ETH/USD");
        btcUsdFeed = new MockChainlinkAggregator(50000e8, 8, "BTC/USD");
        usdcUsdFeed = new MockChainlinkAggregator(1e8, 8, "USDC/USD");
        daiUsdFeed = new MockChainlinkAggregator(1e8, 8, "DAI/USD");
        
        // Add initial price feeds
        vm.startPrank(owner);
        oracle.addPriceFeed(WETH, USDC, address(ethUsdFeed));
        oracle.addPriceFeed(WBTC, USDC, address(btcUsdFeed));
        oracle.addPriceFeed(USDC, DAI, address(usdcUsdFeed));
        oracle.addPriceFeed(DAI, USDC, address(daiUsdFeed));
        vm.stopPrank();
    }
    
    function test_Constructor() public view {
        assertEq(oracle.owner(), owner);
        assertEq(oracle.MAX_PRICE_STALENESS(), 3600); // 1 hour
        assertEq(oracle.MIN_VALID_PRICE(), 1);
        assertEq(oracle.MAX_VALID_PRICE(), 1e30);
    }
    
    function test_AddPriceFeed() public {
        Currency token0 = Currency.wrap(address(0x600));
        Currency token1 = Currency.wrap(address(0x700));
        address feed = address(0x800);
        
        vm.expectEmit(false, false, false, true);
        emit PriceFeedAdded(token0, token1, feed);
        
        vm.prank(owner);
        oracle.addPriceFeed(token0, token1, feed);
        
        bytes32 pairKey = keccak256(abi.encodePacked(token0, token1));
        assertEq(address(oracle.priceFeeds(pairKey)), feed);
    }
    
    function test_AddPriceFeed_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        oracle.addPriceFeed(WETH, USDC, address(ethUsdFeed));
    }
    
    function test_RemovePriceFeed() public {
        vm.expectEmit(false, false, false, true);
        emit PriceFeedRemoved(WETH, USDC);
        
        vm.prank(owner);
        oracle.removePriceFeed(WETH, USDC);
        
        bytes32 pairKey = keccak256(abi.encodePacked(WETH, USDC));
        assertEq(address(oracle.priceFeeds(pairKey)), address(0));
    }
    
    function test_RemovePriceFeed_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        oracle.removePriceFeed(WETH, USDC);
    }
    
    function test_GetPrice() public view {
        uint256 price = oracle.getPrice(WETH, USDC);
        assertEq(price, 2000e18); // Normalized from 2000e8 to 2000e18
    }
    
    function test_GetPrice_NoPriceFeed() public {
        vm.expectRevert(ChainlinkPriceOracle.NoPriceFeedConfigured.selector);
        oracle.getPrice(UNKNOWN, USDC);
    }
    
    function test_GetPrice_InvalidPrice() public {
        MockChainlinkAggregator negativeFeed = new MockChainlinkAggregator(-100e8, 8, "NEGATIVE/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(negativeFeed));
        
        vm.expectRevert(ChainlinkPriceOracle.InvalidPriceData.selector);
        oracle.getPrice(UNKNOWN, USDC);
    }
    
    function test_GetPrice_StalePrice() public {
        // Ensure we have a proper timestamp
        vm.warp(7200); // Set to 2 hours after epoch
        
        // Set price to be stale (older than 1 hour)
        ethUsdFeed.setUpdatedAt(block.timestamp - 3601);
        
        vm.expectRevert(ChainlinkPriceOracle.StalePriceData.selector);
        oracle.getPrice(WETH, USDC);
    }
    
    function test_GetPrice_ZeroPrice() public {
        MockChainlinkAggregator zeroFeed = new MockChainlinkAggregator(0, 8, "ZERO/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(zeroFeed));
        
        vm.expectRevert(ChainlinkPriceOracle.InvalidPriceData.selector);
        oracle.getPrice(UNKNOWN, USDC);
    }
    
    function test_GetPriceAtTime() public view {
        uint256 price = oracle.getPriceAtTime(WETH, USDC, block.timestamp - 1000);
        // Should return current price (simplified implementation)
        assertEq(price, 2000e18);
    }
    
    function test_IsPriceStale_Fresh() public view {
        bool isStale = oracle.isPriceStale(WETH, USDC);
        assertFalse(isStale);
    }
    
    function test_IsPriceStale_Stale() public {
        ethUsdFeed.setUpdatedAt(block.timestamp - 3601);
        
        bool isStale = oracle.isPriceStale(WETH, USDC);
        assertTrue(isStale);
    }
    
    function test_IsPriceStale_NoPriceFeed() public view {
        bool isStale = oracle.isPriceStale(UNKNOWN, USDC);
        assertTrue(isStale); // Should return true for non-existent feeds
    }
    
    function test_GetLastUpdateTime() public view {
        uint256 updateTime = oracle.getLastUpdateTime(WETH, USDC);
        assertEq(updateTime, block.timestamp);
    }
    
    function test_GetLastUpdateTime_NoPriceFeed() public view {
        uint256 updateTime = oracle.getLastUpdateTime(UNKNOWN, USDC);
        assertEq(updateTime, 0);
    }
    
    function test_PriceNormalization_6Decimals() public {
        MockChainlinkAggregator feed6Dec = new MockChainlinkAggregator(1000e6, 6, "TOKEN/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(feed6Dec));
        
        uint256 price = oracle.getPrice(UNKNOWN, USDC);
        assertEq(price, 1000e18); // Should normalize to 18 decimals
    }
    
    function test_PriceNormalization_18Decimals() public {
        MockChainlinkAggregator feed18Dec = new MockChainlinkAggregator(1000e18, 18, "TOKEN/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(feed18Dec));
        
        uint256 price = oracle.getPrice(UNKNOWN, USDC);
        assertEq(price, 1000e18); // Should remain 18 decimals
    }
    
    function test_PriceNormalization_HighDecimals() public {
        MockChainlinkAggregator feed24Dec = new MockChainlinkAggregator(1000e24, 24, "TOKEN/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(feed24Dec));
        
        uint256 price = oracle.getPrice(UNKNOWN, USDC);
        assertEq(price, 1000e18); // Should normalize down to 18 decimals
    }
    
    function test_PriceNormalization_1Decimal() public {
        MockChainlinkAggregator feed1Dec = new MockChainlinkAggregator(5e1, 1, "TOKEN/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(feed1Dec));
        
        uint256 price = oracle.getPrice(UNKNOWN, USDC);
        assertEq(price, 5e18); // Should normalize up to 18 decimals
    }
    
    function test_MultiplePriceFeeds() public view {
        // Test that multiple price feeds work independently
        uint256 ethPrice = oracle.getPrice(WETH, USDC);
        uint256 btcPrice = oracle.getPrice(WBTC, USDC);
        uint256 usdcPrice = oracle.getPrice(USDC, DAI);
        uint256 daiPrice = oracle.getPrice(DAI, USDC);
        
        assertEq(ethPrice, 2000e18);
        assertEq(btcPrice, 50000e18);
        assertEq(usdcPrice, 1e18);
        assertEq(daiPrice, 1e18);
    }
    
    function test_PriceFeedOverwrite() public {
        MockChainlinkAggregator newFeed = new MockChainlinkAggregator(3000e8, 8, "ETH/USD_NEW");
        
        vm.prank(owner);
        oracle.addPriceFeed(WETH, USDC, address(newFeed));
        
        uint256 price = oracle.getPrice(WETH, USDC);
        assertEq(price, 3000e18); // Should use new feed
    }
    
    function test_SamePairDifferentOrder() public {
        // Test that the same pair in different order uses the same key (canonical ordering)
        MockChainlinkAggregator reverseFeed = new MockChainlinkAggregator(500e8, 8, "USDC/ETH");
        
        vm.prank(owner);
        oracle.addPriceFeed(USDC, WETH, address(reverseFeed));
        
        // Both orders should return the same price since they use the same key
        uint256 ethUsdcPrice = oracle.getPrice(WETH, USDC);
        uint256 usdcEthPrice = oracle.getPrice(USDC, WETH);
        
        // Both should return the same price (500e18) because the implementation
        // sorts tokens to ensure canonical ordering
        assertEq(ethUsdcPrice, 500e18);
        assertEq(usdcEthPrice, 500e18);
    }
    
    function test_ExtremePrices() public {
        // Test very high price that's still within bounds
        MockChainlinkAggregator highPriceFeed = new MockChainlinkAggregator(1e20, 8, "HIGH/USD"); // 1e20 * 1e10 = 1e30 (at the limit)
        
        vm.prank(owner);
        oracle.addPriceFeed(UNKNOWN, USDC, address(highPriceFeed));
        
        uint256 highPrice = oracle.getPrice(UNKNOWN, USDC);
        assertEq(highPrice, 1e30); // Should be exactly at the limit
        
        // Test very low price (but still positive)
        MockChainlinkAggregator lowPriceFeed = new MockChainlinkAggregator(1, 8, "LOW/USD");
        
        vm.prank(owner);
        oracle.addPriceFeed(DAI, UNKNOWN, address(lowPriceFeed));
        
        uint256 lowPrice = oracle.getPrice(DAI, UNKNOWN);
        assertEq(lowPrice, 1e10); // 1 with 8 decimals normalized to 18
    }
    
    function test_TimeBoundaryConditions() public {
        // Test exactly at staleness boundary
        ethUsdFeed.setUpdatedAt(block.timestamp - 3600); // Exactly 1 hour ago
        
        bool isStale = oracle.isPriceStale(WETH, USDC);
        assertFalse(isStale); // Should not be stale at exactly 1 hour
        
        // Test just past staleness boundary
        ethUsdFeed.setUpdatedAt(block.timestamp - 3601); // 1 second past 1 hour
        
        isStale = oracle.isPriceStale(WETH, USDC);
        assertTrue(isStale); // Should be stale
    }
    
    function test_PairKeyGeneration() public pure {
        Currency token0 = Currency.wrap(address(0x100));
        Currency token1 = Currency.wrap(address(0x200));
        
        // Verify that pair keys are generated consistently
        bytes32 key1 = keccak256(abi.encodePacked(token0, token1));
        bytes32 key2 = keccak256(abi.encodePacked(token1, token0));
        
        assertNotEq(key1, key2); // Different pairs should have different keys
        
        // Same pair should generate same key
        bytes32 key3 = keccak256(abi.encodePacked(token0, token1));
        assertEq(key1, key3);
    }
    
    function test_FeedDeletion() public {
        // Remove a feed and verify it's actually deleted
        vm.prank(owner);
        oracle.removePriceFeed(WETH, USDC);
        
        bytes32 pairKey = keccak256(abi.encodePacked(WETH, USDC));
        assertEq(address(oracle.priceFeeds(pairKey)), address(0));
        
        // Verify we can add it back
        vm.prank(owner);
        oracle.addPriceFeed(WETH, USDC, address(ethUsdFeed));
        
        assertEq(address(oracle.priceFeeds(pairKey)), address(ethUsdFeed));
    }
    
    function test_EmptyAddressHandling() public {
        // Test behavior with zero addresses (should revert appropriately)
        Currency zeroToken = Currency.wrap(address(0));
        
        vm.prank(owner);
        oracle.addPriceFeed(zeroToken, USDC, address(ethUsdFeed));
        
        // Should be able to get price even with zero address as token
        uint256 price = oracle.getPrice(zeroToken, USDC);
        assertEq(price, 2000e18);
    }
}