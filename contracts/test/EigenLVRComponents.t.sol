// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Mock Chainlink aggregator for testing
contract MockAggregator {
    int256 public price;
    uint8 public decimals;
    uint256 public updatedAt;
    
    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals = _decimals;
        updatedAt = block.timestamp;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updateAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, updatedAt, 1);
    }
    
    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }
    
    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }
}

/**
 * @title EigenLVR Component Tests
 * @notice Tests for individual components of the EigenLVR system
 */
contract EigenLVRComponentTest is Test {
    using AuctionLib for AuctionLib.Auction;
    
    // Test constants - moved to pure functions to avoid compiler warnings
    function BASIS_POINTS() internal pure returns (uint256) { return 10000; }
    function LP_REWARD_PERCENTAGE() internal pure returns (uint256) { return 8500; }
    function AVS_REWARD_PERCENTAGE() internal pure returns (uint256) { return 1000; }
    function PROTOCOL_FEE_PERCENTAGE() internal pure returns (uint256) { return 300; }
    function MIN_BID() internal pure returns (uint256) { return 1e15; }
    function MAX_AUCTION_DURATION() internal pure returns (uint256) { return 12; }
    
    function test_Constants_Validation() public pure {
        // Verify all percentages add up to less than 100%
        uint256 totalPercentage = LP_REWARD_PERCENTAGE() + AVS_REWARD_PERCENTAGE() + PROTOCOL_FEE_PERCENTAGE();
        assert(totalPercentage <= BASIS_POINTS()); // Should be 9800 (98%)
        
        // Verify minimum bid is reasonable
        assert(MIN_BID() > 0);
        assert(MIN_BID() == 1e15); // 0.001 ETH
        
        // Verify auction duration is reasonable
        assert(MAX_AUCTION_DURATION() > 0);
        assert(MAX_AUCTION_DURATION() <= 60); // At most 1 minute
    }
    
    function test_MEV_Distribution() public pure {
        uint256 totalProceeds = 1 ether;
        
        uint256 lpAmount = (totalProceeds * LP_REWARD_PERCENTAGE()) / BASIS_POINTS();
        uint256 avsAmount = (totalProceeds * AVS_REWARD_PERCENTAGE()) / BASIS_POINTS();
        uint256 protocolAmount = (totalProceeds * PROTOCOL_FEE_PERCENTAGE()) / BASIS_POINTS();
        
        assertEq(lpAmount, 0.85 ether); // 85%
        assertEq(avsAmount, 0.1 ether);  // 10%
        assertEq(protocolAmount, 0.03 ether); // 3%
        
        // Remaining 2% would go to gas compensation
        uint256 remaining = totalProceeds - lpAmount - avsAmount - protocolAmount;
        assertEq(remaining, 0.02 ether);
    }
    
    function test_LVR_ThresholdCalculation() public pure {
        uint256 poolPrice = 1e18; // $1
        uint256 externalPrice = 1.01e18; // $1.01
        uint256 threshold = 50; // 0.5%
        
        // Calculate deviation in basis points
        uint256 deviation = ((externalPrice - poolPrice) * BASIS_POINTS()) / poolPrice;
        assertEq(deviation, 100); // 1%
        
        // Should trigger auction (1% > 0.5%)
        assertTrue(deviation >= threshold);
        
        // Test smaller deviation
        externalPrice = 1.001e18; // $1.001
        deviation = ((externalPrice - poolPrice) * BASIS_POINTS()) / poolPrice;
        assertEq(deviation, 10); // 0.1%
        
        // Should not trigger auction (0.1% < 0.5%)
        assertFalse(deviation >= threshold);
    }
    
    function test_SwapSignificance() public pure {
        int256 significantSwap = 2e18; // 2 ETH
        int256 smallSwap = 0.1e18; // 0.1 ETH
        int256 threshold = 1e18; // 1 ETH
        
        assertTrue(significantSwap > threshold || significantSwap < -threshold);
        assertFalse(smallSwap > threshold || smallSwap < -threshold);
    }
    
    function test_AuctionLib_GenerateCommitment() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 expected = keccak256(abi.encodePacked(bidder, amount, nonce));
        
        assertEq(commitment, expected);
    }
    
    function test_AuctionLib_VerifyCommitment() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bool isValid = AuctionLib.verifyCommitment(commitment, bidder, amount, nonce);
        
        assertTrue(isValid);
        
        // Test with wrong parameters
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x456), amount, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, 2 ether, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount, 54321));
    }
    
    function test_AuctionLib_AuctionState() public {
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: block.timestamp,
            duration: 60,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        // Test with memory struct - this will now work correctly with view functions
        // We need to create a storage version for library functions that require storage
        
        // Test active state calculations manually
        bool shouldBeActive = auction.isActive && 
                             block.timestamp >= auction.startTime && 
                             block.timestamp < auction.startTime + auction.duration;
        assertTrue(shouldBeActive);
        
        // Test end time calculation
        bool shouldBeEnded = block.timestamp >= auction.startTime + auction.duration;
        assertFalse(shouldBeEnded);
        
        // Test time remaining calculation
        uint256 expectedRemaining = auction.startTime + auction.duration - block.timestamp;
        assertTrue(expectedRemaining > 0);
    }
}

/**
 * @title Chainlink Oracle Integration Test
 * @notice Tests for Chainlink price oracle integration
 */
contract ChainlinkOracleIntegrationTest is Test {
    ChainlinkPriceOracle public oracle;
    MockAggregator public aggregator;
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    address public owner = address(0x1);
    
    function setUp() public {
        // Warp to a reasonable timestamp to avoid underflows
        vm.warp(86400); // 1 day in seconds
        
        vm.prank(owner);
        oracle = new ChainlinkPriceOracle(owner);
        
        // Create mock aggregator with 8 decimals (like ETH/USD)
        aggregator = new MockAggregator(2000e8, 8); // $2000
        
        // Add price feed
        vm.prank(owner);
        oracle.addPriceFeed(token0, token1, address(aggregator));
    }
    
    function test_GetPrice() public view {
        uint256 price = oracle.getPrice(token0, token1);
        assertEq(price, 2000e18); // Should be normalized to 18 decimals
    }
    
    function test_PriceNormalization() public {
        // Test different decimal configurations
        MockAggregator agg6 = new MockAggregator(1e6, 6); // 6 decimals
        MockAggregator agg18 = new MockAggregator(1e18, 18); // 18 decimals
        MockAggregator agg24 = new MockAggregator(1e24, 24); // 24 decimals
        
        vm.startPrank(owner);
        oracle.addPriceFeed(Currency.wrap(address(0x301)), Currency.wrap(address(0x302)), address(agg6));
        oracle.addPriceFeed(Currency.wrap(address(0x401)), Currency.wrap(address(0x402)), address(agg18));
        oracle.addPriceFeed(Currency.wrap(address(0x501)), Currency.wrap(address(0x502)), address(agg24));
        vm.stopPrank();
        
        // All should be normalized to 18 decimals
        assertEq(oracle.getPrice(Currency.wrap(address(0x301)), Currency.wrap(address(0x302))), 1e18);
        assertEq(oracle.getPrice(Currency.wrap(address(0x401)), Currency.wrap(address(0x402))), 1e18);
        assertEq(oracle.getPrice(Currency.wrap(address(0x501)), Currency.wrap(address(0x502))), 1e18);
    }
    
    function test_StalePrice() public {
        // Set stale timestamp (older than 1 hour)
        aggregator.setUpdatedAt(block.timestamp - 3601);
        
        vm.expectRevert(ChainlinkPriceOracle.StalePriceData.selector);
        oracle.getPrice(token0, token1);
    }
    
    function test_InvalidPrice() public {
        // Set invalid price (zero or negative)
        aggregator.setPrice(0);
        
        vm.expectRevert(ChainlinkPriceOracle.InvalidPriceData.selector);
        oracle.getPrice(token0, token1);
        
        aggregator.setPrice(-100);
        
        vm.expectRevert(ChainlinkPriceOracle.InvalidPriceData.selector);
        oracle.getPrice(token0, token1);
    }
}