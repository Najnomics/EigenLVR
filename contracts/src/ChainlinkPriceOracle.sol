// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title ChainlinkPriceOracle
 * @notice Price oracle using Chainlink price feeds
 */
contract ChainlinkPriceOracle is IPriceOracle, Ownable {
    /// @notice Maximum allowed staleness for price data (1 hour)
    uint256 public constant MAX_PRICE_STALENESS = 3600;
    
    /// @notice Minimum valid price to prevent manipulation
    uint256 public constant MIN_VALID_PRICE = 1;
    
    /// @notice Maximum valid price to prevent manipulation (1 trillion in 18 decimals)
    uint256 public constant MAX_VALID_PRICE = 1e30;
    
    /// @notice Mapping of token pair to Chainlink price feeds
    mapping(bytes32 => AggregatorV3Interface) public priceFeeds;
    
    /// @notice Event emitted when a price feed is added
    event PriceFeedAdded(Currency token0, Currency token1, address priceFeed);
    
    /// @notice Event emitted when a price feed is removed
    event PriceFeedRemoved(Currency token0, Currency token1);
    
    /// @notice Error for when no price feed is configured
    error NoPriceFeedConfigured();
    
    /// @notice Error for invalid price data
    error InvalidPriceData();
    
    /// @notice Error for stale price data
    error StalePriceData();

    constructor(address _owner) Ownable(_owner) {}

    /**
     * @notice Add a price feed for a token pair
     * @param token0 First token
     * @param token1 Second token
     * @param priceFeed Chainlink price feed address
     */
    function addPriceFeed(
        Currency token0,
        Currency token1,
        address priceFeed
    ) external onlyOwner {
        require(priceFeed != address(0), "Invalid price feed address");
        
        bytes32 pairKey = _getPairKey(token0, token1);
        priceFeeds[pairKey] = AggregatorV3Interface(priceFeed);
        
        emit PriceFeedAdded(token0, token1, priceFeed);
    }

    /**
     * @notice Remove a price feed for a token pair
     * @param token0 First token
     * @param token1 Second token
     */
    function removePriceFeed(Currency token0, Currency token1) external onlyOwner {
        bytes32 pairKey = _getPairKey(token0, token1);
        delete priceFeeds[pairKey];
        
        emit PriceFeedRemoved(token0, token1);
    }

    /**
     * @notice Get current price for a token pair
     * @param token0 First token
     * @param token1 Second token
     * @return price The current price in 18 decimals
     */
    function getPrice(Currency token0, Currency token1) external view override returns (uint256 price) {
        bytes32 pairKey = _getPairKey(token0, token1);
        AggregatorV3Interface priceFeed = priceFeeds[pairKey];
        
        if (address(priceFeed) == address(0)) {
            revert NoPriceFeedConfigured();
        }
        
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        
        if (answer <= 0) {
            revert InvalidPriceData();
        }
        
        // Safe timestamp check to prevent underflow
        if (block.timestamp > updatedAt && (block.timestamp - updatedAt) > MAX_PRICE_STALENESS) {
            revert StalePriceData();
        }
        
        uint8 decimals = priceFeed.decimals();
        price = _normalizePrice(uint256(answer), decimals);
        
        // Validate price bounds
        if (price < MIN_VALID_PRICE || price > MAX_VALID_PRICE) {
            revert InvalidPriceData();
        }
    }

    /**
     * @notice Get price at a specific time (placeholder implementation)
     * @param token0 First token
     * @param token1 Second token
     * @return price The price at the specified time
     */
    function getPriceAtTime(
        Currency token0, 
        Currency token1, 
        uint256 /* timestamp */
    ) external view override returns (uint256 price) {
        // For simplicity, return current price
        // In production, this would query historical data
        return this.getPrice(token0, token1);
    }

    /**
     * @notice Check if price data is stale
     * @param token0 First token
     * @param token1 Second token
     * @return stale Whether the price data is stale
     */
    function isPriceStale(Currency token0, Currency token1) external view override returns (bool stale) {
        bytes32 pairKey = _getPairKey(token0, token1);
        AggregatorV3Interface priceFeed = priceFeeds[pairKey];
        
        if (address(priceFeed) == address(0)) {
            return true;
        }
        
        (, , , uint256 updatedAt, ) = priceFeed.latestRoundData();
        
        // Safe timestamp check to prevent underflow
        if (block.timestamp <= updatedAt) {
            return false;
        }
        
        return (block.timestamp - updatedAt) > MAX_PRICE_STALENESS;
    }

    /**
     * @notice Get the last update time for a price feed
     * @param token0 First token
     * @param token1 Second token
     * @return timestamp The last update timestamp
     */
    function getLastUpdateTime(Currency token0, Currency token1) external view override returns (uint256 timestamp) {
        bytes32 pairKey = _getPairKey(token0, token1);
        AggregatorV3Interface priceFeed = priceFeeds[pairKey];
        
        if (address(priceFeed) == address(0)) {
            return 0;
        }
        
        (, , , timestamp, ) = priceFeed.latestRoundData();
    }

    /**
     * @notice Generate a unique key for a token pair
     * @param token0 First token
     * @param token1 Second token
     * @return The unique pair key
     */
    function _getPairKey(Currency token0, Currency token1) internal pure returns (bytes32) {
        // Sort tokens to ensure consistent key regardless of order
        if (Currency.unwrap(token0) < Currency.unwrap(token1)) {
            return keccak256(abi.encodePacked(token0, token1));
        } else {
            return keccak256(abi.encodePacked(token1, token0));
        }
    }

    /**
     * @notice Normalize price to 18 decimals
     * @param price The raw price from Chainlink
     * @param decimals The number of decimals in the price feed
     * @return The normalized price
     */
    function _normalizePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return price;
        } else if (decimals < 18) {
            // Scale up to 18 decimals
            return price * (10 ** (18 - decimals));
        } else {
            // Scale down to 18 decimals
            return price / (10 ** (decimals - 18));
        }
    }
}