// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IAVSDirectory} from "./interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {AuctionLib} from "./libraries/AuctionLib.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
/**
 * @title EigenLVRHook
 * @author EigenLVR Team
 * @notice A Uniswap v4 Hook that mitigates Loss Versus Rebalancing (LVR) through 
 *         EigenLayer-powered sealed-bid auctions
 * @dev This hook intercepts swaps to run block-level auctions, redistributing MEV to LPs
 */
contract EigenLVRHook is BaseHook, ReentrancyGuard, Ownable, Pausable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using AuctionLib for AuctionLib.Auction;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Minimum bid amount (0.001 ETH)
    uint256 public constant MIN_BID = 1e15;
    
    /// @notice Maximum auction duration in seconds
    uint256 public constant MAX_AUCTION_DURATION = 12;
    
    /// @notice LP reward percentage (85%)
    uint256 public constant LP_REWARD_PERCENTAGE = 8500;
    
    /// @notice AVS operator reward percentage (10%)
    uint256 public constant AVS_REWARD_PERCENTAGE = 1000;
    
    /// @notice Protocol fee percentage (3%)
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 300;
    
    /// @notice Gas compensation percentage (2%)
    uint256 public constant GAS_COMPENSATION_PERCENTAGE = 200;
    
    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice EigenLayer AVS Directory for operator validation
    IAVSDirectory public immutable avsDirectory;
    
    /// @notice Price oracle for LVR detection
    IPriceOracle public immutable priceOracle;
    
    /// @notice Mapping of pool to active auctions
    mapping(PoolId => bytes32) public activeAuctions;
    
    /// @notice Mapping of auction ID to auction data
    mapping(bytes32 => AuctionLib.Auction) public auctions;
    
    /// @notice Mapping of pool to accumulated LP rewards
    mapping(PoolId => uint256) public poolRewards;
    
    /// @notice Mapping of LP to claimable rewards per pool
    mapping(PoolId => mapping(address => uint256)) public lpRewards;
    
    /// @notice Mapping of pool to total liquidity (for reward calculation)
    mapping(PoolId => uint256) public totalLiquidity;
    
    /// @notice Mapping of pool to LP liquidity positions
    mapping(PoolId => mapping(address => uint256)) public lpLiquidity;
    
    /// @notice Authorized AVS operators
    mapping(address => bool) public authorizedOperators;
    
    /// @notice Protocol fee recipient
    address public feeRecipient;
    
    /// @notice LVR threshold for triggering auctions (in basis points)
    uint256 public lvrThreshold;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event AuctionStarted(
        bytes32 indexed auctionId,
        PoolId indexed poolId,
        uint256 startTime,
        uint256 duration
    );
    
    event AuctionEnded(
        bytes32 indexed auctionId,
        PoolId indexed poolId,
        address indexed winner,
        uint256 winningBid
    );
    
    event MEVDistributed(
        PoolId indexed poolId,
        uint256 totalAmount,
        uint256 lpAmount,
        uint256 avsAmount,
        uint256 protocolAmount
    );
    
    event RewardsClaimed(
        PoolId indexed poolId,
        address indexed lp,
        uint256 amount
    );
    
    event OperatorAuthorized(address indexed operator, bool authorized);
    
    event LVRThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorizedOperator() {
        require(authorizedOperators[msg.sender], "EigenLVR: unauthorized operator");
        _;
    }
    
    modifier onlyActiveAuction(bytes32 auctionId) {
        require(auctions[auctionId].isActive, "EigenLVR: auction not active");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IPoolManager _poolManager,
        IAVSDirectory _avsDirectory,
        IPriceOracle _priceOracle,
        address _feeRecipient,
        uint256 _lvrThreshold
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        avsDirectory = _avsDirectory;
        priceOracle = _priceOracle;
        feeRecipient = _feeRecipient;
        lvrThreshold = _lvrThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Returns the hook's permissions
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /**
     * @notice Called before adding liquidity to track LP positions
     */
    function _beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        
        // Update LP liquidity tracking
        if (params.liquidityDelta > 0) {
            lpLiquidity[poolId][sender] += uint256(int256(params.liquidityDelta));
            totalLiquidity[poolId] += uint256(int256(params.liquidityDelta));
        }
        
        return this.beforeAddLiquidity.selector;
    }

    
    /**
     * @notice Called before removing liquidity to update LP positions
     */
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal override returns (bytes4) {
        PoolId poolId = key.toId();
        
        // Update LP liquidity tracking
        if (params.liquidityDelta < 0) {
            uint256 liquidityRemoved = uint256(-int256(params.liquidityDelta));
            lpLiquidity[poolId][sender] -= liquidityRemoved;
            totalLiquidity[poolId] -= liquidityRemoved;
        }
        
        return this.beforeRemoveLiquidity.selector;
    }
    
    /**
     * @notice Called before swap to potentially trigger LVR auction
     */
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override whenNotPaused returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        
        // Check if LVR threshold is exceeded
        if (_shouldTriggerAuction(key, params)) {
            _startAuction(poolId);
        }
        
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    
    /**
     * @notice Called after swap to handle auction results and distribute MEV
     */
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        bytes32 auctionId = activeAuctions[poolId];
        
        // Process completed auction if exists
        if (auctionId != bytes32(0) && auctions[auctionId].isComplete) {
            _processAuctionResult(poolId, auctionId);
        }
        
        return (this.afterSwap.selector, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           AUCTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Start a new auction for a pool
     * @param poolId The pool ID to auction
     */
    function _startAuction(PoolId poolId) internal {
        // Skip if there's already an active auction
        if (activeAuctions[poolId] != bytes32(0)) {
            return;
        }
        
        bytes32 auctionId = keccak256(abi.encodePacked(poolId, block.timestamp, block.number));
        
        // Create new auction
        auctions[auctionId] = AuctionLib.Auction({
            poolId: poolId,
            startTime: block.timestamp,
            duration: MAX_AUCTION_DURATION,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        activeAuctions[poolId] = auctionId;
        
        emit AuctionStarted(auctionId, poolId, block.timestamp, MAX_AUCTION_DURATION);
    }
    
    /**
     * @notice Submit auction result from AVS operators
     * @param auctionId The auction ID
     * @param winner The winning bidder
     * @param winningBid The winning bid amount
     */
    function submitAuctionResult(
        bytes32 auctionId,
        address winner,
        uint256 winningBid
    ) external onlyAuthorizedOperator onlyActiveAuction(auctionId) nonReentrant {
        AuctionLib.Auction storage auction = auctions[auctionId];
        
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
        
        emit AuctionEnded(auctionId, auction.poolId, winner, winningBid);
    }
    
    /**
     * @notice Process auction result and distribute MEV
     * @param poolId The pool ID
     * @param auctionId The auction ID
     */
    function _processAuctionResult(PoolId poolId, bytes32 auctionId) internal {
        AuctionLib.Auction storage auction = auctions[auctionId];
        uint256 totalProceeds = auction.winningBid;
        
        if (totalProceeds > 0) {
            // Calculate distribution amounts
            uint256 lpAmount = (totalProceeds * LP_REWARD_PERCENTAGE) / BASIS_POINTS;
            uint256 avsAmount = (totalProceeds * AVS_REWARD_PERCENTAGE) / BASIS_POINTS;
            uint256 protocolAmount = (totalProceeds * PROTOCOL_FEE_PERCENTAGE) / BASIS_POINTS;
            
            // Distribute to LPs
            poolRewards[poolId] += lpAmount;
            _updateLPRewards(poolId, lpAmount);
            
            // Transfer to AVS operators and protocol
            if (avsAmount > 0) {
                payable(msg.sender).transfer(avsAmount);
            }
            if (protocolAmount > 0) {
                payable(feeRecipient).transfer(protocolAmount);
            }
            
            emit MEVDistributed(poolId, totalProceeds, lpAmount, avsAmount, protocolAmount);
        }
        
        // Clear active auction
        activeAuctions[poolId] = bytes32(0);
    }
    
    /**
     * @notice Update LP rewards based on their liquidity share
     * @param poolId The pool ID
     * @param rewardAmount The total reward amount for LPs
     */
    function _updateLPRewards(PoolId poolId, uint256 rewardAmount) internal {
        // This is a simplified implementation
        // In production, you'd need to iterate through LP positions
        // For now, we'll accumulate rewards that can be claimed proportionally
        poolRewards[poolId] += rewardAmount;
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Claim accumulated LP rewards
     * @param poolId The pool ID
     */
    function claimRewards(PoolId poolId) external nonReentrant {
        uint256 userLiquidity = lpLiquidity[poolId][msg.sender];
        require(userLiquidity > 0, "EigenLVR: no liquidity provided");
        
        uint256 totalPool = totalLiquidity[poolId];
        uint256 poolRewardBalance = poolRewards[poolId];
        
        // Calculate user's share of rewards
        uint256 userReward = (poolRewardBalance * userLiquidity) / totalPool;
        
        if (userReward > 0) {
            lpRewards[poolId][msg.sender] += userReward;
            poolRewards[poolId] -= userReward;
            
            payable(msg.sender).transfer(userReward);
            
            emit RewardsClaimed(poolId, msg.sender, userReward);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Authorize or deauthorize AVS operators
     * @param operator The operator address
     * @param authorized Whether to authorize the operator
     */
    function setOperatorAuthorization(address operator, bool authorized) external onlyOwner {
        authorizedOperators[operator] = authorized;
        emit OperatorAuthorized(operator, authorized);
    }
    
    /**
     * @notice Update LVR threshold for auction triggering
     * @param newThreshold The new threshold in basis points
     */
    function setLVRThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold <= 1000, "EigenLVR: threshold too high"); // Max 10%
        uint256 oldThreshold = lvrThreshold;
        lvrThreshold = newThreshold;
        emit LVRThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /**
     * @notice Update fee recipient
     * @param newFeeRecipient The new fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "EigenLVR: invalid address");
        feeRecipient = newFeeRecipient;
    }
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if an auction should be triggered based on LVR
     * @param key The pool key
     * @param params The swap parameters
     * @return Whether to trigger an auction
     */
    function _shouldTriggerAuction(
        PoolKey calldata key,
        SwapParams calldata params
    ) internal view returns (bool) {
        // Get current pool price and external price
        uint256 poolPrice = _getPoolPrice(key);
        uint256 externalPrice = priceOracle.getPrice(key.currency0, key.currency1);
        
        // Handle edge cases
        if (poolPrice == 0 || externalPrice == 0) {
            return false;
        }
        
        // Calculate price deviation with overflow protection
        uint256 deviation;
        unchecked {
            if (poolPrice > externalPrice) {
                // Avoid overflow: check if (poolPrice - externalPrice) * BASIS_POINTS would overflow
                uint256 diff = poolPrice - externalPrice;
                if (diff > type(uint256).max / BASIS_POINTS) {
                    deviation = type(uint256).max; // Cap at max value
                } else {
                    deviation = (diff * BASIS_POINTS) / externalPrice;
                }
            } else {
                // Avoid overflow: check if (externalPrice - poolPrice) * BASIS_POINTS would overflow
                uint256 diff = externalPrice - poolPrice;
                if (diff > type(uint256).max / BASIS_POINTS) {
                    deviation = type(uint256).max; // Cap at max value
                } else {
                    deviation = (diff * BASIS_POINTS) / poolPrice;
                }
            }
        }
        
        // Check if deviation exceeds threshold and swap size is significant
        return deviation >= lvrThreshold && _isSignificantSwap(params);
    }
    
    /**
     * @notice Get current pool price from Uniswap v4 pool
     * @param key The pool key containing currency and fee information
     * @return The current pool price in 18 decimals
     */
    function _getPoolPrice(PoolKey calldata key) internal view virtual returns (uint256) {
        // In a real implementation, you would call:
        // (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        
        // For this implementation, we'll simulate getting the sqrt price
        // In production, integrate with actual Uniswap v4 PoolManager
        
        // Placeholder logic that attempts to get real price data
        // This would be replaced with actual pool manager calls
        uint160 sqrtPriceX96 = _getSqrtPriceFromPool(key);
        
        if (sqrtPriceX96 == 0) {
            // Fallback to oracle price if pool price is unavailable
            return priceOracle.getPrice(key.currency0, key.currency1);
        }
        
        // Convert sqrt price to regular price with overflow protection
        // sqrtPriceX96 = sqrt(price) * 2^96
        // price = (sqrtPriceX96 / 2^96)^2
        
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        
        // Calculate price with 18 decimal precision and overflow protection
        // Using bit shifting for efficiency: price = (sqrtPrice^2 * 10^18) / (2^192)
        uint256 price;
        unchecked {
            // Check for potential overflow before multiplication
            if (sqrtPrice > type(uint256).max / sqrtPrice) {
                // If overflow would occur, use a scaled calculation
                price = (sqrtPrice / 1e9) * (sqrtPrice / 1e9) * 1e18;
            } else {
                price = (sqrtPrice * sqrtPrice * 1e18) >> 192;
            }
        }
        
        // Handle token ordering - ensure consistent price direction
        if (_shouldInvertPrice(key.currency0, key.currency1)) {
            // Invert the price: 1/price = 10^36 / price
            if (price > 0) {
                price = (1e36) / price;
            }
        }
        
        return price;
    }
    
    /**
     * @notice Get sqrt price from pool (placeholder for actual implementation)
     * @return sqrtPriceX96 The sqrt price in X96 format
     */
    function _getSqrtPriceFromPool(PoolKey calldata /* key */) internal pure returns (uint160) {
        // PLACEHOLDER: In production, this would call:
        // (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        // return sqrtPriceX96;
        
        // For now, return 0 to indicate pool price is not available
        // This will trigger fallback to oracle price
        return 0;
    }
    
    /**
     * @notice Determine if price should be inverted based on token ordering convention
     * @param token0 The first token
     * @param token1 The second token
     * @return Whether to invert the price
     */
    function _shouldInvertPrice(Currency token0, Currency token1) internal pure returns (bool) {
        // Convention: We want consistent price direction regardless of token ordering
        // For most DeFi applications, we want USD-denominated prices
        
        // Example logic: If token1 is a USD stablecoin, don't invert
        // If token0 is a USD stablecoin, invert to get USD price
        
        address addr0 = Currency.unwrap(token0);
        address addr1 = Currency.unwrap(token1);
        
        // Common USD stablecoin addresses on mainnet
        address USDC = 0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e;
        address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        
        // If token1 is USD stablecoin, keep price as is (token1/token0)
        if (addr1 == USDC || addr1 == USDT || addr1 == DAI) {
            return false;
        }
        
        // If token0 is USD stablecoin, invert to get USD price (token0/token1)
        if (addr0 == USDC || addr0 == USDT || addr0 == DAI) {
            return true;
        }
        
        // Default: use address ordering (lower address as denominator)
        return addr0 < addr1;
    }
    
    /**
     * @notice Check if swap is significant enough to warrant auction
     * @param params The swap parameters
     * @return Whether the swap is significant
     */
    function _isSignificantSwap(SwapParams calldata params) internal pure returns (bool) {
        // Consider swaps above 1 ETH equivalent as significant
        return params.amountSpecified > 1e18 || params.amountSpecified < -1e18;
    }
    
    /**
     * @notice Receive ETH for auction payments
     */
    receive() external payable virtual {}
}