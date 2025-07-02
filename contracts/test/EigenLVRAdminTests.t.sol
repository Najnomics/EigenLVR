// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TestEigenLVRHook} from "./TestEigenLVRHook.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

// Mock contracts
contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) { return ""; }
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
    function getPrice(Currency, Currency) external pure returns (uint256) {
        return 2000e18;
    }
}

/**
 * @title EigenLVR Admin Function Tests
 * @notice Tests all admin functions for 100% coverage
 */
contract EigenLVRAdminTests is Test {
    TestEigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public feeRecipient = address(0x3);
    address public newFeeRecipient = address(0x4);
    address public nonOwner = address(0x5);
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%
    
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
    }
    
    /*//////////////////////////////////////////////////////////////
                            OPERATOR AUTHORIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetOperatorAuthorization_Success() public {
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        assertTrue(hook.authorizedOperators(operator));
    }
    
    function test_SetOperatorAuthorization_Unauthorized() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setOperatorAuthorization(operator, true);
    }
    
    function test_SetOperatorAuthorization_Event() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit OperatorAuthorized(operator, true);
        hook.setOperatorAuthorization(operator, true);
    }
    
    function test_SetOperatorAuthorization_Deauthorize() public {
        // First authorize
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        assertTrue(hook.authorizedOperators(operator));
        
        // Then deauthorize
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, false);
        assertFalse(hook.authorizedOperators(operator));
    }
    
    /*//////////////////////////////////////////////////////////////
                            LVR THRESHOLD TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetLVRThreshold_Success() public {
        uint256 newThreshold = 100; // 1%
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
    }
    
    function test_SetLVRThreshold_TooHigh() public {
        uint256 newThreshold = 1100; // 11% - too high
        
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        hook.setLVRThreshold(newThreshold);
    }
    
    function test_SetLVRThreshold_MaxValid() public {
        uint256 newThreshold = 1000; // 10% - max valid
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
    }
    
    function test_SetLVRThreshold_Unauthorized() public {
        uint256 newThreshold = 100;
        
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setLVRThreshold(newThreshold);
    }
    
    function test_SetLVRThreshold_Event() public {
        uint256 oldThreshold = hook.lvrThreshold();
        uint256 newThreshold = 100;
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit LVRThresholdUpdated(oldThreshold, newThreshold);
        hook.setLVRThreshold(newThreshold);
    }
    
    function test_SetLVRThreshold_Zero() public {
        vm.prank(owner);
        hook.setLVRThreshold(0);
        
        assertEq(hook.lvrThreshold(), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FEE RECIPIENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetFeeRecipient_Success() public {
        vm.prank(owner);
        hook.setFeeRecipient(newFeeRecipient);
        
        assertEq(hook.feeRecipient(), newFeeRecipient);
    }
    
    function test_SetFeeRecipient_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("EigenLVR: invalid address");
        hook.setFeeRecipient(address(0));
    }
    
    function test_SetFeeRecipient_Unauthorized() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setFeeRecipient(newFeeRecipient);
    }
    
    /*//////////////////////////////////////////////////////////////
                            PAUSE/UNPAUSE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Pause_Success() public {
        vm.prank(owner);
        hook.pause();
        
        assertTrue(hook.paused());
    }
    
    function test_Pause_Unauthorized() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.pause();
    }
    
    function test_Unpause_Success() public {
        // First pause
        vm.prank(owner);
        hook.pause();
        assertTrue(hook.paused());
        
        // Then unpause
        vm.prank(owner);
        hook.unpause();
        assertFalse(hook.paused());
    }
    
    function test_Unpause_Unauthorized() public {
        // First pause
        vm.prank(owner);
        hook.pause();
        
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.unpause();
    }
    
    function test_Pause_AlreadyPaused() public {
        vm.prank(owner);
        hook.pause();
        
        vm.prank(owner);
        vm.expectRevert();
        hook.pause();
    }
    
    function test_Unpause_AlreadyUnpaused() public {
        vm.prank(owner);
        vm.expectRevert();
        hook.unpause();
    }
    
    /*//////////////////////////////////////////////////////////////
                            MODIFIER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_OnlyAuthorizedOperator_Success() public {
        // Authorize operator first
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        // Create a test auction that's active
        bytes32 auctionId = _createTestAuction();
        
        // Should succeed with authorized operator
        vm.prank(operator);
        hook.submitAuctionResult(auctionId, address(0x123), 1 ether);
    }
    
    function test_OnlyAuthorizedOperator_Unauthorized() public {
        // Don't authorize operator
        
        // Create a test auction that's active
        bytes32 auctionId = _createTestAuction();
        
        // Should fail with unauthorized operator
        vm.prank(operator);
        vm.expectRevert("EigenLVR: unauthorized operator");
        hook.submitAuctionResult(auctionId, address(0x123), 1 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor_Owner() public view {
        assertEq(hook.owner(), owner);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createTestAuction() internal returns (bytes32) {
        // Create an auction ID
        bytes32 auctionId = keccak256(abi.encodePacked("test", block.timestamp, block.number));
        
        // Create a pool ID for the auction
        bytes32 poolIdBytes = keccak256(abi.encodePacked("test_pool", block.timestamp));
        
        // Create the auction using the TestEigenLVRHook helper
        uint256 startTime = block.timestamp; // Start now
        uint256 duration = 200; // Duration 
        
        hook.testCreateAuction(
            PoolId.wrap(poolIdBytes),
            auctionId,
            startTime,
            duration,
            true,  // isActive
            false  // isComplete
        );
        
        // Fast forward past auction end for submit
        vm.warp(startTime + duration + 1);
        
        return auctionId;
    }
    
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OperatorAuthorized(address indexed operator, bool authorized);
    event LVRThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
}