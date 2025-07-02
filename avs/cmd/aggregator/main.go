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
	"github.com/eigenlvr/avs/aggregator"
)

var (
	configFile = flag.String("config", "config/aggregator.yaml", "Path to aggregator config file")
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

	logger.Info("Starting EigenLVR Aggregator")

	// Load configuration
	config, err := loadConfig(*configFile)
	if err != nil {
		logger.Fatal("Failed to load config", "error", err)
	}

	// Create aggregator
	agg, err := aggregator.NewAggregator(config, logger)
	if err != nil {
		logger.Fatal("Failed to create aggregator", "error", err)
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

	// Start aggregator
	logger.Info("Starting aggregator with config",
		"serverAddr", config.ServerIpPortAddr,
		"ethRpcUrl", config.EthRpcUrl,
		"registryCoordinator", config.RegistryCoordinatorAddress,
	)

	if err := agg.Start(ctx); err != nil {
		logger.Fatal("Aggregator failed", "error", err)
	}

	logger.Info("Aggregator stopped gracefully")
}

func loadConfig(configPath string) (aggregator.Config, error) {
	var config aggregator.Config

	// Check if config file exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Use default config if file doesn't exist
		config = aggregator.Config{
			ServerIpPortAddr:              "localhost:8090",
			EthRpcUrl:                     "http://localhost:8545",
			RegistryCoordinatorAddress:    "0x0000000000000000000000000000000000000000",
			OperatorStateRetrieverAddress: "0x0000000000000000000000000000000000000000",
			AggregatorPrivateKeyPath:      "./keys/aggregator.ecdsa.key.json",
			EigenMetricsIpPortAddress:     "localhost:9092",
			EnableMetrics:                 true,
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