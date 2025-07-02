package aggregator

import (
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/Layr-Labs/eigensdk-go/chainio/clients/eth"
	"github.com/Layr-Labs/eigensdk-go/logging"
	"github.com/Layr-Labs/eigensdk-go/types"
	"github.com/ethereum/go-ethereum/common"
	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"

	"github.com/eigenlvr/avs/pkg/avsregistry"
)

type Aggregator struct {
	config     Config
	logger     logging.Logger
	ethClient  eth.Client
	metricsReg *prometheus.Registry

	avsWriter avsregistry.AvsRegistryChainWriter
	avsReader avsregistry.AvsRegistryChainReader

	// Task aggregation
	tasksMutex    sync.RWMutex
	tasks         map[uint32]*TaskInfo
	httpServer    *http.Server
}

type Config struct {
	ServerIpPortAddr              string `json:"server_ip_port_address"`
	EthRpcUrl                     string `json:"eth_rpc_url"`
	RegistryCoordinatorAddress    string `json:"registry_coordinator_address"`
	OperatorStateRetrieverAddress string `json:"operator_state_retriever_address"`
	AggregatorPrivateKeyPath      string `json:"aggregator_private_key_path"`
	EigenMetricsIpPortAddress     string `json:"eigen_metrics_ip_port_address"`
	EnableMetrics                 bool   `json:"enable_metrics"`
}

type TaskInfo struct {
	TaskIndex                 uint32                           `json:"taskIndex"`
	PoolId                    common.Hash                      `json:"poolId"`
	TaskCreatedBlock          uint32                           `json:"taskCreatedBlock"`
	QuorumNumbers             types.QuorumNums                 `json:"quorumNumbers"`
	QuorumThresholdPercentage types.ThresholdPercentage        `json:"quorumThresholdPercentage"`
	TaskResponses             map[types.OperatorId]TaskResponse `json:"taskResponses"`
	TaskResponsesInfo         map[types.OperatorId]TaskResponseInfo `json:"taskResponsesInfo"`
	IsCompleted               bool                             `json:"isCompleted"`
	CreatedAt                 time.Time                        `json:"createdAt"`
}

type TaskResponse struct {
	ReferenceTaskIndex uint32         `json:"referenceTaskIndex"`
	Winner             common.Address `json:"winner"`
	WinningBid         *big.Int       `json:"winningBid"`
	TotalBids          uint32         `json:"totalBids"`
}

type TaskResponseInfo struct {
	TaskResponse TaskResponse        `json:"taskResponse"`
	BlsSignature types.Signature     `json:"blsSignature"`
	OperatorId   types.OperatorId    `json:"operatorId"`
}

type SignedTaskResponse struct {
	TaskResponse TaskResponse        `json:"taskResponse"`
	BlsSignature types.Signature     `json:"blsSignature"`
	OperatorId   types.OperatorId    `json:"operatorId"`
}

func NewAggregator(config Config, logger logging.Logger) (*Aggregator, error) {
	logger = logger.With("component", "aggregator")

	ethClient, err := eth.NewClient(config.EthRpcUrl)
	if err != nil {
		return nil, fmt.Errorf("failed to create eth client: %w", err)
	}

	// Create AVS registry clients
	avsReader, err := avsregistry.NewAvsRegistryChainReader(
		common.HexToAddress(config.RegistryCoordinatorAddress),
		common.HexToAddress(config.OperatorStateRetrieverAddress),
		ethClient,
		logger,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create avs registry chain reader: %w", err)
	}

	// For the writer, we'd need the aggregator's private key
	// For now, we'll skip this as it requires key management
	var avsWriter avsregistry.AvsRegistryChainWriter

	// Create metrics registry
	var metricsReg *prometheus.Registry
	if config.EnableMetrics {
		metricsReg = prometheus.NewRegistry()
	} else {
		metricsReg = prometheus.NewRegistry()
	}

	aggregator := &Aggregator{
		config:     config,
		logger:     logger,
		ethClient:  ethClient,
		metricsReg: metricsReg,
		avsWriter:  avsWriter,
		avsReader:  *avsReader,
		tasks:      make(map[uint32]*TaskInfo),
	}

	return aggregator, nil
}

func (a *Aggregator) Start(ctx context.Context) error {
	a.logger.Info("Starting aggregator")

	// Start HTTP server for receiving operator responses
	go a.startHttpServer()

	// Start task processing
	go a.processAggregatedTasks(ctx)

	// Start listening for new tasks from the service manager
	go a.listenForNewTasks(ctx)

	// Keep the aggregator running
	<-ctx.Done()
	return nil
}

func (a *Aggregator) startHttpServer() {
	router := mux.NewRouter()
	
	// Health check endpoint
	router.HandleFunc("/health", a.healthHandler).Methods("GET")
	
	// Task response endpoint
	router.HandleFunc("/task-response", a.taskResponseHandler).Methods("POST")
	
	// Task status endpoint
	router.HandleFunc("/task/{taskIndex}", a.taskStatusHandler).Methods("GET")

	a.httpServer = &http.Server{
		Addr:    a.config.ServerIpPortAddr,
		Handler: router,
	}

	a.logger.Info("Starting HTTP server", "address", a.config.ServerIpPortAddr)
	if err := a.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		a.logger.Error("HTTP server error", "error", err)
	}
}

func (a *Aggregator) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func (a *Aggregator) taskResponseHandler(w http.ResponseWriter, r *http.Request) {
	var signedResponse SignedTaskResponse
	if err := json.NewDecoder(r.Body).Decode(&signedResponse); err != nil {
		a.logger.Error("Failed to decode task response", "error", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	a.logger.Info("Received task response",
		"taskIndex", signedResponse.TaskResponse.ReferenceTaskIndex,
		"operatorId", signedResponse.OperatorId.String(),
		"winner", signedResponse.TaskResponse.Winner.Hex(),
		"winningBid", signedResponse.TaskResponse.WinningBid.String(),
	)

	// Process the task response
	if err := a.processTaskResponse(signedResponse); err != nil {
		a.logger.Error("Failed to process task response", "error", err)
		http.Error(w, "Failed to process response", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "accepted"})
}

func (a *Aggregator) taskStatusHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	taskIndex := vars["taskIndex"]

	// Convert taskIndex to uint32 and get task info
	// For simplicity, we'll just return a status
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"taskIndex": taskIndex,
		"status":    "processing",
	})
}

func (a *Aggregator) processTaskResponse(signedResponse SignedTaskResponse) error {
	taskIndex := signedResponse.TaskResponse.ReferenceTaskIndex

	a.tasksMutex.Lock()
	defer a.tasksMutex.Unlock()

	task, exists := a.tasks[taskIndex]
	if !exists {
		// Create new task if it doesn't exist
		task = &TaskInfo{
			TaskIndex:         taskIndex,
			TaskResponses:     make(map[types.OperatorId]TaskResponse),
			TaskResponsesInfo: make(map[types.OperatorId]TaskResponseInfo),
			IsCompleted:       false,
			CreatedAt:        time.Now(),
		}
		a.tasks[taskIndex] = task
	}

	// Add the response
	task.TaskResponses[signedResponse.OperatorId] = signedResponse.TaskResponse
	task.TaskResponsesInfo[signedResponse.OperatorId] = TaskResponseInfo{
		TaskResponse: signedResponse.TaskResponse,
		BlsSignature: signedResponse.BlsSignature,
		OperatorId:   signedResponse.OperatorId,
	}

	a.logger.Info("Task response added",
		"taskIndex", taskIndex,
		"totalResponses", len(task.TaskResponses),
	)

	// Check if we have enough responses to aggregate
	if a.shouldAggregateTask(task) {
		go a.aggregateAndSubmitTask(task)
	}

	return nil
}

func (a *Aggregator) shouldAggregateTask(task *TaskInfo) bool {
	// Simple threshold: aggregate when we have at least 2 responses
	// In a real implementation, this would check against quorum requirements
	return len(task.TaskResponses) >= 2 && !task.IsCompleted
}

func (a *Aggregator) aggregateAndSubmitTask(task *TaskInfo) {
	a.logger.Info("Aggregating task responses", "taskIndex", task.TaskIndex)

	// Simple aggregation: find the most common winner and highest bid
	winnerVotes := make(map[common.Address]int)
	highestBid := big.NewInt(0)
	var finalWinner common.Address
	totalBids := uint32(0)

	for _, response := range task.TaskResponses {
		winnerVotes[response.Winner]++
		if response.WinningBid.Cmp(highestBid) > 0 {
			highestBid = response.WinningBid
		}
		totalBids += response.TotalBids
	}

	// Find winner with most votes
	maxVotes := 0
	for winner, votes := range winnerVotes {
		if votes > maxVotes {
			maxVotes = votes
			finalWinner = winner
		}
	}

	aggregatedResponse := TaskResponse{
		ReferenceTaskIndex: task.TaskIndex,
		Winner:             finalWinner,
		WinningBid:         highestBid,
		TotalBids:          totalBids / uint32(len(task.TaskResponses)), // Average
	}

	a.logger.Info("Aggregated task response",
		"taskIndex", task.TaskIndex,
		"winner", finalWinner.Hex(),
		"winningBid", highestBid.String(),
		"totalResponses", len(task.TaskResponses),
	)

	// Mark task as completed
	a.tasksMutex.Lock()
	task.IsCompleted = true
	a.tasksMutex.Unlock()

	// In a real implementation, this would:
	// 1. Verify BLS signatures
	// 2. Check quorum requirements
	// 3. Submit aggregated response to service manager
	// 4. Handle potential challenges

	a.logger.Info("Task aggregation completed", "taskIndex", task.TaskIndex)
}

func (a *Aggregator) processAggregatedTasks(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.cleanupOldTasks()
		}
	}
}

func (a *Aggregator) cleanupOldTasks() {
	a.tasksMutex.Lock()
	defer a.tasksMutex.Unlock()

	cutoff := time.Now().Add(-1 * time.Hour) // Clean tasks older than 1 hour
	
	for taskIndex, task := range a.tasks {
		if task.CreatedAt.Before(cutoff) {
			delete(a.tasks, taskIndex)
			a.logger.Debug("Cleaned up old task", "taskIndex", taskIndex)
		}
	}
}

func (a *Aggregator) listenForNewTasks(ctx context.Context) {
	a.logger.Info("Starting to listen for new tasks")

	// In a real implementation, this would:
	// 1. Subscribe to NewAuctionTaskCreated events from service manager
	// 2. Initialize task tracking
	// 3. Set up timeouts for task responses

	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.logger.Debug("Listening for new auction tasks...")
		}
	}
}

// GetTaskStatus returns the status of a specific task
func (a *Aggregator) GetTaskStatus(taskIndex uint32) (*TaskInfo, bool) {
	a.tasksMutex.RLock()
	defer a.tasksMutex.RUnlock()
	
	task, exists := a.tasks[taskIndex]
	return task, exists
}

// GetActiveTasks returns all active tasks
func (a *Aggregator) GetActiveTasks() map[uint32]*TaskInfo {
	a.tasksMutex.RLock()
	defer a.tasksMutex.RUnlock()
	
	activeTasks := make(map[uint32]*TaskInfo)
	for taskIndex, task := range a.tasks {
		if !task.IsCompleted {
			activeTasks[taskIndex] = task
		}
	}
	
	return activeTasks
}