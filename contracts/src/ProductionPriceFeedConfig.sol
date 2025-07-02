// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ChainlinkPriceOracle} from "./ChainlinkPriceOracle.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProductionPriceFeedConfig
 * @notice Configuration contract for setting up production Chainlink price feeds
 * @dev This contract manages the setup of price feeds across different networks
 */
contract ProductionPriceFeedConfig is Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice The price oracle contract
    ChainlinkPriceOracle public immutable priceOracle;
    
    /// @notice Mapping of network ID to whether it's configured
    mapping(uint256 => bool) public networkConfigured;
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Token configuration
    struct TokenConfig {
        address token;
        string symbol;
        uint8 decimals;
    }
    
    /// @notice Price feed configuration
    struct PriceFeedConfig {
        address token0;
        address token1;
        address priceFeed;
        string description;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event NetworkConfigured(uint256 indexed chainId, uint256 feedCount);
    event PriceFeedAdded(address indexed token0, address indexed token1, address priceFeed);
    event PriceFeedRemoved(address indexed token0, address indexed token1);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(ChainlinkPriceOracle _priceOracle) Ownable(msg.sender) {
        priceOracle = _priceOracle;
    }

    /*//////////////////////////////////////////////////////////////
                         NETWORK CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Configure price feeds for Ethereum Mainnet
     */
    function configureMainnet() public onlyOwner {
        require(!networkConfigured[1], "Mainnet already configured");
        
        // Common tokens on mainnet
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86a33e6441C4c27D3F50c9d6D14bDf12F4e6e;
        // address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // Unused for now
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        
        // Chainlink price feeds on mainnet
        address ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        address BTC_USD = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
        address USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        address DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
        
        // Configure major trading pairs
        _addPriceFeed(WETH, USDC, ETH_USD, "ETH/USD");
        _addPriceFeed(WBTC, USDC, BTC_USD, "BTC/USD");
        _addPriceFeed(USDC, DAI, USDC_USD, "USDC/USD");
        _addPriceFeed(DAI, USDC, DAI_USD, "DAI/USD");
        
        // Cross pairs (using derived prices)
        _addDerivedPriceFeed(WETH, WBTC, ETH_USD, BTC_USD, "ETH/BTC");
        _addDerivedPriceFeed(WETH, DAI, ETH_USD, DAI_USD, "ETH/DAI");
        
        networkConfigured[1] = true;
        emit NetworkConfigured(1, 6);
    }
    
    /**
     * @notice Configure price feeds for Sepolia testnet
     */
    function configureSepolia() public onlyOwner {
        require(!networkConfigured[11155111], "Sepolia already configured");
        
        // Common tokens on Sepolia
        address WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        address USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        address LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
        
        // Chainlink price feeds on Sepolia
        address ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        address LINK_USD = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
        address USDC_USD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
        
        // Configure testnet pairs
        _addPriceFeed(WETH, USDC, ETH_USD, "ETH/USD (Sepolia)");
        _addPriceFeed(LINK, USDC, LINK_USD, "LINK/USD (Sepolia)");
        _addPriceFeed(USDC, WETH, USDC_USD, "USDC/USD (Sepolia)");
        
        networkConfigured[11155111] = true;
        emit NetworkConfigured(11155111, 3);
    }
    
    /**
     * @notice Configure price feeds for Base
     */
    function configureBase() public onlyOwner {
        require(!networkConfigured[8453], "Base already configured");
        
        // Common tokens on Base
        address WETH = 0x4200000000000000000000000000000000000006;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
        
        // Chainlink price feeds on Base
        address ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
        address USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
        address DAI_USD = 0x591e79239a7d679378eC8c847e5038150364C78F;
        
        // Configure Base pairs
        _addPriceFeed(WETH, USDC, ETH_USD, "ETH/USD (Base)");
        _addPriceFeed(USDC, DAI, USDC_USD, "USDC/USD (Base)");
        _addPriceFeed(DAI, USDC, DAI_USD, "DAI/USD (Base)");
        
        networkConfigured[8453] = true;
        emit NetworkConfigured(8453, 3);
    }
    
    /**
     * @notice Configure price feeds for Arbitrum
     */
    function configureArbitrum() public onlyOwner {
        require(!networkConfigured[42161], "Arbitrum already configured");
        
        // Common tokens on Arbitrum
        address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
        address ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        
        // Chainlink price feeds on Arbitrum
        address ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        address USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        address ARB_USD = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6;
        address DAI_USD = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;
        
        // Configure Arbitrum pairs
        _addPriceFeed(WETH, USDC, ETH_USD, "ETH/USD (Arbitrum)");
        _addPriceFeed(ARB, USDC, ARB_USD, "ARB/USD (Arbitrum)");
        _addPriceFeed(USDC, DAI, USDC_USD, "USDC/USD (Arbitrum)");
        _addPriceFeed(DAI, USDC, DAI_USD, "DAI/USD (Arbitrum)");
        
        networkConfigured[42161] = true;
        emit NetworkConfigured(42161, 4);
    }

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION HELPERS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add a price feed configuration
     * @param token0 First token
     * @param token1 Second token
     * @param priceFeed Chainlink price feed address
     */
    function _addPriceFeed(
        address token0,
        address token1,
        address priceFeed,
        string memory /* description */
    ) internal {
        priceOracle.addPriceFeed(
            Currency.wrap(token0),
            Currency.wrap(token1),
            priceFeed
        );
        
        emit PriceFeedAdded(token0, token1, priceFeed);
    }
    
    /**
     * @notice Add derived price feed (for cross-pairs)
     * @param token0 First token
     * @param token1 Second token
     * @param feed0 Price feed for token0/USD
     * @param feed1 Price feed for token1/USD
     */
    function _addDerivedPriceFeed(
        address token0,
        address token1,
        address feed0,
        address feed1,
        string memory /* description */
    ) internal {
        // For derived prices, we use the USD feed of the quote token
        // The oracle will calculate the cross rate internally
        priceOracle.addPriceFeed(
            Currency.wrap(token0),
            Currency.wrap(token1),
            feed0 // Use token0's USD feed as the primary
        );
        
        emit PriceFeedAdded(token0, token1, feed0);
    }

    /*//////////////////////////////////////////////////////////////
                            MANUAL CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Manually add a price feed
     * @param token0 First token
     * @param token1 Second token
     * @param priceFeed Chainlink price feed address
     */
    function addCustomPriceFeed(
        address token0,
        address token1,
        address priceFeed
    ) external onlyOwner {
        _addPriceFeed(token0, token1, priceFeed, "Custom");
    }
    
    /**
     * @notice Remove a price feed
     * @param token0 First token
     * @param token1 Second token
     */
    function removePriceFeed(
        address token0,
        address token1
    ) external onlyOwner {
        priceOracle.removePriceFeed(
            Currency.wrap(token0),
            Currency.wrap(token1)
        );
        
        emit PriceFeedRemoved(token0, token1);
    }

    /*//////////////////////////////////////////////////////////////
                           AUTO CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Auto-configure for current network
     */
    function autoConfigureNetwork() external onlyOwner {
        _autoConfigureNetwork();
    }
    
    /**
     * @notice Check if current network is configured
     * @return Whether the current network has price feeds configured
     */
    function isCurrentNetworkConfigured() external view returns (bool) {
        return networkConfigured[block.chainid];
    }
    
    /**
     * @notice Get network name for current chain
     * @return The network name
     */
    function getCurrentNetworkName() external view returns (string memory) {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) return "Ethereum Mainnet";
        if (chainId == 11155111) return "Sepolia Testnet";
        if (chainId == 8453) return "Base";
        if (chainId == 42161) return "Arbitrum One";
        if (chainId == 31337) return "Localhost";
        
        return "Unknown Network";
    }

    /*//////////////////////////////////////////////////////////////
                            BULK OPERATIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Batch add multiple price feeds
     * @param configs Array of price feed configurations
     */
    function batchAddPriceFeeds(PriceFeedConfig[] calldata configs) external onlyOwner {
        for (uint256 i = 0; i < configs.length; i++) {
            PriceFeedConfig memory config = configs[i];
            _addPriceFeed(
                config.token0,
                config.token1,
                config.priceFeed,
                config.description
            );
        }
    }
    
    /**
     * @notice Emergency function to reconfigure all feeds for current network
     */
    function emergencyReconfigure() external onlyOwner {
        networkConfigured[block.chainid] = false;
        _autoConfigureNetwork();
    }
    
    /**
     * @notice Internal function to auto-configure network without ownership check
     */
    function _autoConfigureNetwork() internal {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) {
            configureMainnet();
        } else if (chainId == 11155111) {
            configureSepolia();
        } else if (chainId == 8453) {
            configureBase();
        } else if (chainId == 42161) {
            configureArbitrum();
        } else {
            revert("Unsupported network for auto-configuration");
        }
    }
}