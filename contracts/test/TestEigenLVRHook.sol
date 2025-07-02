// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/**
 * @title Test version of EigenLVRHook that skips address validation
 * @notice This allows deployment to any address for testing purposes
 */
contract TestEigenLVRHook is EigenLVRHook {
    // Test variables to mock pool price
    mapping(bytes32 => uint256) public mockPoolPrices;
    
    // Allow receiving ETH for testing MEV distribution
    receive() external payable override {}
    
    constructor(
        IPoolManager _poolManager,
        IAVSDirectory _avsDirectory,
        IPriceOracle _priceOracle,
        address _feeRecipient,
        uint256 _lvrThreshold
    ) EigenLVRHook(
        _poolManager,
        _avsDirectory,
        _priceOracle,
        _feeRecipient,
        _lvrThreshold
    ) {}
    
    /// @dev Override to skip hook address validation during testing
    function validateHookAddress(BaseHook) internal pure override {
        // Skip validation for testing
    }
    
    /// @dev Set mock pool price for testing
    function setMockPoolPrice(PoolKey calldata key, uint256 price) external {
        bytes32 poolKey = keccak256(abi.encode(key.currency0, key.currency1, key.fee));
        mockPoolPrices[poolKey] = price;
    }
    
    /// @dev Override to return mock pool price if set
    function _getPoolPrice(PoolKey calldata key) internal view override returns (uint256) {
        bytes32 poolKey = keccak256(abi.encode(key.currency0, key.currency1, key.fee));
        uint256 mockPrice = mockPoolPrices[poolKey];
        if (mockPrice > 0) {
            return mockPrice;
        }
        // Fall back to parent implementation
        return super._getPoolPrice(key);
    }
    
    // Test wrapper functions that bypass the onlyPoolManager modifier
    function testBeforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4) {
        // Temporarily set the pool manager to this contract for testing
        return _beforeAddLiquidity(sender, key, params, hookData);
    }
    
    function testBeforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4) {
        return _beforeRemoveLiquidity(sender, key, params, hookData);
    }
    
    function testBeforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        return _beforeSwap(sender, key, params, hookData);
    }
    
    function testAfterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128) {
        return _afterSwap(sender, key, params, delta, hookData);
    }
    
    // Additional test wrapper functions to bypass onlyPoolManager checks
    function testClaimRewards(PoolId poolId) external {
        // Bypass authorization by calling the internal logic directly
        uint256 userLiquidity = lpLiquidity[poolId][msg.sender];
        require(userLiquidity > 0, "EigenLVR: no liquidity provided");
        
        uint256 totalPool = totalLiquidity[poolId];
        uint256 poolRewardBalance = poolRewards[poolId];
        
        if (poolRewardBalance > 0 && totalPool > 0) {
            uint256 userReward = (userLiquidity * poolRewardBalance) / totalPool;
            
            if (userReward > 0) {
                poolRewards[poolId] -= userReward;
                lpRewards[poolId][msg.sender] += userReward;
                
                payable(msg.sender).transfer(userReward);
                
                // Emit the event manually for testing
                emit RewardsClaimed(poolId, msg.sender, userReward);
            }
        }
    }
    
    function testSubmitAuctionResult(
        bytes32 auctionId,
        address winner,
        uint256 winningBid
    ) external {
        // Bypass authorization for testing by calling internal logic directly
        AuctionLib.Auction storage auction = auctions[auctionId];
        
        // Check auction is active
        require(auction.isActive, "EigenLVR: auction not active");
        
        // Skip timing validation for testing purposes
        // In real scenarios: require(block.timestamp >= auction.startTime + auction.duration, "EigenLVR: auction not ended");
        
        // Update auction state
        auction.winner = winner;
        auction.winningBid = winningBid;
        auction.isComplete = true;
        auction.isActive = false;
        
        // Emit event manually for testing
        emit AuctionEnded(auctionId, auction.poolId, winner, winningBid);
    }
    
    function testSubmitAuctionResultWithTimingCheck(
        bytes32 auctionId,
        address winner,
        uint256 winningBid
    ) external {
        // This version includes timing validation for specific tests
        AuctionLib.Auction storage auction = auctions[auctionId];
        
        // Check auction is active
        require(auction.isActive, "EigenLVR: auction not active");
        
        // Validate auction timing
        require(
            block.timestamp >= auction.startTime + auction.duration,
            "EigenLVR: auction not ended"
        );
        
        // Update auction state
        auction.winner = winner;
        auction.winningBid = winningBid;
        auction.isComplete = true;
        auction.isActive = false;
        
        // Emit event manually for testing
        emit AuctionEnded(auctionId, auction.poolId, winner, winningBid);
    }
    
    // Direct access functions for testing internal state
    function testSetPoolRewards(PoolId poolId, uint256 amount) external {
        poolRewards[poolId] = amount;
    }
    
    function testSetLpLiquidity(PoolId poolId, address lp, uint256 amount) external {
        lpLiquidity[poolId][lp] = amount;
    }
    
    function testSetTotalLiquidity(PoolId poolId, uint256 amount) external {
        totalLiquidity[poolId] = amount;
    }
    
    function testSetActiveAuction(PoolId poolId, bytes32 auctionId) external {
        activeAuctions[poolId] = auctionId;
    }
    
    function testCreateAuction(
        PoolId poolId,
        bytes32 auctionId,
        uint256 startTime,
        uint256 duration,
        bool isActive,
        bool isComplete
    ) external {
        auctions[auctionId] = AuctionLib.Auction({
            poolId: poolId,
            startTime: startTime,
            duration: duration,
            isActive: isActive,
            isComplete: isComplete,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
    }
}