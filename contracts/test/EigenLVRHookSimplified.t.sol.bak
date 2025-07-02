// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
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

// Simplified mock contracts
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
    function registerOperatorToAVS(address, bytes calldata) external pure override {}
    function deregisterOperatorFromAVS(address) external pure override {}
    function isOperatorRegistered(address, address) external pure override returns (bool) { return true; }
    function getOperatorStake(address, address) external pure override returns (uint256) { return 1000 ether; }
}

contract MockPriceOracle is IPriceOracle {
    uint256 private constant DEFAULT_PRICE = 1e18;
    
    function getPrice(Currency, Currency) external pure override returns (uint256) {
        return DEFAULT_PRICE;
    }
    
    function getPriceAtTime(Currency, Currency, uint256) external pure override returns (uint256) {
        return DEFAULT_PRICE;
    }
    
    function isPriceStale(Currency, Currency) external pure override returns (bool) {
        return false;
    }
    
    function getLastUpdateTime(Currency, Currency) external view override returns (uint256) {
        return block.timestamp;
    }
}

/**
 * @title Simplified EigenLVR Hook Tests
 * @notice Basic tests for EigenLVR hook deployment and permissions
 */
contract EigenLVRHookSimplifiedTest is Test {
    using PoolIdLibrary for PoolKey;

    EigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public feeRecipient = address(0x2);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%

    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
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
        
        // Verify deployment
        assertEq(address(hook), hookAddress);
        
        // Set up pool key
        poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
    }
    
    function test_BasicDeployment() public view {
        // Verify hook was deployed correctly
        assertEq(address(hook.avsDirectory()), address(avsDirectory));
        assertEq(address(hook.priceOracle()), address(priceOracle));
        assertEq(hook.feeRecipient(), feeRecipient);
        assertEq(hook.lvrThreshold(), LVR_THRESHOLD);
    }
    
    function test_HookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        // Verify required permissions are set
        assertTrue(permissions.beforeAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        
        // Verify unused permissions are not set
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
    }
    
    function test_BasicLiquidityOperations() public {
        address testLP = address(0x123);
        
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        // Test adding liquidity
        hook.beforeAddLiquidity(testLP, poolKey, params, "");
        
        assertEq(hook.lpLiquidity(poolId, testLP), 1000e18);
        assertEq(hook.totalLiquidity(poolId), 1000e18);
        
        // Test removing liquidity
        params.liquidityDelta = -500e18;
        hook.beforeRemoveLiquidity(testLP, poolKey, params, "");
        
        assertEq(hook.lpLiquidity(poolId, testLP), 500e18);
        assertEq(hook.totalLiquidity(poolId), 500e18);
    }
    
    function test_BasicSwapOperation() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        // Should not revert and return correct selector
        (bytes4 selector,,) = hook.beforeSwap(address(this), poolKey, params, "");
        assertEq(selector, hook.beforeSwap.selector);
        
        // After swap should also work
        (bytes4 afterSelector,) = hook.afterSwap(address(this), poolKey, params, BalanceDelta.wrap(0), "");
        assertEq(afterSelector, hook.afterSwap.selector);
    }
    
    function test_OwnershipFunctions() public {
        address newOperator = address(0x456);
        
        // Test operator authorization (only owner)
        vm.prank(owner);
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
        
        // Test threshold update (only owner)
        vm.prank(owner);
        hook.setLVRThreshold(100);
        assertEq(hook.lvrThreshold(), 100);
        
        // Test fee recipient update (only owner)
        address newFeeRecipient = address(0x789);
        vm.prank(owner);
        hook.setFeeRecipient(newFeeRecipient);
        assertEq(hook.feeRecipient(), newFeeRecipient);
    }
    
    function test_PauseUnpause() public {
        // Initially not paused
        assertFalse(hook.paused());
        
        // Only owner can pause
        vm.prank(owner);
        hook.pause();
        assertTrue(hook.paused());
        
        // Only owner can unpause
        vm.prank(owner);
        hook.unpause();
        assertFalse(hook.paused());
    }
    
    function test_ReceiveETH() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = address(hook).balance;
        
        // Send ETH to hook
        (bool success,) = address(hook).call{value: amount}("");
        assertTrue(success);
        
        assertEq(address(hook).balance, balanceBefore + amount);
    }
}