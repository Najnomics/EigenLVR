package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/eigenlvr/avs/operator"
)

var (
	configFile = flag.String("config", "config/operator.yaml", "Path to operator config file")
	help       = flag.Bool("help", false, "Show help")
)

func main() {
	flag.Parse()

	if *help {
		flag.Usage()
		os.Exit(0)
	}

	logger, err := logging.NewZapLogger(logging.Development)
	if err != nil {
		log.Fatalf("Failed to create logger: %v", err)
	}

	logger.Info("Starting EigenLVR Operator")

	// Load configuration
	config, err := loadConfig(*configFile)
	if err != nil {
		logger.Fatal("Failed to load config", "error", err)
	}

	// Create operator
	op, err := operator.NewOperator(config, logger)
	if err != nil {
		logger.Fatal("Failed to create operator", "error", err)
	}

	// Set up context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigChan
		logger.Info("Received shutdown signal", "signal", sig)
		cancel()
	}()

	// Start operator
	logger.Info("Starting operator with config", 
		"ethRpcUrl", config.EthRpcUrl,
		"registryCoordinator", config.RegistryCoordinatorAddress,
		"aggregatorAddr", config.AggregatorServerIpPortAddr,
	)

	if err := op.Start(ctx); err != nil {
		logger.Fatal("Operator failed", "error", err)
	}

	logger.Info("Operator stopped gracefully")
}

func loadConfig(configPath string) (operator.Config, error) {
	var config operator.Config

	// Check if config file exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Use default config if file doesn't exist
		config = operator.Config{
			EcdsaPrivateKeyStorePath:      "./keys/operator.ecdsa.key.json",
			BlsPrivateKeyStorePath:        "./keys/operator.bls.key.json",
			EthRpcUrl:                     "http://localhost:8545",
			EthWsUrl:                      "ws://localhost:8546",
			RegistryCoordinatorAddress:    "0x0000000000000000000000000000000000000000",
			OperatorStateRetrieverAddress: "0x0000000000000000000000000000000000000000",
			AggregatorServerIpPortAddr:    "localhost:8090",
			RegisterOperatorOnStartup:     true,
			EigenMetricsIpPortAddress:     "localhost:9090",
			EnableMetrics:                 true,
			NodeApiIpPortAddress:          "localhost:9091",
			EnableNodeApi:                 true,
		}
		
		return config, nil
	}

	// Load from file
	file, err := os.Open(configPath)
	if err != nil {
		return config, fmt.Errorf("failed to open config file: %w", err)
	}
	defer file.Close()

	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&config); err != nil {
		return config, fmt.Errorf("failed to decode config: %w", err)
	}

	return config, nil
}