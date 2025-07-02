// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
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

contract MockPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory) {
        return data;
    }
}

contract MockAVSDirectory is IAVSDirectory {
    function registerOperatorToAVS(address, bytes calldata) external pure override {}
    function deregisterOperatorFromAVS(address) external pure override {}
    function isOperatorRegistered(address, address) external pure override returns (bool) { return true; }
    function getOperatorStake(address, address) external pure override returns (uint256) { return 1000 ether; }
}

contract MockPriceOracle is IPriceOracle {
    uint256 public price = 1e18;
    uint256 public lastUpdateTime = block.timestamp;
    
    function setPrice(uint256 newPrice) external {
        price = newPrice;
        lastUpdateTime = block.timestamp;
    }
    
    function getPrice(Currency, Currency) external view override returns (uint256) {
        return price;
    }
    
    function getPriceAtTime(
        Currency,
        Currency,
        uint256
    ) external view override returns (uint256) {
        return price;
    }
    
    function isPriceStale(Currency, Currency) external pure override returns (bool) {
        return false;
    }
    
    function getLastUpdateTime(Currency, Currency) external view override returns (uint256) {
        return lastUpdateTime;
    }
}

contract EigenLVRHookTest is Test {
    EigenLVRHook hook;
    MockPoolManager poolManager;
    MockAVSDirectory avsDirectory;
    MockPriceOracle priceOracle;
    
    address owner = address(0x1);
    address operator = address(0x2);
    address feeRecipient = address(0x3);
    uint256 constant LVR_THRESHOLD = 50; // 0.5%
    
    function setUp() public {
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        vm.prank(owner);
        // Deploy hook without address mining for now
        hook = new EigenLVRHook(
            IPoolManager(address(poolManager)),
            avsDirectory,
            priceOracle,
            feeRecipient,
            LVR_THRESHOLD
        );
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
    }
    
    function test_Deployment() public {
        assertEq(address(hook.avsDirectory()), address(avsDirectory));
        assertEq(address(hook.priceOracle()), address(priceOracle));
        assertEq(hook.feeRecipient(), feeRecipient);
        assertEq(hook.lvrThreshold(), LVR_THRESHOLD);
        assertTrue(hook.authorizedOperators(operator));
    }
    
    function test_HookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
    }
    
    function test_OperatorAuthorization() public {
        address newOperator = address(0x4);
        
        vm.prank(owner);
        hook.setOperatorAuthorization(newOperator, true);
        assertTrue(hook.authorizedOperators(newOperator));
        
        vm.prank(owner);
        hook.setOperatorAuthorization(newOperator, false);
        assertFalse(hook.authorizedOperators(newOperator));
    }
    
    function test_LVRThresholdUpdate() public {
        uint256 newThreshold = 100; // 1%
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        assertEq(hook.lvrThreshold(), newThreshold);
    }
    
    function test_LVRThresholdTooHigh() public {
        uint256 newThreshold = 1001; // >10%
        
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        hook.setLVRThreshold(newThreshold);
    }
    
    function test_PauseUnpause() public {
        vm.prank(owner);
        hook.pause();
        assertTrue(hook.paused());
        
        vm.prank(owner);
        hook.unpause();
        assertFalse(hook.paused());
    }
    
    function test_FeeRecipientUpdate() public {
        address newFeeRecipient = address(0x5);
        
        vm.prank(owner);
        hook.setFeeRecipient(newFeeRecipient);
        assertEq(hook.feeRecipient(), newFeeRecipient);
    }
    
    function test_OnlyOwnerFunctions() public {
        address nonOwner = address(0x6);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setOperatorAuthorization(operator, false);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setLVRThreshold(100);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.pause();
    }
}