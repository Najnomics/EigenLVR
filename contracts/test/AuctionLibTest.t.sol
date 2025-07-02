// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

contract AuctionLibTest is Test {
    using AuctionLib for AuctionLib.Auction;
    
    AuctionLib.Auction auction;
    
    function setUp() public {
        auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: block.timestamp,
            duration: 3600, // 1 hour
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
    }
    
    function test_IsAuctionActive() public {
        assertTrue(auction.isAuctionActive());
        
        // Set auction as inactive
        auction.isActive = false;
        assertFalse(auction.isAuctionActive());
        
        // Reactivate auction
        auction.isActive = true;
        assertTrue(auction.isAuctionActive());
    }
    
    function test_IsAuctionEnded() public {
        assertFalse(auction.isAuctionEnded());
        
        // Move time forward past auction end
        vm.warp(block.timestamp + 3601);
        assertTrue(auction.isAuctionEnded());
    }
    
    function test_GetTimeRemaining() public {
        uint256 timeRemaining = auction.getTimeRemaining();
        assertEq(timeRemaining, 3600);
        
        // Move time forward 30 minutes
        vm.warp(block.timestamp + 1800);
        timeRemaining = auction.getTimeRemaining();
        assertEq(timeRemaining, 1800);
        
        // Move time forward past end
        vm.warp(block.timestamp + 3600);
        timeRemaining = auction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_GenerateCommitment() public {
        address bidder = address(0x1);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 expected = keccak256(abi.encodePacked(bidder, amount, nonce));
        
        assertEq(commitment, expected);
    }
    
    function test_VerifyCommitment() public {
        address bidder = address(0x1);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        assertTrue(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce + 1));
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x2), amount, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount + 1, nonce));
    }
    
    function test_AuctionOverflowSafety() public {
        // Test with maximum values to check overflow protection
        auction.startTime = type(uint256).max - 100;
        auction.duration = 200; // Would overflow
        
        // Since we're handling overflow as infinite duration,
        // the auction should be active if block.timestamp >= startTime
        // and should never end
        vm.warp(type(uint256).max - 50); // Set time past startTime
        assertTrue(auction.isAuctionActive());
        assertFalse(auction.isAuctionEnded());
    }
    
    function test_InfiniteDurationAuction() public {
        auction.duration = type(uint256).max;
        
        // Infinite duration auction should never end
        assertFalse(auction.isAuctionEnded());
        assertTrue(auction.isAuctionActive());
        assertEq(auction.getTimeRemaining(), type(uint256).max);
    }
    
    function test_FuzzCommitmentGeneration(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) public {
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        assertTrue(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce));
    }
    
    function test_FuzzCommitmentVerification(
        address bidder,
        uint256 amount,
        uint256 nonce,
        address wrongBidder,
        uint256 wrongAmount,
        uint256 wrongNonce
    ) public {
        vm.assume(
            bidder != wrongBidder || 
            amount != wrongAmount || 
            nonce != wrongNonce
        );
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        assertFalse(AuctionLib.verifyCommitment(commitment, wrongBidder, wrongAmount, wrongNonce));
    }
}