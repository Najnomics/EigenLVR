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

// Integration test mocks
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
    mapping(address => mapping(address => uint256)) public operatorStake;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
        operatorStake[msg.sender][operator] = 1000 ether; // Default stake
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
        operatorStake[msg.sender][operator] = 0;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address avs, address operator) external view override returns (uint256) {
        return operatorStake[avs][operator];
    }
    
    function setOperatorStake(address avs, address operator, uint256 stake) external {
        operatorStake[avs][operator] = stake;
    }
}

/**
 * @title EigenLVR Integration Tests
 * @notice End-to-end integration tests for the complete EigenLVR system
 */
contract EigenLVRIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenLVRHook public hook;
    ChainlinkPriceOracle public priceOracle;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public lp = address(0x3);
    address public arbitrageur = address(0x4);
    address public feeRecipient = address(0x5);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%

    function setUp() public {
        // Deploy all contracts
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        
        vm.prank(owner);
        priceOracle = new ChainlinkPriceOracle(owner);
        
        // Calculate required hook permissions
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        // Mine valid hook address
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
        
        // Set up system
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        // Fund accounts
        vm.deal(address(hook), 100 ether);
        vm.deal(lp, 10 ether);
        vm.deal(arbitrageur, 10 ether);
        vm.deal(feeRecipient, 1 ether);
    }
    
    function test_FullSystemIntegration() public {
        // 1. Add liquidity
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp, poolKey, liquidityParams, "");
        
        assertEq(hook.lpLiquidity(poolId, lp), 1000e18);
        assertEq(hook.totalLiquidity(poolId), 1000e18);
        
        // 2. Since we're using a mock oracle, we'll simulate price update detection
        // In real implementation, this would come from Chainlink
        
        // 3. Simulate a significant swap that would trigger LVR detection
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // Significant amount
            sqrtPriceLimitX96: 0
        });
        
        // Note: With mock oracle returning constant price, LVR won't trigger
        // This test verifies the integration flow without price deviations
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        // Verify no auction was triggered (mock oracle returns constant price)
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertEq(auctionId, bytes32(0));
        
        // 4. Process after swap
        hook.afterSwap(address(this), poolKey, swapParams, BalanceDelta.wrap(0), "");
        
        // System should remain stable
        assertEq(hook.totalLiquidity(poolId), 1000e18);
    }
    
    function test_OperatorManagement() public {
        // Test operator registration and management
        address newOperator = address(0x123);
        
        // Register operator with AVS
        avsDirectory.registerOperatorToAVS(newOperator, "");
        assertTrue(avsDirectory.isOperatorRegistered(address(this), newOperator));
        
        // Authorize operator in hook
        vm.prank(owner);
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
        
        // Test stake management
        avsDirectory.setOperatorStake(address(this), newOperator, 5000 ether);
        assertEq(avsDirectory.getOperatorStake(address(this), newOperator), 5000 ether);
    }
    
    function test_EmergencyScenarios() public {
        // Add liquidity first
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        // Test emergency pause
        vm.prank(owner);
        hook.pause();
        
        // Verify operations are blocked when paused
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.expectRevert();
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        // Unpause and verify operations resume
        vm.prank(owner);
        hook.unpause();
        
        // Should work now
        hook.beforeSwap(address(this), poolKey, swapParams, "");
    }
    
    function test_GasOptimization() public {
        // Test gas usage for typical operations
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        uint256 gasBefore = gasleft();
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify reasonable gas usage (less than 100k gas)
        assertTrue(gasUsed < 100000);
        
        // Test swap gas usage
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        gasBefore = gasleft();
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        gasUsed = gasBefore - gasleft();
        
        // Verify reasonable swap gas usage
        assertTrue(gasUsed < 150000);
    }
    
    function test_RewardDistributionPrecision() public {
        // Test precision in reward calculations
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1337e18, // Odd number to test precision
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        // Fund the hook for reward distribution
        vm.deal(address(hook), 50 ether);
        
        // Manually set rewards to test precision
        uint256 rewardAmount = 1.23456789e18; // High precision amount
        
        vm.store(
            address(hook),
            keccak256(abi.encode(poolId, uint256(4))), // poolRewards slot
            bytes32(rewardAmount)
        );
        
        uint256 balanceBefore = lp.balance;
        
        vm.prank(lp);
        hook.claimRewards(poolId);
        
        uint256 balanceAfter = lp.balance;
        uint256 claimedAmount = balanceAfter - balanceBefore;
        
        // Verify we received the exact amount (LP has 100% of liquidity)
        assertEq(claimedAmount, rewardAmount);
    }
    
    function test_ConcurrentOperations() public {
        // Test multiple operations happening in sequence
        address lp1 = address(0x111);
        address lp2 = address(0x222);
        
        vm.deal(lp1, 10 ether);
        vm.deal(lp2, 10 ether);
        
        // Multiple LPs add liquidity
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
        
        // Verify total liquidity is correct
        assertEq(hook.totalLiquidity(poolId), 3000e18);
        assertEq(hook.lpLiquidity(poolId, lp1), 1000e18);
        assertEq(hook.lpLiquidity(poolId, lp2), 2000e18);
        
        // Multiple swaps
        SwapParams memory swap1 = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        SwapParams memory swap2 = SwapParams({
            zeroForOne: false,
            amountSpecified: 0.5e18,
            sqrtPriceLimitX96: 0
        });
        
        hook.beforeSwap(address(this), poolKey, swap1, "");
        hook.afterSwap(address(this), poolKey, swap1, BalanceDelta.wrap(0), "");
        
        hook.beforeSwap(address(this), poolKey, swap2, "");
        hook.afterSwap(address(this), poolKey, swap2, BalanceDelta.wrap(0), "");
        
        // System should remain consistent
        assertEq(hook.totalLiquidity(poolId), 3000e18);
    }
}