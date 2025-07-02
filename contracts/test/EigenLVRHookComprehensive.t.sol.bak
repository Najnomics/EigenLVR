// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

// Mock contracts (same as in EigenLVRHook.t.sol)
contract MockPoolManager {
    function swap(
        PoolKey calldata /* key */,
        SwapParams calldata /* params */,
        bytes calldata /* hookData */
    ) external pure returns (bytes4) {
        return bytes4(0);
    }
}

contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => bool)) public operatorRegistered;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address, address) external pure override returns (uint256) {
        return 1000 ether;
    }
}

contract MockPriceOracle is IPriceOracle {
    mapping(bytes32 => uint256) private prices;
    mapping(bytes32 => uint256) private updateTimes;
    
    function setPrice(Currency token0, Currency token1, uint256 price) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        prices[key] = price;
        updateTimes[key] = block.timestamp;
    }
    
    function getPrice(Currency token0, Currency token1) external view override returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        require(prices[key] != 0, "Price not set");
        return prices[key];
    }
    
    function getPriceAtTime(Currency token0, Currency token1, uint256) external view override returns (uint256) {
        return this.getPrice(token0, token1);
    }
    
    function isPriceStale(Currency, Currency) external pure override returns (bool) {
        return false;
    }
    
    function getLastUpdateTime(Currency token0, Currency token1) external view override returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return updateTimes[key];
    }
}

/**
 * @title Comprehensive EigenLVR Hook Tests
 * @notice Extended tests for EigenLVR hook functionality
 */
contract EigenLVRHookComprehensiveTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator1 = address(0x2);
    address public operator2 = address(0x3);
    address public lp1 = address(0x4);
    address public lp2 = address(0x5);
    address public arbitrageur = address(0x6);
    address public feeRecipient = address(0x7);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%

    function setUp() public {
        // Deploy mocks
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        // Calculate required flags for hook permissions
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        // Mine a valid hook address
        bytes memory constructorArgs = abi.encode(
            address(poolManager),
            address(avsDirectory),
            address(priceOracle),
            feeRecipient,
            LVR_THRESHOLD
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(EigenLVRHook).creationCode,
            constructorArgs
        );
        
        // Deploy hook
        vm.prank(owner);
        hook = new EigenLVRHook{salt: salt}(
            IPoolManager(address(poolManager)),
            avsDirectory,
            priceOracle,
            feeRecipient,
            LVR_THRESHOLD
        );
        
        // Set up pool key
        poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
        
        // Set up operators
        vm.prank(owner);
        hook.setOperatorAuthorization(operator1, true);
        vm.prank(owner);
        hook.setOperatorAuthorization(operator2, true);
        
        // Set initial prices
        priceOracle.setPrice(token0, token1, 1e18);
        
        // Fund accounts
        vm.deal(address(hook), 100 ether);
        vm.deal(lp1, 10 ether);
        vm.deal(lp2, 10 ether);
        vm.deal(arbitrageur, 10 ether);
    }
    
    function test_MultipleOperators() public {
        assertTrue(hook.authorizedOperators(operator1));
        assertTrue(hook.authorizedOperators(operator2));
        
        // Deauthorize one operator
        vm.prank(owner);
        hook.setOperatorAuthorization(operator1, false);
        
        assertFalse(hook.authorizedOperators(operator1));
        assertTrue(hook.authorizedOperators(operator2));
    }
    
    function test_MultipleLiquidityProviders() public {
        // Add liquidity from multiple LPs
        ModifyLiquidityParams memory params1 = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        ModifyLiquidityParams memory params2 = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 2000e18,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp1, poolKey, params1, "");
        hook.beforeAddLiquidity(lp2, poolKey, params2, "");
        
        assertEq(hook.lpLiquidity(poolId, lp1), 1000e18);
        assertEq(hook.lpLiquidity(poolId, lp2), 2000e18);
        assertEq(hook.totalLiquidity(poolId), 3000e18);
    }
    
    function test_CompleteAuctionFlow() public {
        // Add liquidity first
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp1, poolKey, liquidityParams, "");
        
        // Set price deviation to trigger auction
        priceOracle.setPrice(token0, token1, 1.1e18); // 10% increase
        
        // Trigger auction via swap
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0));
        
        // Fast forward past auction duration
        vm.warp(block.timestamp + 13);
        
        // Submit auction result
        uint256 winningBid = 2 ether;
        vm.prank(operator1);
        hook.submitAuctionResult(auctionId, arbitrageur, winningBid);
        
        // Process auction result via afterSwap
        hook.afterSwap(address(this), poolKey, swapParams, BalanceDelta.wrap(0), "");
        
        // Verify auction is completed and cleaned up
        bytes32 activeAuction = hook.activeAuctions(poolId);
        assertEq(activeAuction, bytes32(0));
        
        // Verify rewards were distributed
        uint256 poolRewardBalance = hook.poolRewards(poolId);
        uint256 expectedLPReward = (winningBid * 8500) / 10000; // 85%
        assertEq(poolRewardBalance, expectedLPReward);
    }
    
    function test_MultipleAuctionsSequential() public {
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp1, poolKey, liquidityParams, "");
        
        // First auction
        priceOracle.setPrice(token0, token1, 1.1e18);
        SwapParams memory swapParams1 = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        hook.beforeSwap(address(this), poolKey, swapParams1, "");
        bytes32 auctionId1 = hook.activeAuctions(poolId);
        
        vm.warp(block.timestamp + 13);
        vm.prank(operator1);
        hook.submitAuctionResult(auctionId1, arbitrageur, 1 ether);
        hook.afterSwap(address(this), poolKey, swapParams1, BalanceDelta.wrap(0), "");
        
        // Second auction after some time
        vm.warp(block.timestamp + 100);
        priceOracle.setPrice(token0, token1, 1.2e18);
        
        SwapParams memory swapParams2 = SwapParams({
            zeroForOne: true,
            amountSpecified: 3e18,
            sqrtPriceLimitX96: 0
        });
        
        hook.beforeSwap(address(this), poolKey, swapParams2, "");
        bytes32 auctionId2 = hook.activeAuctions(poolId);
        
        // Verify different auction IDs
        assertNotEq(auctionId1, auctionId2);
        
        vm.warp(block.timestamp + 13);
        vm.prank(operator2);
        hook.submitAuctionResult(auctionId2, arbitrageur, 2 ether);
        hook.afterSwap(address(this), poolKey, swapParams2, BalanceDelta.wrap(0), "");
        
        // Verify cumulative rewards
        uint256 totalRewards = hook.poolRewards(poolId);
        uint256 expectedTotal = ((1 ether + 2 ether) * 8500) / 10000;
        assertEq(totalRewards, expectedTotal);
    }
    
    function test_EmergencyPauseUnpause() public {
        // Test pause functionality
        vm.prank(owner);
        hook.pause();
        
        // Should prevent new auctions
        priceOracle.setPrice(token0, token1, 1.5e18);
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.expectRevert();
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        // Unpause and verify functionality restored
        vm.prank(owner);
        hook.unpause();
        
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0));
    }
    
    function test_RewardClaiming() public {
        // Set up liquidity
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp1, poolKey, params, "");
        
        // Simulate reward accumulation
        vm.deal(address(hook), 20 ether);
        
        // Manually set pool rewards for testing
        vm.store(
            address(hook),
            keccak256(abi.encode(poolId, uint256(4))), // poolRewards mapping slot
            bytes32(uint256(10 ether))
        );
        
        uint256 balanceBefore = lp1.balance;
        
        vm.prank(lp1);
        hook.claimRewards(poolId);
        
        uint256 balanceAfter = lp1.balance;
        assertTrue(balanceAfter > balanceBefore);
    }
    
    function test_LVRThresholdUpdates() public {
        // Test threshold updates
        uint256 newThreshold = 100; // 1%
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
        
        // Test with new threshold - smaller deviation should not trigger
        priceOracle.setPrice(token0, token1, 1.005e18); // 0.5% increase
        
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertEq(auctionId, bytes32(0)); // No auction triggered
        
        // Larger deviation should trigger
        priceOracle.setPrice(token0, token1, 1.02e18); // 2% increase
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0)); // Auction triggered
    }
    
    function test_FeeRecipientUpdates() public {
        address newFeeRecipient = address(0x999);
        
        vm.prank(owner);
        hook.setFeeRecipient(newFeeRecipient);
        
        assertEq(hook.feeRecipient(), newFeeRecipient);
    }
    
    function test_AccessControlOwnership() public {
        // Only owner should be able to call admin functions
        vm.prank(address(0x999));
        vm.expectRevert();
        hook.setOperatorAuthorization(address(0x888), true);
        
        vm.prank(address(0x999));
        vm.expectRevert();
        hook.setLVRThreshold(200);
        
        vm.prank(address(0x999));
        vm.expectRevert();
        hook.setFeeRecipient(address(0x777));
        
        vm.prank(address(0x999));
        vm.expectRevert();
        hook.pause();
    }
}