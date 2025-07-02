// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title AuctionLib
 * @notice Library for auction data structures and utilities
 */
library AuctionLib {
    /**
     * @notice Auction state structure
     * @param poolId The pool ID this auction is for
     * @param startTime When the auction started
     * @param duration How long the auction runs for
     * @param isActive Whether the auction is currently active
     * @param isComplete Whether the auction has been completed
     * @param winner The winning bidder address
     * @param winningBid The winning bid amount
     * @param totalBids The total number of bids received
     */
    struct Auction {
        PoolId poolId;
        uint256 startTime;
        uint256 duration;
        bool isActive;
        bool isComplete;
        address winner;
        uint256 winningBid;
        uint256 totalBids;
    }

    /**
     * @notice Bid structure for sealed bids
     * @param bidder The address of the bidder
     * @param amount The bid amount
     * @param commitment The hash commitment of the bid
     * @param revealed Whether the bid has been revealed
     * @param timestamp When the bid was submitted
     */
    struct Bid {
        address bidder;
        uint256 amount;
        bytes32 commitment;
        bool revealed;
        uint256 timestamp;
    }

    /**
     * @notice Check if an auction is active
     * @param auction The auction to check
     * @return Whether the auction is active
     */
    function isAuctionActive(Auction storage auction) internal view returns (bool) {
        if (!auction.isActive) return false;
        
        // Handle potential overflow in startTime + duration
        if (auction.duration == type(uint256).max) {
            // Special case: infinite duration
            return block.timestamp >= auction.startTime;
        }
        
        // Safe addition check
        if (auction.startTime > type(uint256).max - auction.duration) {
            // Would overflow, so end time is effectively infinite
            return block.timestamp >= auction.startTime;
        }
        
        uint256 endTime = auction.startTime + auction.duration;
        return block.timestamp >= auction.startTime && block.timestamp < endTime;
    }

    /**
     * @notice Check if an auction has ended
     * @param auction The auction to check
     * @return Whether the auction has ended
     */
    function isAuctionEnded(Auction storage auction) internal view returns (bool) {
        // Handle potential overflow in startTime + duration
        if (auction.duration == type(uint256).max) {
            // Special case: infinite duration never ends
            return false;
        }
        
        // Safe addition check
        if (auction.startTime > type(uint256).max - auction.duration) {
            // Would overflow, so end time is effectively infinite
            return false;
        }
        
        return block.timestamp >= auction.startTime + auction.duration;
    }

    /**
     * @notice Calculate the time remaining in an auction
     * @param auction The auction to check
     * @return The time remaining in seconds
     */
    function getTimeRemaining(Auction storage auction) internal view returns (uint256) {
        if (!auction.isActive) return 0;
        
        // If auction hasn't started yet, return 0
        if (block.timestamp < auction.startTime) return 0;
        
        // Handle potential overflow in startTime + duration
        if (auction.duration == type(uint256).max) {
            // Special case: infinite duration
            if (block.timestamp >= auction.startTime) {
                return type(uint256).max;
            } else {
                return 0;
            }
        }
        
        // Safe addition check
        if (auction.startTime > type(uint256).max - auction.duration) {
            // Would overflow, so end time is effectively infinite
            // But only if we're past the start time
            if (block.timestamp >= auction.startTime) {
                return type(uint256).max;
            } else {
                return 0;
            }
        }
        
        uint256 endTime = auction.startTime + auction.duration;
        if (block.timestamp >= endTime) return 0;
        
        // Safe subtraction (we know block.timestamp < endTime)
        return endTime - block.timestamp;
    }

    /**
     * @notice Generate a bid commitment hash
     * @param bidder The bidder address
     * @param amount The bid amount
     * @param nonce A random nonce for privacy
     * @return The commitment hash
     */
    function generateCommitment(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bidder, amount, nonce));
    }

    /**
     * @notice Verify a bid commitment
     * @param commitment The stored commitment
     * @param bidder The bidder address
     * @param amount The bid amount
     * @param nonce The nonce used
     * @return Whether the commitment is valid
     */
    function verifyCommitment(
        bytes32 commitment,
        address bidder,
        uint256 amount,
        uint256 nonce
    ) internal pure returns (bool) {
        return commitment == generateCommitment(bidder, amount, nonce);
    }
}