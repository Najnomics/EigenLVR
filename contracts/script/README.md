# EigenLVR Deployment Scripts

This directory contains comprehensive deployment scripts for the EigenLVR protocol across different environments and use cases.

## 📁 Script Overview

### Core Deployment Scripts

| Script | Purpose | Use Case |
|--------|---------|----------|
| `BaseDeployment.s.sol` | Abstract base with common functionality | Foundation for all deployments |
| `SimpleDeployment.s.sol` | Basic deployment without address mining | Development & testing |
| `ProductionDeployment.s.sol` | Full production deployment with hook mining | Mainnet & production networks |
| `TestnetDeployment.s.sol` | Testnet deployment with mock tokens | Sepolia & other testnets |

### Specialized Scripts

| Script | Purpose | Use Case |
|--------|---------|----------|
| `UpgradeDeployment.s.sol` | Upgrade existing deployments | Contract upgrades & migrations |
| `EmergencyDeployment.s.sol` | Emergency deployment with safety features | Critical fixes & security updates |
| `MultiNetworkDeployment.s.sol` | Deploy across multiple networks | Cross-chain deployments |
| `DeploymentUtils.s.sol` | Utility functions for verification | Deployment management & monitoring |

## 🚀 Quick Start

### 1. Environment Setup

Create a `.env` file in the contracts directory:

```bash
# Required for all deployments
PRIVATE_KEY=0x...                    # Deployer private key
FEE_RECIPIENT=0x...                  # Optional: fee recipient address

# RPC URLs
MAINNET_RPC_URL=https://mainnet.infura.io/v3/...
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/...
BASE_RPC_URL=https://mainnet.base.org
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc

# Etherscan API Keys
ETHERSCAN_API_KEY=...
BASESCAN_API_KEY=...
ARBISCAN_API_KEY=...

# Emergency deployment (optional)
EMERGENCY_PRIVATE_KEY=0x...
EMERGENCY_FEE_RECIPIENT=0x...
```

### 2. Simple Development Deployment

For local testing and development:

```bash
# Deploy to local network (Anvil)
forge script script/SimpleDeployment.s.sol --rpc-url local --broadcast

# Deploy to Sepolia testnet
forge script script/SimpleDeployment.s.sol --rpc-url sepolia --broadcast --verify
```

### 3. Production Deployment

For mainnet and production networks:

```bash
# Deploy to mainnet with proper hook address mining
forge script script/ProductionDeployment.s.sol \
  --rpc-url mainnet \
  --broadcast \
  --verify \
  --gas-estimate-multiplier 120

# Deploy to Base
forge script script/ProductionDeployment.s.sol \
  --rpc-url base \
  --broadcast \
  --verify
```

### 4. Testnet Deployment

For comprehensive testnet setup with mock tokens:

```bash
# Deploy to Sepolia with mock tokens and test configuration
forge script script/TestnetDeployment.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

## 📋 Deployment Types Explained

### 🔧 SimpleDeployment

**Best for:** Local development, quick testing

**Features:**
- Basic contract deployment
- No hook address mining
- Minimal configuration
- Fast deployment

**Limitations:**
- May not work with actual Uniswap v4 (hook address validation)
- Basic configuration only

### 🏭 ProductionDeployment

**Best for:** Mainnet, production networks

**Features:**
- Proper hook address mining with CREATE2
- Full configuration setup
- Production-ready settings
- Comprehensive verification
- Etherscan verification

**Requirements:**
- Valid RPC endpoints
- Sufficient gas funds
- Etherscan API key for verification

### 🧪 TestnetDeployment

**Best for:** Sepolia, development testnets

**Features:**
- Mock token deployment
- Relaxed validation
- Test-specific configuration
- Pre-funded accounts
- Lower thresholds for testing

**Includes:**
- Mock WETH, USDC, DAI tokens
- Pre-authorized test operators
- Funded service manager
- Test-friendly settings

### 🔄 UpgradeDeployment

**Best for:** Contract upgrades, migrations

**Features:**
- Loads previous deployment data
- Migrates configuration
- Preserves operator authorizations
- Backup & restore functionality

**Usage:**
```bash
# Set old contract addresses
export OLD_HOOK_ADDRESS=0x...
export OLD_PRICE_ORACLE_ADDRESS=0x...

# Run upgrade
forge script script/UpgradeDeployment.s.sol --rpc-url mainnet --broadcast
```

### 🚨 EmergencyDeployment

**Best for:** Critical fixes, security updates

**Features:**
- Emergency pause by default
- Higher safety thresholds
- Restricted operator access
- Emergency-only configuration

**Usage:**
```bash
# Use emergency private key
export EMERGENCY_PRIVATE_KEY=0x...
export EMERGENCY_FEE_RECIPIENT=0x...

forge script script/EmergencyDeployment.s.sol --rpc-url mainnet --broadcast
```

### 🌐 MultiNetworkDeployment

**Best for:** Cross-chain deployments

**Features:**
- Consistent configuration across networks
- Coordinated deployment
- Cross-network summary
- Unified management

## 📊 Verification & Monitoring

### Contract Verification

Use the DeploymentUtils script for comprehensive verification:

```bash
# Verify deployment
forge script script/DeploymentUtils.s.sol:DeploymentUtils \
  --sig "verifyDeployment(address,address,address,address)" \
  0xHOOK 0xORACLE 0xSERVICE_MANAGER 0xPRICE_CONFIG \
  --rpc-url mainnet
```

### Health Checks

Monitor system health:

```bash
# Check system health
forge script script/DeploymentUtils.s.sol:DeploymentUtils \
  --sig "checkSystemHealth(address,address)" \
  0xHOOK 0xSERVICE_MANAGER \
  --rpc-url mainnet
```

### Generate Reports

Create deployment reports:

```bash
# Generate comprehensive report
forge script script/DeploymentUtils.s.sol:DeploymentUtils \
  --sig "generateDeploymentReport(address,address,address,address,address)" \
  0xHOOK 0xORACLE 0xSERVICE_MANAGER 0xPRICE_CONFIG 0xDEPLOYER \
  --rpc-url mainnet
```

## 🔧 Configuration Management

### Network Configuration

Network-specific settings are configured in `BaseDeployment.s.sol`:

- **Mainnet:** Production settings, higher stakes
- **Sepolia:** Testnet settings, lower stakes
- **Base/Arbitrum:** L2-optimized settings
- **Local:** Development settings

### Customizing Deployments

Override configuration by extending base contracts:

```solidity
contract CustomDeployment is ProductionDeployment {
    function _setupNetworkConfigs() internal override {
        // Custom network configuration
        networkConfigs[1337] = NetworkConfig({
            poolManager: 0x...,
            avsDirectory: 0x...,
            lvrThreshold: 100, // Custom threshold
            // ...
        });
    }
}
```

## 📁 Output Files

Deployments generate several output files in the `./deployments/` directory:

### Markdown Reports
- `{Network}_deployment_{timestamp}.md` - Human-readable deployment summary
- `multi-network-deployment.md` - Cross-network deployment summary

### JSON Files
- `{Network}_production.json` - Machine-readable deployment data
- `multi-network-deployment.json` - Cross-network deployment data

### Environment Files
- `.{Network}.env` - Frontend environment variables

## 🛡️ Security Considerations

### Private Key Management
- Never commit private keys to version control
- Use hardware wallets for mainnet deployments
- Consider multi-sig for production deployments

### Deployment Validation
- Always verify contracts on Etherscan
- Run verification scripts after deployment
- Monitor system health regularly
- Test on testnets first

### Emergency Procedures
- Keep emergency private keys secure
- Test emergency procedures on testnets
- Have rollback plans ready
- Monitor for unusual activity

## 🔍 Troubleshooting

### Common Issues

1. **Hook Address Validation Fails**
   - Use ProductionDeployment for proper address mining
   - Ensure sufficient gas for mining process

2. **Insufficient Gas**
   - Increase gas limit: `--gas-limit 10000000`
   - Use gas estimation multiplier: `--gas-estimate-multiplier 150`

3. **RPC Rate Limits**
   - Use premium RPC endpoints
   - Add delays between transactions
   - Use different RPC for verification

4. **Verification Failures**
   - Check constructor arguments match
   - Ensure contract is fully deployed
   - Wait for block confirmations

### Debug Commands

```bash
# Dry run deployment
forge script script/ProductionDeployment.s.sol --rpc-url mainnet

# Estimate gas
forge script script/ProductionDeployment.s.sol --rpc-url mainnet --gas-estimate

# Verbose output
forge script script/ProductionDeployment.s.sol --rpc-url mainnet -vvvv
```

## 📞 Support

For deployment support:
- Check the technical documentation
- Review test results in `test_result.md`
- Submit issues with deployment logs
- Use testnet deployments for debugging

---

**⚠️ Important:** Always test deployments on testnets before deploying to mainnet. Ensure you have sufficient funds for gas costs and that all environment variables are properly configured.