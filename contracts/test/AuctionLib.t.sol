// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title Comprehensive AuctionLib Tests
 * @notice Tests all AuctionLib functions with edge cases and boundary conditions
 */
contract AuctionLibTest is Test {
    using AuctionLib for AuctionLib.Auction;
    
    // Test state variables to simulate storage
    AuctionLib.Auction internal testAuction;
    
    function setUp() public {
        // Initialize test auction
        testAuction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: block.timestamp,
            duration: 60, // 1 minute
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
    }
    
    function test_AuctionStructInitialization() public view {
        assertEq(PoolId.unwrap(testAuction.poolId), bytes32(uint256(1)));
        assertEq(testAuction.startTime, block.timestamp);
        assertEq(testAuction.duration, 60);
        assertTrue(testAuction.isActive);
        assertFalse(testAuction.isComplete);
        assertEq(testAuction.winner, address(0));
        assertEq(testAuction.winningBid, 0);
        assertEq(testAuction.totalBids, 0);
    }
    
    function test_IsAuctionActive_DuringAuction() public view {
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive);
    }
    
    function test_IsAuctionActive_BeforeStart() public {
        // Create auction that starts in the future
        testAuction.startTime = block.timestamp + 100;
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Should not be active before start time
    }
    
    function test_IsAuctionActive_AfterEnd() public {
        // Fast forward past auction end
        vm.warp(block.timestamp + testAuction.duration + 1);
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Should not be active after end time
    }
    
    function test_IsAuctionActive_NotActiveFlag() public {
        testAuction.isActive = false;
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Should not be active when flag is false
    }
    
    function test_IsAuctionActive_AtExactStartTime() public {
        testAuction.startTime = block.timestamp;
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should be active at exact start time
    }
    
    function test_IsAuctionActive_AtExactEndTime() public {
        vm.warp(testAuction.startTime + testAuction.duration);
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Should not be active at exact end time
    }
    
    function test_IsAuctionEnded_BeforeEnd() public view {
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded);
    }
    
    function test_IsAuctionEnded_AfterEnd() public {
        vm.warp(block.timestamp + testAuction.duration + 1);
        
        bool isEnded = testAuction.isAuctionEnded();
        assertTrue(isEnded);
    }
    
    function test_IsAuctionEnded_AtExactEndTime() public {
        vm.warp(testAuction.startTime + testAuction.duration);
        
        bool isEnded = testAuction.isAuctionEnded();
        assertTrue(isEnded); // Should be ended at exact end time
    }
    
    function test_GetTimeRemaining_FullDuration() public view {
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 60);
    }
    
    function test_GetTimeRemaining_PartialDuration() public {
        vm.warp(block.timestamp + 20); // 20 seconds passed
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 40); // 40 seconds remaining
    }
    
    function test_GetTimeRemaining_AfterEnd() public {
        vm.warp(block.timestamp + testAuction.duration + 10);
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_GetTimeRemaining_InactiveAuction() public {
        testAuction.isActive = false;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_GetTimeRemaining_AtExactEndTime() public {
        vm.warp(testAuction.startTime + testAuction.duration);
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_GenerateCommitment() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 expected = keccak256(abi.encodePacked(bidder, amount, nonce));
        
        assertEq(commitment, expected);
    }
    
    function test_GenerateCommitment_DifferentInputs() public pure {
        address bidder1 = address(0x123);
        address bidder2 = address(0x456);
        uint256 amount1 = 1 ether;
        uint256 amount2 = 2 ether;
        uint256 nonce1 = 12345;
        uint256 nonce2 = 54321;
        
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder1, amount1, nonce1);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder2, amount2, nonce2);
        
        assertNotEq(commitment1, commitment2);
    }
    
    function test_GenerateCommitment_SameInputs() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        assertEq(commitment1, commitment2);
    }
    
    function test_GenerateCommitment_ZeroValues() public pure {
        bytes32 commitment = AuctionLib.generateCommitment(address(0), 0, 0);
        bytes32 expected = keccak256(abi.encodePacked(address(0), uint256(0), uint256(0)));
        
        assertEq(commitment, expected);
    }
    
    function test_GenerateCommitment_MaxValues() public pure {
        address bidder = address(type(uint160).max);
        uint256 amount = type(uint256).max;
        uint256 nonce = type(uint256).max;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 expected = keccak256(abi.encodePacked(bidder, amount, nonce));
        
        assertEq(commitment, expected);
    }
    
    function test_VerifyCommitment_Valid() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bool isValid = AuctionLib.verifyCommitment(commitment, bidder, amount, nonce);
        
        assertTrue(isValid);
    }
    
    function test_VerifyCommitment_InvalidBidder() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bool isValid = AuctionLib.verifyCommitment(commitment, address(0x456), amount, nonce);
        
        assertFalse(isValid);
    }
    
    function test_VerifyCommitment_InvalidAmount() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bool isValid = AuctionLib.verifyCommitment(commitment, bidder, 2 ether, nonce);
        
        assertFalse(isValid);
    }
    
    function test_VerifyCommitment_InvalidNonce() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bool isValid = AuctionLib.verifyCommitment(commitment, bidder, amount, 54321);
        
        assertFalse(isValid);
    }
    
    function test_VerifyCommitment_WrongCommitment() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 wrongCommitment = keccak256("wrong commitment");
        bool isValid = AuctionLib.verifyCommitment(wrongCommitment, bidder, amount, nonce);
        
        assertFalse(isValid);
    }
    
    function test_BidStruct() public {
        AuctionLib.Bid memory bid = AuctionLib.Bid({
            bidder: address(0x123),
            amount: 1 ether,
            commitment: keccak256("test"),
            revealed: false,
            timestamp: 1234567890 // Fixed timestamp
        });
        
        assertEq(bid.bidder, address(0x123));
        assertEq(bid.amount, 1 ether);
        assertEq(bid.commitment, keccak256("test"));
        assertFalse(bid.revealed);
        assertEq(bid.timestamp, 1234567890);
    }
    
    function test_AuctionTimingEdgeCases() public {
        // Test with zero duration
        testAuction.duration = 0;
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Should not be active with zero duration
        
        bool isEnded = testAuction.isAuctionEnded();
        assertTrue(isEnded); // Should be ended immediately
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_AuctionWithMaxDuration() public {
        testAuction.duration = type(uint256).max;
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive);
        
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded);
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max);
    }
    
    function test_AuctionStateTransitions() public {
        // Initially active
        assertTrue(testAuction.isAuctionActive());
        assertFalse(testAuction.isAuctionEnded());
        
        // Deactivate
        testAuction.isActive = false;
        assertFalse(testAuction.isAuctionActive());
        
        // Reactivate
        testAuction.isActive = true;
        assertTrue(testAuction.isAuctionActive());
        
        // Complete
        testAuction.isComplete = true;
        // Note: isComplete doesn't affect isAuctionActive() logic in the library
        assertTrue(testAuction.isAuctionActive());
    }
    
    function test_CommitmentCollisions() public pure {
        // Test that different inputs produce different commitments
        address bidder1 = address(0x123);
        address bidder2 = address(0x124);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder1, amount, nonce);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder2, amount, nonce);
        
        assertNotEq(commitment1, commitment2);
        
        // Test with amount variation
        bytes32 commitment3 = AuctionLib.generateCommitment(bidder1, amount + 1, nonce);
        assertNotEq(commitment1, commitment3);
        
        // Test with nonce variation
        bytes32 commitment4 = AuctionLib.generateCommitment(bidder1, amount, nonce + 1);
        assertNotEq(commitment1, commitment4);
    }
    
    function test_TimeArithmmeticEdgeCases() public {
        // Test startTime at block.timestamp boundary
        testAuction.startTime = block.timestamp;
        testAuction.duration = 100;
        
        assertTrue(testAuction.isAuctionActive());
        
        // Test with startTime in the past - use warp instead of subtraction
        uint256 currentTime = block.timestamp;
        testAuction.startTime = currentTime;
        testAuction.duration = 100;
        
        // Move forward 50 seconds
        vm.warp(currentTime + 50);
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 50); // Should have 50 seconds remaining
        
        // Test potential overflow scenarios
        testAuction.startTime = 1;
        testAuction.duration = type(uint256).max - 2; // Avoid overflow
        vm.warp(2); // Set current time to 2
        // Should not overflow when calculating end time
        bool isEnded = testAuction.isAuctionEnded();
        assertFalse(isEnded);
    }
    
    function test_FuzzCommitmentGeneration(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) public pure {
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Same inputs should always produce same commitment
        assertEq(commitment1, commitment2);
        
        // Verification should always work with correct inputs
        assertTrue(AuctionLib.verifyCommitment(commitment1, bidder, amount, nonce));
    }
    
    function test_FuzzCommitmentVerification(
        address bidder,
        uint256 amount,
        uint256 nonce,
        address wrongBidder,
        uint256 wrongAmount,
        uint256 wrongNonce
    ) public pure {
        vm.assume(bidder != wrongBidder || amount != wrongAmount || nonce != wrongNonce);
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Wrong inputs should fail verification
        assertFalse(AuctionLib.verifyCommitment(commitment, wrongBidder, wrongAmount, wrongNonce));
    }
}