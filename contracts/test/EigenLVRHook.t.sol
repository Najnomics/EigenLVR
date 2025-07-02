// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TestEigenLVRHook} from "./TestEigenLVRHook.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

// Mock contracts for testing
contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) {
        return "";
    }
    function initialize(PoolKey memory, uint160) external pure returns (int24) {
        return 0;
    }
    function modifyLiquidity(PoolKey memory, ModifyLiquidityParams memory, bytes calldata) 
        external pure returns (BalanceDelta, BalanceDelta) {
        return (BalanceDelta.wrap(0), BalanceDelta.wrap(0));
    }
    function swap(PoolKey memory, SwapParams memory, bytes calldata) 
        external pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }
    function donate(PoolKey memory, uint256, uint256, bytes calldata) 
        external pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }
    function sync(Currency) external pure {}
    function take(Currency, address, uint256) external pure {}
    function settle(Currency) external payable returns (uint256) {
        return 0;
    }
    function settleFor(Currency, address) external payable returns (uint256) {
        return 0;
    }
    function clear(Currency, uint256) external pure {}
    function mint(address, uint256, uint256) external pure {}
    function burn(address, uint256, uint256) external pure {}
    function updateDynamicLPFee(PoolKey memory, uint24) external pure {}
}

contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => bool)) public operatorRegistered;
    mapping(address => mapping(address => uint256)) public operatorStakes;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address avs, address operator) external view override returns (uint256) {
        return operatorStakes[avs][operator];
    }
    
    function setOperatorStake(address avs, address operator, uint256 stake) external {
        operatorStakes[avs][operator] = stake;
    }
}

contract MockPriceOracle {
    mapping(bytes32 => uint256) public prices;
    mapping(bytes32 => bool) public stalePrices;
    
    function getPrice(Currency token0, Currency token1) external view returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        uint256 price = prices[key];
        return price > 0 ? price : 2000e18; // Default price 2000 USD
    }
    
    function setPrice(Currency token0, Currency token1, uint256 price) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        prices[key] = price;
    }
    
    function isPriceStale(Currency token0, Currency token1) external view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return stalePrices[key];
    }
    
    function setPriceStale(Currency token0, Currency token1, bool stale) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        stalePrices[key] = stale;
    }
    
    function getLastUpdateTime(Currency, Currency) external view returns (uint256) {
        return block.timestamp;
    }
    
    function getPriceAtTime(Currency token0, Currency token1, uint256) external view returns (uint256) {
        return this.getPrice(token0, token1);
    }
}

/**
 * @title Comprehensive EigenLVRHook Tests
 * @notice Tests all EigenLVRHook functions for 100% coverage
 */
contract EigenLVRHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    TestEigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public lp = address(0x3);
    address public feeRecipient = address(0x4);
    address public user = address(0x5);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%
    
    // Add payable receive function to handle ETH transfers
    receive() external payable {}

    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        // Deploy hook without address validation for testing
        vm.prank(owner);
        hook = new TestEigenLVRHook(
            IPoolManager(address(poolManager)),
            avsDirectory,
            IPriceOracle(address(priceOracle)),
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
        
        // Fund accounts
        vm.deal(address(hook), 100 ether);
        vm.deal(lp, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(operator, 5 ether);
        vm.deal(feeRecipient, 1 ether);
        
        // Set up oracle price
        priceOracle.setPrice(token0, token1, 2000e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public view {
        assertEq(address(hook.avsDirectory()), address(avsDirectory));
        assertEq(address(hook.priceOracle()), address(priceOracle));
        assertEq(hook.feeRecipient(), feeRecipient);
        assertEq(hook.lvrThreshold(), LVR_THRESHOLD);
        assertEq(hook.owner(), owner);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertTrue(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }
    
    /*//////////////////////////////////////////////////////////////
                            LIQUIDITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeAddLiquidity() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        bytes4 selector = hook.testBeforeAddLiquidity(lp, poolKey, params, "");
        
        assertEq(selector, hook.beforeAddLiquidity.selector);
        assertEq(hook.lpLiquidity(poolId, lp), 1000e18);
        assertEq(hook.totalLiquidity(poolId), 1000e18);
    }
    
    function test_BeforeAddLiquidity_ZeroLiquidity() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 0,
            salt: bytes32(0)
        });
        
        hook.testBeforeAddLiquidity(lp, poolKey, params, "");
        
        assertEq(hook.lpLiquidity(poolId, lp), 0);
        assertEq(hook.totalLiquidity(poolId), 0);
    }
    
    function test_BeforeAddLiquidity_MultipleLPs() public {
        address lp2 = address(0x6);
        
        ModifyLiquidityParams memory params1 = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        ModifyLiquidityParams memory params2 = ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 500e18,
            salt: bytes32(0)
        });
        
        hook.testBeforeAddLiquidity(lp, poolKey, params1, "");
        hook.testBeforeAddLiquidity(lp2, poolKey, params2, "");
        
        assertEq(hook.lpLiquidity(poolId, lp), 1000e18);
        assertEq(hook.lpLiquidity(poolId, lp2), 500e18);
        assertEq(hook.totalLiquidity(poolId), 1500e18);
    }
    
    function test_BeforeRemoveLiquidity() public {
        // First add liquidity
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        hook.testBeforeAddLiquidity(lp, poolKey, addParams, "");
        
        // Then remove liquidity
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: -500e18,
            salt: bytes32(0)
        });
        
        bytes4 selector = hook.testBeforeRemoveLiquidity(lp, poolKey, removeParams, "");
        
        assertEq(selector, hook.beforeRemoveLiquidity.selector);
        assertEq(hook.lpLiquidity(poolId, lp), 500e18);
        assertEq(hook.totalLiquidity(poolId), 500e18);
    }
    
    function test_BeforeRemoveLiquidity_ZeroRemoval() public {
        // First add liquidity
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        hook.testBeforeAddLiquidity(lp, poolKey, addParams, "");
        
        // Try to remove zero liquidity
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 0,
            salt: bytes32(0)
        });
        
        hook.testBeforeRemoveLiquidity(lp, poolKey, removeParams, "");
        
        // Should remain unchanged
        assertEq(hook.lpLiquidity(poolId, lp), 1000e18);
        assertEq(hook.totalLiquidity(poolId), 1000e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SWAP TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeSwap_NoAuctionTrigger() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e17, // Small amount
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.testBeforeSwap(
            user, poolKey, params, ""
        );
        
        assertEq(selector, hook.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), BeforeSwapDelta.unwrap(BeforeSwapDeltaLibrary.ZERO_DELTA));
        assertEq(fee, 0);
        
        // No auction should be active
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    function test_BeforeSwap_TriggerAuction() public {
        // Set up conditions for auction trigger (significant swap + price deviation)
        // Set mock pool price to create deviation
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool price: 2000
        priceOracle.setPrice(token0, token1, 2100e18); // Oracle price: 2100 (5% deviation)
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // Significant amount
            sqrtPriceLimitX96: 0
        });
        
        hook.testBeforeSwap(user, poolKey, params, "");
        
        // Auction should be active
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0));
    }
    
    function test_BeforeSwap_Paused() public {
        vm.prank(owner);
        hook.pause();
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.expectRevert();
        hook.testBeforeSwap(user, poolKey, params, "");
    }
    
    function test_AfterSwap_NoActiveAuction() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 selector, int128 delta) = hook.testAfterSwap(
            user, poolKey, params, BalanceDelta.wrap(0), ""
        );
        
        assertEq(selector, hook.afterSwap.selector);
        assertEq(delta, 0);
    }
    
    function test_AfterSwap_WithCompletedAuction() public {
        // Create and complete an auction
        _createAndCompleteAuction();
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        uint256 initialBalance = address(hook).balance;
        
        hook.testAfterSwap(user, poolKey, params, BalanceDelta.wrap(0), "");
        
        // Auction should be cleared
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createAndCompleteAuction() internal {
        // Authorize operator
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        // Create auction by triggering a swap with price deviation
        hook.setMockPoolPrice(poolKey, 2000e18); // Pool price: 2000
        priceOracle.setPrice(token0, token1, 2100e18); // Oracle price: 2100 (5% deviation)
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        hook.testBeforeSwap(user, poolKey, params, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        // Fast forward past auction end and complete it
        vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
        
        address winner = address(0x777);
        uint256 winningBid = 5 ether;
        
        vm.prank(operator);
        hook.submitAuctionResult(auctionId, winner, winningBid);
    }
}