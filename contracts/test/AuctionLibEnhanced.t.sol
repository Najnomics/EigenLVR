// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title Enhanced AuctionLib Tests for 100% Coverage
 * @notice Tests all remaining edge cases and branch conditions in AuctionLib
 */
contract AuctionLibEnhancedTest is Test {
    using AuctionLib for AuctionLib.Auction;
    
    AuctionLib.Auction internal testAuction;
    
    function setUp() public {
        testAuction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: block.timestamp,
            duration: 60,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
    }
    
    /*//////////////////////////////////////////////////////////////
                    ENHANCED AUCTION ACTIVE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_IsAuctionActive_InfiniteDuration_BeforeStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp + 100; // Future start
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Not started yet, even with infinite duration
    }
    
    function test_IsAuctionActive_InfiniteDuration_AfterStart() public {
        testAuction.duration = type(uint256).max;
        // Use safe timestamp to avoid underflow
        testAuction.startTime = 1000;
        vm.warp(1100); // 100 seconds after start
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should be active with infinite duration
    }
    
    function test_IsAuctionActive_InfiniteDuration_AtStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp; // Exact start time
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should be active at exact start time
    }
    
    function test_IsAuctionActive_OverflowSafeEndTime_Active() public {
        // Set up conditions where startTime + duration would overflow
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100; // This would overflow
        
        // Warp to after start time for overflow protection to kick in
        vm.warp(type(uint256).max - 25); // After start time
        
        // But since we're past start time, should be active with "infinite" end
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive);
    }
    
    function test_IsAuctionActive_OverflowSafeEndTime_BeforeStart() public {
        // Set up overflow condition but before start time
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        // Move to before start time
        vm.warp(type(uint256).max - 100);
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Before start time
    }
    
    function test_IsAuctionActive_ExactOverflowBoundary() public {
        // Test exact overflow boundary
        testAuction.startTime = type(uint256).max - 10;
        testAuction.duration = 11; // Exactly overflow
        
        // Warp to after start time
        vm.warp(type(uint256).max - 5);
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should treat as infinite duration
    }
    
    /*//////////////////////////////////////////////////////////////
                    ENHANCED AUCTION ENDED TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_IsAuctionEnded_InfiniteDuration() public {
        testAuction.duration = type(uint256).max;
        
        // Even far in the future, infinite duration never ends
        vm.warp(type(uint256).max - 1);
        
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded);
    }
    
    function test_IsAuctionEnded_OverflowSafeEndTime() public {
        // Set up overflow condition
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded); // Overflow treated as infinite, so never ends
    }
    
    function test_IsAuctionEnded_ExactOverflowBoundary() public {
        testAuction.startTime = type(uint256).max - 10;
        testAuction.duration = 11; // Exactly at overflow boundary
        
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded); // Treated as infinite
    }
    
    function test_IsAuctionEnded_NoOverflow_JustEnded() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        // Move to exactly end time
        vm.warp(1500);
        
        bool isEnded = testAuction.isAuctionEnded();
        assertTrue(isEnded); // Should be ended at exact end time
    }
    
    function test_IsAuctionEnded_NoOverflow_JustBeforeEnd() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        // Move to just before end
        vm.warp(1499);
        
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded); // Not ended yet
    }
    
    /*//////////////////////////////////////////////////////////////
                    ENHANCED TIME REMAINING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetTimeRemaining_InfiniteDuration_BeforeStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp + 100;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0); // Not started yet
    }
    
    function test_GetTimeRemaining_InfiniteDuration_AfterStart() public {
        testAuction.duration = type(uint256).max;
        // Use a safe past timestamp to avoid underflow
        testAuction.startTime = 1000;
        vm.warp(1100); // 100 seconds after start
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Infinite time remaining
    }
    
    function test_GetTimeRemaining_InfiniteDuration_AtStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Infinite time remaining
    }
    
    function test_GetTimeRemaining_OverflowSafe_BeforeStart() public {
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        // Move to before start
        vm.warp(type(uint256).max - 100);
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0); // Not started
    }
    
    function test_GetTimeRemaining_OverflowSafe_AfterStart() public {
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        // Need to warp to after start time
        vm.warp(type(uint256).max - 25); // After start time
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Treated as infinite
    }
    
    function test_GetTimeRemaining_ExactOverflowBoundary() public {
        testAuction.startTime = type(uint256).max - 10;
        testAuction.duration = 11;
        
        // Need to warp to after start time for overflow protection to kick in
        vm.warp(type(uint256).max - 5); // After start time
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Overflow, treated as infinite
    }
    
    function test_GetTimeRemaining_NoOverflow_PartialTime() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        vm.warp(1200); // 200 seconds in, 300 remaining
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 300);
    }
    
    function test_GetTimeRemaining_NoOverflow_AtEnd() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        vm.warp(1500); // Exactly at end
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_GetTimeRemaining_NoOverflow_PastEnd() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        vm.warp(1600); // Past end
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                    BRANCH COVERAGE EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function test_IsAuctionActive_AllConditions() public {
        // Test the && condition branches
        
        // Case 1: isActive = false (first condition fails)
        testAuction.isActive = false;
        testAuction.startTime = 1000;
        testAuction.duration = 100;
        vm.warp(1050);
        
        assertFalse(testAuction.isAuctionActive());
        
        // Case 2: isActive = true, before start (second condition fails)
        testAuction.isActive = true;
        testAuction.startTime = 2000;
        testAuction.duration = 100;
        vm.warp(1900); // Before start
        
        assertFalse(testAuction.isAuctionActive());
        
        // Case 3: isActive = true, after end (third condition fails)
        testAuction.isActive = true;
        testAuction.startTime = 1000;
        testAuction.duration = 100;
        vm.warp(1200); // After end
        
        assertFalse(testAuction.isAuctionActive());
        
        // Case 4: All conditions true
        testAuction.isActive = true;
        testAuction.startTime = 1000;
        testAuction.duration = 100;
        vm.warp(1050); // During auction
        
        assertTrue(testAuction.isAuctionActive());
    }
    
    function test_TimeCalculation_BoundaryConditions() public {
        // Test exact boundaries for all time calculations
        
        uint256 currentTime = 1500; // Use fixed time
        vm.warp(currentTime);
        
        // Test startTime + duration = current time (boundary)
        testAuction.startTime = 1400; // currentTime - 100
        testAuction.duration = 100;
        
        // At exact end time
        assertFalse(testAuction.isAuctionActive()); // < endTime, so false at exact time
        assertTrue(testAuction.isAuctionEnded()); // >= endTime, so true at exact time
        assertEq(testAuction.getTimeRemaining(), 0);
        
        // Just before end time
        vm.warp(1499); // currentTime - 1
        assertTrue(testAuction.isAuctionActive());
        assertFalse(testAuction.isAuctionEnded());
        assertEq(testAuction.getTimeRemaining(), 1);
        
        // Just after end time
        vm.warp(1501); // currentTime + 1
        assertFalse(testAuction.isAuctionActive());
        assertTrue(testAuction.isAuctionEnded());
        assertEq(testAuction.getTimeRemaining(), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                    COMMITMENT EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function test_GenerateCommitment_AllZeros() public pure {
        bytes32 commitment = AuctionLib.generateCommitment(address(0), 0, 0);
        bytes32 expected = keccak256(abi.encodePacked(address(0), uint256(0), uint256(0)));
        assertEq(commitment, expected);
    }
    
    function test_GenerateCommitment_MaxValues() public pure {
        address maxAddr = address(type(uint160).max);
        uint256 maxUint = type(uint256).max;
        
        bytes32 commitment = AuctionLib.generateCommitment(maxAddr, maxUint, maxUint);
        bytes32 expected = keccak256(abi.encodePacked(maxAddr, maxUint, maxUint));
        assertEq(commitment, expected);
    }
    
    function test_VerifyCommitment_AllCombinations() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Valid combination
        assertTrue(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce));
        
        // Invalid bidder
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x456), amount, nonce));
        
        // Invalid amount
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount + 1, nonce));
        
        // Invalid nonce
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce + 1));
        
        // Multiple invalid parameters
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x456), amount + 1, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x456), amount, nonce + 1));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount + 1, nonce + 1));
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x456), amount + 1, nonce + 1));
    }
    
    function test_VerifyCommitment_WrongCommitmentFormat() public pure {
        // Test with completely wrong commitment hash
        bytes32 wrongCommitment = keccak256("totally wrong");
        
        assertFalse(AuctionLib.verifyCommitment(
            wrongCommitment, 
            address(0x123), 
            1 ether, 
            12345
        ));
    }
    
    /*//////////////////////////////////////////////////////////////
                    STRUCT VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AuctionStruct_AllFields() public {
        PoolId poolId = PoolId.wrap(bytes32(uint256(0x123)));
        uint256 startTime = 1234567890;
        uint256 duration = 3600;
        bool isActive = true;
        bool isComplete = false;
        address winner = address(0x456);
        uint256 winningBid = 5 ether;
        uint256 totalBids = 10;
        
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: poolId,
            startTime: startTime,
            duration: duration,
            isActive: isActive,
            isComplete: isComplete,
            winner: winner,
            winningBid: winningBid,
            totalBids: totalBids
        });
        
        assertEq(PoolId.unwrap(auction.poolId), PoolId.unwrap(poolId));
        assertEq(auction.startTime, startTime);
        assertEq(auction.duration, duration);
        assertEq(auction.isActive, isActive);
        assertEq(auction.isComplete, isComplete);
        assertEq(auction.winner, winner);
        assertEq(auction.winningBid, winningBid);
        assertEq(auction.totalBids, totalBids);
    }
    
    function test_BidStruct_AllFields() public {
        address bidder = address(0x789);
        uint256 amount = 2.5 ether;
        bytes32 commitment = keccak256("test commitment");
        bool revealed = true;
        uint256 timestamp = 1234567890;
        
        AuctionLib.Bid memory bid = AuctionLib.Bid({
            bidder: bidder,
            amount: amount,
            commitment: commitment,
            revealed: revealed,
            timestamp: timestamp
        });
        
        assertEq(bid.bidder, bidder);
        assertEq(bid.amount, amount);
        assertEq(bid.commitment, commitment);
        assertEq(bid.revealed, revealed);
        assertEq(bid.timestamp, timestamp);
    }
    
    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS FOR COMPREHENSIVE COVERAGE
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_IsAuctionActive_RandomTimes(
        uint128 startTime,
        uint128 duration,
        uint128 currentTime,
        bool isActive
    ) public {
        // Avoid overflow conditions for this fuzz test
        vm.assume(startTime < type(uint128).max - duration);
        vm.assume(duration > 0);
        
        testAuction.startTime = startTime;
        testAuction.duration = duration;
        testAuction.isActive = isActive;
        
        vm.warp(currentTime);
        
        bool expected = isActive && 
                       currentTime >= startTime && 
                       currentTime < startTime + duration;
        
        assertEq(testAuction.isAuctionActive(), expected);
    }
    
    function testFuzz_IsAuctionEnded_RandomTimes(
        uint128 startTime,
        uint128 duration,
        uint128 currentTime
    ) public {
        // Avoid overflow conditions
        vm.assume(startTime < type(uint128).max - duration);
        vm.assume(duration > 0);
        
        testAuction.startTime = startTime;
        testAuction.duration = duration;
        
        vm.warp(currentTime);
        
        bool expected = currentTime >= startTime + duration;
        
        assertEq(testAuction.isAuctionEnded(), expected);
    }
    
    function testFuzz_GetTimeRemaining_RandomTimes(
        uint128 startTime,
        uint128 duration,
        uint128 currentTime,
        bool isActive
    ) public {
        // Avoid overflow conditions
        vm.assume(startTime < type(uint128).max - duration);
        vm.assume(duration > 0);
        vm.assume(duration < type(uint128).max);
        
        testAuction.startTime = startTime;
        testAuction.duration = duration;
        testAuction.isActive = isActive;
        
        vm.warp(currentTime);
        
        uint256 result = testAuction.getTimeRemaining();
        
        if (!isActive) {
            assertEq(result, 0);
        } else if (currentTime < startTime) {
            // Auction hasn't started yet
            assertEq(result, 0);
        } else {
            uint256 endTime = startTime + duration;
            if (currentTime >= endTime) {
                assertEq(result, 0);
            } else {
                assertEq(result, endTime - currentTime);
            }
        }
    }
    
    function testFuzz_CommitmentGeneration(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) public pure {
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Should be deterministic
        assertEq(commitment1, commitment2);
        
        // Should verify correctly
        assertTrue(AuctionLib.verifyCommitment(commitment1, bidder, amount, nonce));
    }
    
    function testFuzz_CommitmentVerification_WrongInputs(
        address bidder,
        uint256 amount,
        uint256 nonce,
        address wrongBidder,
        uint256 wrongAmount,
        uint256 wrongNonce
    ) public pure {
        // Ensure at least one parameter is different
        vm.assume(bidder != wrongBidder || amount != wrongAmount || nonce != wrongNonce);
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Wrong parameters should fail verification
        assertFalse(AuctionLib.verifyCommitment(commitment, wrongBidder, wrongAmount, wrongNonce));
    }
}