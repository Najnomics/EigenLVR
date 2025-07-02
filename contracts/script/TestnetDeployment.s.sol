// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./BaseDeployment.s.sol";

// Simple mock ERC20 for testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function initialize(string memory _name, string memory _symbol, uint8 _decimals) external {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

/**
 * @title TestnetDeployment
 * @notice Testnet deployment with mock tokens and relaxed validation
 * @dev Use this for Sepolia and other testnets
 */
contract TestnetDeployment is BaseDeployment {
    
    /// @notice Deployed mock tokens
    mapping(string => address) public mockTokens;
    
    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);
        
        require(isNetworkSupported(), "Network not supported");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock tokens if needed
        _deployMockTokens();
        
        DeploymentResult memory result = deployAllContracts(deployer, feeRecipient);
        
        // Setup testnet-specific configuration
        _setupTestnetConfiguration(result);
        
        vm.stopBroadcast();
        
        logDeploymentSummary(result);
        _logTestnetInfo();
        saveDeploymentResults(result);
        
        return result;
    }
    
    /**
     * @notice Deploy mock tokens for testing
     */
    function _deployMockTokens() internal {
        console.log("\n=== Deploying Mock Tokens ===");
        
        // Deploy mock WETH
        MockERC20 mockWETH = new MockERC20();
        mockWETH.initialize("Wrapped Ether", "WETH", 18);
        mockTokens["WETH"] = address(mockWETH);
        console.log("Mock WETH deployed at:", address(mockWETH));
        
        // Deploy mock USDC
        MockERC20 mockUSDC = new MockERC20();
        mockUSDC.initialize("USD Coin", "USDC", 6);
        mockTokens["USDC"] = address(mockUSDC);
        console.log("Mock USDC deployed at:", address(mockUSDC));
        
        // Deploy mock DAI
        MockERC20 mockDAI = new MockERC20();
        mockDAI.initialize("Dai Stablecoin", "DAI", 18);
        mockTokens["DAI"] = address(mockDAI);
        console.log("Mock DAI deployed at:", address(mockDAI));
        
        // Mint initial tokens to deployer
        address deployer = tx.origin;
        mockWETH.mint(deployer, 1000 ether);
        mockUSDC.mint(deployer, 1000000 * 10**6); // 1M USDC
        mockDAI.mint(deployer, 1000000 ether); // 1M DAI
        
        console.log("Mock tokens minted to deployer:", deployer);
    }
    
    /**
     * @notice Deploy hook for testnet (simplified)
     */
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        // Use predictable salt for testnet
        bytes32 salt = keccak256(abi.encodePacked("EigenLVR-Testnet", block.chainid));
        
        console.log("Deploying testnet hook with salt:", vm.toString(salt));
        
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            feeRecipient,
            config.lvrThreshold
        );
        
        return hook;
    }
    
    /**
     * @notice Setup testnet-specific configuration
     */
    function _setupTestnetConfiguration(DeploymentResult memory result) internal {
        console.log("\n=== Testnet Configuration ===");
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        ChainlinkPriceOracle oracle = ChainlinkPriceOracle(result.priceOracle);
        EigenLVRAVSServiceManager serviceManager = EigenLVRAVSServiceManager(payable(result.serviceManager));
        
        // Lower LVR threshold for testing
        hook.setLVRThreshold(25); // 0.25%
        console.log("Set LVR threshold to 0.25% for testnet");
        
        // Fund service manager with more ETH for testing
        serviceManager.fundRewardPool{value: 5 ether}();
        console.log("Funded service manager with 5 ETH");
        
        // Add test operators
        address testOperator1 = address(0x1111111111111111111111111111111111111111);
        address testOperator2 = address(0x2222222222222222222222222222222222222222);
        
        hook.setOperatorAuthorization(testOperator1, true);
        hook.setOperatorAuthorization(testOperator2, true);
        
        console.log("Authorized test operators:");
        console.log("- Operator 1:", testOperator1);
        console.log("- Operator 2:", testOperator2);
        
        // Setup mock price feeds if using mock tokens
        if (mockTokens["WETH"] != address(0)) {
            // Note: This would require mock price feeds in a real testnet scenario
            console.log("Mock tokens available for price feed setup");
        }
    }
    
    /**
     * @notice Log testnet-specific information
     */
    function _logTestnetInfo() internal view {
        console.log("\n=== Testnet Information ===");
        console.log("This is a TESTNET deployment!");
        console.log("Mock tokens deployed:");
        
        if (mockTokens["WETH"] != address(0)) {
            console.log("- WETH:", mockTokens["WETH"]);
            console.log("- USDC:", mockTokens["USDC"]);
            console.log("- DAI:", mockTokens["DAI"]);
        }
        
        console.log("");
        console.log("Testnet features:");
        console.log("- Lower LVR threshold (0.25%)");
        console.log("- Pre-authorized test operators");
        console.log("- Funded service manager (5 ETH)");
        console.log("- Mock tokens with initial supply");
        
        console.log("\nNext steps:");
        console.log("1. Setup frontend with deployed addresses");
        console.log("2. Configure price feeds for mock tokens");
        console.log("3. Test auction mechanisms");
        console.log("4. Register additional operators");
        console.log("===============================");
    }
    
    /**
     * @notice Get mock token addresses
     */
    function getMockTokens() external view returns (
        address weth,
        address usdc,
        address dai
    ) {
        return (mockTokens["WETH"], mockTokens["USDC"], mockTokens["DAI"]);
    }
}