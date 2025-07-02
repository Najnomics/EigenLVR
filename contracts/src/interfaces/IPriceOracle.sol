// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title IPriceOracle
 * @notice Interface for price oracle to detect LVR opportunities
 */
interface IPriceOracle {
    /**
     * @notice Get the current price of a token pair
     * @param token0 The first token
     * @param token1 The second token
     * @return price The current price (token1/token0)
     */
    function getPrice(Currency token0, Currency token1) external view returns (uint256 price);

    /**
     * @notice Get the price at a specific timestamp
     * @param token0 The first token
     * @param token1 The second token
     * @param timestamp The timestamp to query
     * @return price The price at the given timestamp
     */
    function getPriceAtTime(
        Currency token0,
        Currency token1,
        uint256 timestamp
    ) external view returns (uint256 price);

    /**
     * @notice Check if price data is stale
     * @param token0 The first token
     * @param token1 The second token
     * @return isStale Whether the price data is stale
     */
    function isPriceStale(Currency token0, Currency token1) external view returns (bool isStale);

    /**
     * @notice Get the last update timestamp for a token pair
     * @param token0 The first token
     * @param token1 The second token
     * @return timestamp The last update timestamp
     */
    function getLastUpdateTime(Currency token0, Currency token1) external view returns (uint256 timestamp);
}