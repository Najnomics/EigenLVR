# EigenLVR Deployment Guide

## Overview

This guide covers deploying the EigenLVR system across different environments.

## Prerequisites

### Software Requirements
- Node.js 18+
- Python 3.11+
- Go 1.21+
- Docker (optional)
- Foundry for smart contract deployment

### Network Requirements
- Ethereum RPC access (Infura, Alchemy, etc.)
- Access to EigenLayer contracts
- Chainlink price feed access

## Environment Setup

### 1. Local Development

```bash
# Clone and install dependencies
git clone <repository>
cd eigenlvr

# Install frontend dependencies
cd frontend && yarn install

# Install backend dependencies  
cd ../backend && pip install -r requirements.txt

# Install AVS dependencies
cd ../avs && go mod download

# Start services
./scripts/start.sh
```

### 2. Testnet Deployment

#### Smart Contracts

```bash
cd contracts

# Set environment variables
export SEPOLIA_RPC_URL="https://sepolia.infura.io/v3/YOUR_KEY"
export PRIVATE_KEY="0x..."
export ETHERSCAN_API_KEY="..."

# Deploy contracts
forge script script/DeployEigenLVR.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify
```

#### AVS Operators

```bash
cd avs

# Configure operator
cp config/operator.yaml.example config/operator.yaml
# Edit config/operator.yaml with your settings

# Generate keys (for testnet only)
# In production, use secure key generation
go run cmd/cli/main.go generate-keys

# Start operator
go run cmd/operator/main.go --config config/operator.yaml
```

#### AVS Aggregator

```bash
# Configure aggregator
cp config/aggregator.yaml.example config/aggregator.yaml
# Edit config/aggregator.yaml with your settings

# Start aggregator
go run cmd/aggregator/main.go --config config/aggregator.yaml
```

### 3. Production Deployment

#### Security Considerations

1. **Key Management**
   - Use hardware security modules (HSMs)
   - Implement key rotation
   - Never store private keys in code

2. **Network Security**
   - Use VPNs for operator communication
   - Implement DDoS protection
   - Monitor for suspicious activity

3. **Smart Contract Security**
   - Complete security audits
   - Formal verification
   - Bug bounty programs
   - Emergency pause mechanisms

#### Infrastructure

```yaml
# docker-compose.production.yml
version: '3.8'
services:
  frontend:
    build: ./frontend
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - REACT_APP_BACKEND_URL=https://api.eigenlvr.com
    
  backend:
    build: ./backend
    ports:
      - "8001:8001"
    environment:
      - DATABASE_URL=mongodb://mongo:27017/eigenlvr
      - ENVIRONMENT=production
    
  operator:
    build: ./avs
    command: ["./operator"]
    volumes:
      - ./keys:/app/keys:ro
      - ./config:/app/config:ro
    
  aggregator:
    build: ./avs
    command: ["./aggregator"]
    volumes:
      - ./keys:/app/keys:ro
      - ./config:/app/config:ro
    
  mongo:
    image: mongo:7
    volumes:
      - mongo_data:/data/db
    
volumes:
  mongo_data:
```

## Monitoring and Maintenance

### Health Checks

```bash
# Backend health
curl https://api.eigenlvr.com/api/health

# Operator status
curl http://operator:9091/health

# Aggregator status  
curl http://aggregator:8090/health
```

### Logging

```bash
# View operator logs
docker logs eigenlvr_operator_1

# View aggregator logs
docker logs eigenlvr_aggregator_1

# View application logs
docker logs eigenlvr_backend_1
```

### Metrics

Access metrics at:
- Operator: `http://localhost:9090/metrics`
- Aggregator: `http://localhost:9092/metrics`
- Backend: `http://localhost:8001/metrics`

## Troubleshooting

### Common Issues

1. **RPC Connection Errors**
   - Check RPC URL configuration
   - Verify API key limits
   - Test network connectivity

2. **Key Generation Errors**
   - Ensure proper permissions
   - Check available entropy
   - Verify file paths

3. **Contract Deployment Failures**
   - Check gas prices
   - Verify network configuration
   - Ensure sufficient funds

4. **AVS Registration Issues**
   - Verify operator stake
   - Check EigenLayer contract addresses
   - Ensure proper signatures

### Debug Commands

```bash
# Check contract deployment
forge verify-contract <address> <contract> --chain sepolia

# Test operator registration
go run cmd/cli/main.go test-registration

# Validate aggregator connectivity
go run cmd/cli/main.go test-aggregator

# Check price oracle
go run cmd/cli/main.go test-oracle
```

## Rollback Procedures

### Smart Contract Rollback

```bash
# Emergency pause
cast send <hook_address> "pause()" --private-key $PRIVATE_KEY

# Upgrade proxy (if using upgradeable contracts)
cast send <proxy_address> "upgrade(address)" <new_implementation>
```

### AVS Rollback

```bash
# Stop operators gracefully
docker-compose stop operator aggregator

# Rollback to previous version
git checkout <previous_tag>
docker-compose up -d
```

## Performance Optimization

### Smart Contract Gas Optimization

1. Use `immutable` for constants
2. Pack structs efficiently
3. Batch operations when possible
4. Optimize storage layout

### AVS Performance

1. Implement connection pooling
2. Use efficient serialization
3. Optimize BLS signature verification
4. Cache frequently accessed data

### Frontend Optimization

1. Implement code splitting
2. Use React.memo for expensive components
3. Optimize bundle size
4. Implement proper caching

## Support

For deployment support:
- Documentation: [docs.eigenlvr.com](https://docs.eigenlvr.com)
- Discord: [discord.gg/eigenlvr](https://discord.gg/eigenlvr)
- Email: support@eigenlvr.com