// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TestEigenLVRHook} from "./TestEigenLVRHook.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

// Import mocks from the main test file
import "./EigenLVRHook.t.sol";

/**
 * @title EigenLVRHook Admin Functions Tests
 * @notice Tests admin functions and auction management for complete coverage
 */
contract EigenLVRHookAdminTest is Test {
    using PoolIdLibrary for PoolKey;

    TestEigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public lp = address(0x3);
    address public feeRecipient = address(0x4);
    address public user = address(0x5);
    address public nonOwner = address(0x6);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50;

    event OperatorAuthorized(address indexed operator, bool authorized);
    event LVRThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event AuctionStarted(bytes32 indexed auctionId, PoolId indexed poolId, uint256 startTime, uint256 duration);
    event AuctionEnded(bytes32 indexed auctionId, PoolId indexed poolId, address indexed winner, uint256 winningBid);
    event MEVDistributed(PoolId indexed poolId, uint256 totalAmount, uint256 lpAmount, uint256 avsAmount, uint256 protocolAmount);
    event RewardsClaimed(PoolId indexed poolId, address indexed lp, uint256 amount);

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
        
        poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
        
        vm.deal(address(hook), 100 ether);
        vm.deal(lp, 10 ether);
        vm.deal(operator, 5 ether);
        vm.deal(feeRecipient, 1 ether);
        
        priceOracle.setPrice(token0, token1, 2000e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetOperatorAuthorization() public {
        vm.expectEmit(true, false, false, true);
        emit OperatorAuthorized(operator, true);
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        assertTrue(hook.authorizedOperators(operator));
    }
    
    function test_SetOperatorAuthorization_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setOperatorAuthorization(operator, true);
    }
    
    function test_SetOperatorAuthorization_Deauthorize() public {
        // First authorize
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        assertTrue(hook.authorizedOperators(operator));
        
        // Then deauthorize
        vm.expectEmit(true, false, false, true);
        emit OperatorAuthorized(operator, false);
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, false);
        
        assertFalse(hook.authorizedOperators(operator));
    }
    
    function test_SetLVRThreshold() public {
        uint256 newThreshold = 100; // 1%
        
        vm.expectEmit(false, false, false, true);
        emit LVRThresholdUpdated(LVR_THRESHOLD, newThreshold);
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
    }
    
    function test_SetLVRThreshold_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setLVRThreshold(100);
    }
    
    function test_SetLVRThreshold_TooHigh() public {
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        hook.setLVRThreshold(1001); // > 10%
    }
    
    function test_SetLVRThreshold_MaxAllowed() public {
        vm.prank(owner);
        hook.setLVRThreshold(1000); // Exactly 10%
        
        assertEq(hook.lvrThreshold(), 1000);
    }
    
    function test_SetFeeRecipient() public {
        address newFeeRecipient = address(0x999);
        
        vm.prank(owner);
        hook.setFeeRecipient(newFeeRecipient);
        
        assertEq(hook.feeRecipient(), newFeeRecipient);
    }
    
    function test_SetFeeRecipient_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.setFeeRecipient(address(0x999));
    }
    
    function test_SetFeeRecipient_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("EigenLVR: invalid address");
        hook.setFeeRecipient(address(0));
    }
    
    function test_Pause() public {
        vm.prank(owner);
        hook.pause();
        
        assertTrue(hook.paused());
    }
    
    function test_Pause_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.pause();
    }
    
    function test_Unpause() public {
        // First pause
        vm.prank(owner);
        hook.pause();
        assertTrue(hook.paused());
        
        // Then unpause
        vm.prank(owner);
        hook.unpause();
        
        assertFalse(hook.paused());
    }
    
    function test_Unpause_OnlyOwner() public {
        vm.prank(owner);
        hook.pause();
        
        vm.prank(nonOwner);
        vm.expectRevert();
        hook.unpause();
    }
    
    /*//////////////////////////////////////////////////////////////
                            AUCTION MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SubmitAuctionResult() public {
        // Authorize operator
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        // Create auction by triggering a swap
        _createActiveAuction();
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        // Fast forward past auction end
        vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
        
        address winner = address(0x777);
        uint256 winningBid = 5 ether;
        
        vm.expectEmit(true, true, true, true);
        emit AuctionEnded(auctionId, poolId, winner, winningBid);
        
        vm.prank(operator);
        hook.submitAuctionResult(auctionId, winner, winningBid);
        
        // Check auction state
        (
            PoolId auctionPoolId,
            uint256 startTime,
            uint256 duration,
            bool isActive,
            bool isComplete,
            address auctionWinner,
            uint256 auctionWinningBid,
            uint256 totalBids
        ) = hook.auctions(auctionId);
        
        assertEq(PoolId.unwrap(auctionPoolId), PoolId.unwrap(poolId));
        assertFalse(isActive);
        assertTrue(isComplete);
        assertEq(auctionWinner, winner);
        assertEq(auctionWinningBid, winningBid);
    }
    
    function test_SubmitAuctionResult_UnauthorizedOperator() public {
        // Create auction first
        _createActiveAuction();
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
        
        vm.prank(nonOwner);
        vm.expectRevert("EigenLVR: unauthorized operator");
        hook.submitAuctionResult(auctionId, address(0x777), 5 ether);
    }
    
    function test_SubmitAuctionResult_InactiveAuction() public {
        bytes32 fakeAuctionId = keccak256("fake");
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        vm.prank(operator);
        vm.expectRevert("EigenLVR: auction not active");
        hook.testSubmitAuctionResult(fakeAuctionId, address(0x777), 5 ether);
    }
    
    function test_SubmitAuctionResult_AuctionNotEnded() public {
        // Create auction
        _createActiveAuction();
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        // Don't fast forward time - auction still active
        vm.prank(operator);
        vm.expectRevert("EigenLVR: auction not ended");
        hook.submitAuctionResult(auctionId, address(0x777), 5 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                            REWARDS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ClaimRewards() public {
        // Add liquidity first
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        hook.testBeforeAddLiquidity(lp, poolKey, addParams, "");
        
        // Manually set pool rewards for testing
        uint256 rewardAmount = 10 ether;
        hook.testSetPoolRewards(poolId, rewardAmount);
        
        uint256 balanceBefore = lp.balance;
        
        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(poolId, lp, rewardAmount);
        
        vm.prank(lp);
        hook.testClaimRewards(poolId);
        
        uint256 balanceAfter = lp.balance;
        assertEq(balanceAfter - balanceBefore, rewardAmount);
    }
    
    function test_ClaimRewards_NoLiquidity() public {
        vm.prank(user);
        vm.expectRevert("EigenLVR: no liquidity provided");
        hook.claimRewards(poolId);
    }
    
    function test_ClaimRewards_NoRewards() public {
        // Add liquidity but no rewards
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        hook.testBeforeAddLiquidity(lp, poolKey, addParams, "");
        
        uint256 balanceBefore = lp.balance;
        
        vm.prank(lp);
        hook.testClaimRewards(poolId);
        
        uint256 balanceAfter = lp.balance;
        assertEq(balanceAfter, balanceBefore); // No change
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createActiveAuction() internal {
        // Set mock pool price to trigger deviation
        hook.setMockPoolPrice(poolKey, 2000e18); // Same as oracle default
        
        // Set oracle price to create 5% deviation
        priceOracle.setPrice(token0, token1, 2100e18); // 5% deviation
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        hook.testBeforeSwap(user, poolKey, params, "");
    }
    
    /*//////////////////////////////////////////////////////////////
                            RECEIVE ETH TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ReceiveETH() public {
        uint256 amount = 5 ether;
        uint256 balanceBefore = address(hook).balance;
        
        (bool success, ) = address(hook).call{value: amount}("");
        assertTrue(success);
        
        assertEq(address(hook).balance, balanceBefore + amount);
    }
    
    /*//////////////////////////////////////////////////////////////
                            MODIFIER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_OnlyAuthorizedOperator_Modifier() public {
        // This is tested indirectly through submitAuctionResult tests
        // but we can test it explicitly here if needed
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        assertTrue(hook.authorizedOperators(operator));
        
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, false);
        assertFalse(hook.authorizedOperators(operator));
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public view {
        assertEq(hook.MIN_BID(), 1e15);
        assertEq(hook.MAX_AUCTION_DURATION(), 12);
        assertEq(hook.LP_REWARD_PERCENTAGE(), 8500);
        assertEq(hook.AVS_REWARD_PERCENTAGE(), 1000);
        assertEq(hook.PROTOCOL_FEE_PERCENTAGE(), 300);
        assertEq(hook.GAS_COMPENSATION_PERCENTAGE(), 200);
        assertEq(hook.BASIS_POINTS(), 10000);
    }
}