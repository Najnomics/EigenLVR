// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TestEigenLVRHook} from "./TestEigenLVRHook.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

// Import mocks
import "./EigenLVRHook.t.sol";

/**
 * @title EigenLVRHook Auction and Internal Functions Tests
 * @notice Tests auction logic and internal functions for complete coverage
 */
contract EigenLVRHookAuctionTest is Test {
    using PoolIdLibrary for PoolKey;

    // Allow receiving ETH for testing
    receive() external payable {}

    TestEigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public lp = address(0x3);
    address public feeRecipient = address(0x4);
    address public user = address(0x5);
    address public winner = address(0x7);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    // Test with USD stablecoins
    Currency public USDC = Currency.wrap(0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e);
    Currency public USDT = Currency.wrap(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    Currency public DAI = Currency.wrap(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    Currency public WETH = Currency.wrap(address(0x300));
    
    PoolKey public poolKey;
    PoolKey public usdcPoolKey;
    PoolKey public usdtPoolKey;
    PoolKey public daiPoolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50;

    event AuctionStarted(bytes32 indexed auctionId, PoolId indexed poolId, uint256 startTime, uint256 duration);
    event AuctionEnded(bytes32 indexed auctionId, PoolId indexed poolId, address indexed winner, uint256 winningBid);
    event MEVDistributed(PoolId indexed poolId, uint256 totalAmount, uint256 lpAmount, uint256 avsAmount, uint256 protocolAmount);

    function setUp() public {
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        vm.prank(owner);
        hook = new TestEigenLVRHook(
            IPoolManager(address(poolManager)),
            avsDirectory,
            IPriceOracle(address(priceOracle)),
            feeRecipient,
            LVR_THRESHOLD
        );
        
        // Regular pool
        poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
        
        // USD stablecoin pools for price inversion testing
        usdcPoolKey = PoolKey({
            currency0: WETH,
            currency1: USDC,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        usdtPoolKey = PoolKey({
            currency0: USDT,
            currency1: WETH,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        daiPoolKey = PoolKey({
            currency0: WETH,
            currency1: DAI,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        vm.deal(address(hook), 100 ether);
        vm.deal(lp, 10 ether);
        vm.deal(operator, 5 ether);
        vm.deal(feeRecipient, 1 ether);
        vm.deal(winner, 20 ether);
        
        // Set up oracle prices
        priceOracle.setPrice(token0, token1, 2000e18);
        priceOracle.setPrice(WETH, USDC, 2000e18);
        priceOracle.setPrice(USDT, WETH, 2000e18);
        priceOracle.setPrice(WETH, DAI, 2000e18);
        
        // Authorize operator
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
    }
    
    /*//////////////////////////////////////////////////////////////
                            AUCTION LIFECYCLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AuctionLifecycle_Complete() public {
        // 1. Trigger auction
        bytes32 auctionId = _triggerAuction();
        assertTrue(auctionId != bytes32(0));
        
        // Check auction was started
        (
            PoolId auctionPoolId,
            uint256 startTime,
            uint256 duration,
            bool isActive,
            bool isComplete,
            address auctionWinner,
            uint256 winningBid,
            uint256 totalBids
        ) = hook.auctions(auctionId);
        
        assertEq(PoolId.unwrap(auctionPoolId), PoolId.unwrap(poolId));
        assertEq(startTime, block.timestamp);
        assertEq(duration, hook.MAX_AUCTION_DURATION());
        assertTrue(isActive);
        assertFalse(isComplete);
        assertEq(auctionWinner, address(0));
        assertEq(winningBid, 0);
        assertEq(totalBids, 0);
        
        // 2. Complete auction
        vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
        
        uint256 bidAmount = 10 ether;
        vm.deal(address(hook), bidAmount);
        
        vm.prank(operator);
        hook.testSubmitAuctionResult(auctionId, winner, bidAmount);
        
        // Check auction completion
        (, , , isActive, isComplete, auctionWinner, winningBid, ) = hook.auctions(auctionId);
        assertFalse(isActive);
        assertTrue(isComplete);
        assertEq(auctionWinner, winner);
        assertEq(winningBid, bidAmount);
        
        // 3. Process auction result via afterSwap
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        uint256 feeRecipientBalanceBefore = feeRecipient.balance;
        uint256 operatorBalanceBefore = operator.balance;
        
        vm.prank(operator);
        hook.testAfterSwap(user, poolKey, params, BalanceDelta.wrap(0), "");
        
        // Check MEV distribution
        uint256 lpAmount = (bidAmount * hook.LP_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 avsAmount = (bidAmount * hook.AVS_REWARD_PERCENTAGE()) / hook.BASIS_POINTS();
        uint256 protocolAmount = (bidAmount * hook.PROTOCOL_FEE_PERCENTAGE()) / hook.BASIS_POINTS();
        
        assertEq(hook.poolRewards(poolId), lpAmount * 2); // Updated twice in _updateLPRewards
        assertEq(feeRecipient.balance, feeRecipientBalanceBefore + protocolAmount);
        
        // Auction should be cleared
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    function test_AuctionTrigger_DuplicateAuction() public {
        // Create first auction
        _triggerAuction();
        
        // Try to create second auction for same pool
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        // This should not create a new auction (no revert, but no new auction either)
        // The beforeSwap will detect existing auction and not start new one
        hook.testBeforeSwap(user, poolKey, params, "");
        
        // Should still have the original auction
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0));
    }
    
    function test_ProcessAuctionResult_ZeroBid() public {
        bytes32 auctionId = _triggerAuction();
        
        vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
        
        // Submit zero bid
        vm.prank(operator);
        hook.testSubmitAuctionResult(auctionId, winner, 0);
        
        // Process via afterSwap
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        uint256 poolRewardsBefore = hook.poolRewards(poolId);
        
        hook.testAfterSwap(user, poolKey, params, BalanceDelta.wrap(0), "");
        
        // No rewards should be distributed for zero bid
        assertEq(hook.poolRewards(poolId), poolRewardsBefore);
        assertEq(hook.activeAuctions(poolId), bytes32(0)); // Still cleared
    }
    
    /*//////////////////////////////////////////////////////////////
                            PRICE LOGIC TESTS  
    //////////////////////////////////////////////////////////////*/
    
    function test_ShouldTriggerAuction_True() public {
        // Set up price deviation above threshold
        priceOracle.setPrice(token0, token1, 2100e18); // Oracle: 2100 USD
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool: 2000 USD = 5% deviation
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // Significant swap
            sqrtPriceLimitX96: 0
        });
        
        // Call beforeSwap which internally calls _shouldTriggerAuction
        hook.testBeforeSwap(user, poolKey, params, "");
        
        // Should have triggered auction
        assertTrue(hook.activeAuctions(poolId) != bytes32(0));
    }
    
    function test_ShouldTriggerAuction_False_SmallDeviation() public {
        // Set up small price deviation
        priceOracle.setPrice(token0, token1, 2005e18); // Oracle: 2005 USD  
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool: 2000 USD = 0.25% deviation (below 0.5% threshold)
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // Significant swap
            sqrtPriceLimitX96: 0
        });
        
        hook.testBeforeSwap(user, poolKey, params, "");
        
        // Should not trigger auction
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    function test_ShouldTriggerAuction_False_SmallSwap() public {
        // Set up large price deviation
        priceOracle.setPrice(token0, token1, 2100e18); // Oracle: 2100 USD
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool: 2000 USD = 5% deviation
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e17, // Small swap (0.1 ETH)
            sqrtPriceLimitX96: 0
        });
        
        hook.testBeforeSwap(user, poolKey, params, "");
        
        // Should not trigger auction due to small swap size
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    function test_IsSignificantSwap() public {
        // Test positive significant amount
        SwapParams memory params1 = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // > 1 ETH
            sqrtPriceLimitX96: 0
        });
        
        // Test negative significant amount  
        SwapParams memory params2 = SwapParams({
            zeroForOne: false,
            amountSpecified: -2e18, // < -1 ETH
            sqrtPriceLimitX96: 0
        });
        
        // Test insignificant amount
        SwapParams memory params3 = SwapParams({
            zeroForOne: true,
            amountSpecified: 5e17, // 0.5 ETH
            sqrtPriceLimitX96: 0
        });
        
        // Trigger with different swap sizes to test _isSignificantSwap indirectly
        priceOracle.setPrice(token0, token1, 2100e18); // Oracle: 2100 USD
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool: 2000 USD = 5% deviation
        
        // Significant positive
        hook.testBeforeSwap(user, poolKey, params1, "");
        assertTrue(hook.activeAuctions(poolId) != bytes32(0));
        
        // Clear auction for next test
        _clearAuction();
        
        // Significant negative  
        hook.testBeforeSwap(user, poolKey, params2, "");
        assertTrue(hook.activeAuctions(poolId) != bytes32(0));
        
        // Clear auction for next test
        _clearAuction();
        
        // Insignificant
        hook.testBeforeSwap(user, poolKey, params3, "");
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _triggerAuction() internal returns (bytes32) {
        priceOracle.setPrice(token0, token1, 2100e18); // Oracle: 2100 USD
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool: 2000 USD = 5% deviation
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        hook.testBeforeSwap(user, poolKey, params, "");
        
        return hook.activeAuctions(poolId);
    }
    
    function _clearAuction() internal {
        bytes32 auctionId = hook.activeAuctions(poolId);
        if (auctionId != bytes32(0)) {
            vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
            vm.prank(operator);
            hook.testSubmitAuctionResult(auctionId, winner, 1 ether);
            
            SwapParams memory params = SwapParams({
                zeroForOne: true,
                amountSpecified: 1e18,
                sqrtPriceLimitX96: 0
            });
            hook.testAfterSwap(user, poolKey, params, BalanceDelta.wrap(0), "");
        }
    }
}