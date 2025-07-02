// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAVSDirectory} from "./interfaces/IAVSDirectory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title EigenLVRAVSServiceManager
 * @notice Service Manager for EigenLVR AVS handling operator registration and task management
 * @dev This contract manages the EigenLayer AVS for auction validation and consensus
 */
contract EigenLVRAVSServiceManager is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Minimum stake required for operators (in wei)
    uint256 public constant MINIMUM_STAKE = 32 ether;
    
    /// @notice Task response window (60 seconds)
    uint256 public constant TASK_RESPONSE_WINDOW = 60;
    
    /// @notice Challenge window (7 days)
    uint256 public constant CHALLENGE_WINDOW = 7 days;
    
    /// @notice Minimum operators required for quorum
    uint256 public constant MINIMUM_QUORUM_SIZE = 3;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice EigenLayer AVS Directory
    IAVSDirectory public immutable avsDirectory;
    
    /// @notice Current task number
    uint32 public latestTaskNum;
    
    /// @notice Mapping of task number to task hash
    mapping(uint32 => bytes32) public allTaskHashes;
    
    /// @notice Mapping of task number to task response hash
    mapping(uint32 => bytes32) public allTaskResponses;
    
    /// @notice Mapping to track operator registration status
    mapping(address => bool) public operatorRegistered;
    
    /// @notice Mapping to track operator stakes
    mapping(address => uint256) public operatorStakes;
    
    /// @notice Array of registered operators
    address[] public registeredOperators;
    
    /// @notice Mapping to check if task has been responded to
    mapping(uint32 => mapping(address => bool)) public operatorResponded;
    
    /// @notice Mapping to track challenge status
    mapping(uint32 => bool) public taskChallenged;
    
    /// @notice Reward pool for operators
    uint256 public rewardPool;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Structure for auction tasks
    struct AuctionTask {
        bytes32 auctionId;
        bytes32 poolId;
        uint32 taskCreatedBlock;
        uint256 deadline;
        bool completed;
    }
    
    /// @notice Structure for task responses
    struct TaskResponse {
        address operator;
        bytes32 auctionId;
        address winner;
        uint256 winningBid;
        bytes signature;
        uint256 timestamp;
    }
    
    /// @notice Mapping of task number to auction task
    mapping(uint32 => AuctionTask) public auctionTasks;
    
    /// @notice Mapping of task number to operator responses
    mapping(uint32 => mapping(address => TaskResponse)) public taskResponses;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event NewTaskCreated(uint32 indexed taskIndex, AuctionTask task);
    event TaskResponded(uint32 indexed taskIndex, address indexed operator, TaskResponse response);
    event TaskCompleted(uint32 indexed taskIndex, address winner, uint256 winningBid);
    event TaskChallenged(uint32 indexed taskIndex, address indexed challenger);
    event RewardsDistributed(uint32 indexed taskIndex, uint256 totalReward);
    event StakeSlashed(address indexed operator, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyRegisteredOperator() {
        require(operatorRegistered[msg.sender], "Not a registered operator");
        _;
    }
    
    modifier onlyValidTask(uint32 taskIndex) {
        require(taskIndex <= latestTaskNum, "Invalid task index");
        require(!auctionTasks[taskIndex].completed, "Task already completed");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(IAVSDirectory _avsDirectory) Ownable(msg.sender) {
        avsDirectory = _avsDirectory;
    }

    /*//////////////////////////////////////////////////////////////
                           OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Register as an operator in the AVS
     * @param operatorSignature Signature proving operator authorization
     */
    function registerOperator(bytes calldata operatorSignature) external payable nonReentrant {
        require(!operatorRegistered[msg.sender], "Already registered");
        require(msg.value >= MINIMUM_STAKE, "Insufficient stake");
        
        // Register with EigenLayer AVS Directory
        avsDirectory.registerOperatorToAVS(msg.sender, operatorSignature);
        
        // Update local state
        operatorRegistered[msg.sender] = true;
        operatorStakes[msg.sender] = msg.value;
        registeredOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender, msg.value);
    }
    
    /**
     * @notice Deregister from the AVS
     */
    function deregisterOperator() external onlyRegisteredOperator nonReentrant {
        // Deregister from EigenLayer
        avsDirectory.deregisterOperatorFromAVS(msg.sender);
        
        // Return stake
        uint256 stake = operatorStakes[msg.sender];
        operatorStakes[msg.sender] = 0;
        operatorRegistered[msg.sender] = false;
        
        // Remove from operators array
        _removeOperator(msg.sender);
        
        // Return stake
        payable(msg.sender).transfer(stake);
        
        emit OperatorDeregistered(msg.sender);
    }
    
    /**
     * @notice Add additional stake
     */
    function addStake() external payable onlyRegisteredOperator {
        operatorStakes[msg.sender] += msg.value;
    }

    /*//////////////////////////////////////////////////////////////
                            TASK MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create a new auction task
     * @param auctionId The auction identifier
     * @param poolId The pool identifier
     * @return taskIndex The created task index
     */
    function createAuctionTask(
        bytes32 auctionId,
        bytes32 poolId
    ) external onlyOwner returns (uint32) {
        require(registeredOperators.length >= MINIMUM_QUORUM_SIZE, "Insufficient operators");
        
        uint32 taskIndex = latestTaskNum;
        latestTaskNum++;
        
        AuctionTask memory newTask = AuctionTask({
            auctionId: auctionId,
            poolId: poolId,
            taskCreatedBlock: uint32(block.number),
            deadline: block.timestamp + TASK_RESPONSE_WINDOW,
            completed: false
        });
        
        auctionTasks[taskIndex] = newTask;
        allTaskHashes[taskIndex] = keccak256(abi.encode(newTask));
        
        emit NewTaskCreated(taskIndex, newTask);
        
        return taskIndex;
    }
    
    /**
     * @notice Submit response to auction task
     * @param taskIndex The task index
     * @param winner The auction winner
     * @param winningBid The winning bid amount
     * @param signature BLS signature of the response
     */
    function respondToTask(
        uint32 taskIndex,
        address winner,
        uint256 winningBid,
        bytes calldata signature
    ) external onlyRegisteredOperator onlyValidTask(taskIndex) {
        require(block.timestamp <= auctionTasks[taskIndex].deadline, "Task deadline passed");
        require(!operatorResponded[taskIndex][msg.sender], "Already responded");
        
        TaskResponse memory response = TaskResponse({
            operator: msg.sender,
            auctionId: auctionTasks[taskIndex].auctionId,
            winner: winner,
            winningBid: winningBid,
            signature: signature,
            timestamp: block.timestamp
        });
        
        taskResponses[taskIndex][msg.sender] = response;
        operatorResponded[taskIndex][msg.sender] = true;
        
        emit TaskResponded(taskIndex, msg.sender, response);
        
        // Check if we have quorum and can complete task
        _checkAndCompleteTask(taskIndex);
    }
    
    /**
     * @notice Complete task if quorum is reached
     * @param taskIndex The task index
     */
    function _checkAndCompleteTask(uint32 taskIndex) internal {
        uint256 responses = 0;
        address consensusWinner;
        uint256 consensusBid;
        uint256 consensusCount = 0;
        
        // Count responses and find consensus
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            address operator = registeredOperators[i];
            if (operatorResponded[taskIndex][operator]) {
                responses++;
                
                TaskResponse memory response = taskResponses[taskIndex][operator];
                
                // Simple consensus: find most common response
                uint256 matchingResponses = 0;
                for (uint256 j = 0; j < registeredOperators.length; j++) {
                    address otherOperator = registeredOperators[j];
                    if (operatorResponded[taskIndex][otherOperator]) {
                        TaskResponse memory otherResponse = taskResponses[taskIndex][otherOperator];
                        if (response.winner == otherResponse.winner && 
                            response.winningBid == otherResponse.winningBid) {
                            matchingResponses++;
                        }
                    }
                }
                
                if (matchingResponses > consensusCount) {
                    consensusCount = matchingResponses;
                    consensusWinner = response.winner;
                    consensusBid = response.winningBid;
                }
            }
        }
        
        // Complete task if we have quorum and consensus
        if (responses >= MINIMUM_QUORUM_SIZE && 
            consensusCount >= (responses * 2) / 3) { // 2/3 majority
            
            auctionTasks[taskIndex].completed = true;
            allTaskResponses[taskIndex] = keccak256(abi.encode(consensusWinner, consensusBid));
            
            emit TaskCompleted(taskIndex, consensusWinner, consensusBid);
            
            // Distribute rewards
            _distributeRewards(taskIndex, consensusWinner, consensusBid);
        }
    }
    
    /**
     * @notice Distribute rewards to operators who participated in consensus
     * @param taskIndex The task index
     * @param winner The consensus winner
     * @param winningBid The consensus bid
     */
    function _distributeRewards(uint32 taskIndex, address winner, uint256 winningBid) internal {
        uint256 totalReward = (winningBid * 1000) / 10000; // 10% of winning bid
        uint256 participantReward = totalReward / registeredOperators.length;
        
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            address operator = registeredOperators[i];
            if (operatorResponded[taskIndex][operator]) {
                TaskResponse memory response = taskResponses[taskIndex][operator];
                
                // Reward operators who provided correct consensus
                if (response.winner == winner && response.winningBid == winningBid) {
                    payable(operator).transfer(participantReward);
                }
            }
        }
        
        emit RewardsDistributed(taskIndex, totalReward);
    }

    /*//////////////////////////////////////////////////////////////
                              CHALLENGE SYSTEM
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Challenge a completed task
     * @param taskIndex The task index to challenge
     */
    function challengeTask(uint32 taskIndex) external payable {
        require(msg.value >= 0.1 ether, "Insufficient challenge stake");
        require(auctionTasks[taskIndex].completed, "Task not completed");
        require(!taskChallenged[taskIndex], "Already challenged");
        require(
            block.timestamp <= 
            auctionTasks[taskIndex].deadline + CHALLENGE_WINDOW, 
            "Challenge window expired"
        );
        
        taskChallenged[taskIndex] = true;
        
        emit TaskChallenged(taskIndex, msg.sender);
        
        // In a full implementation, this would trigger a dispute resolution process
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get task details
     * @param taskIndex The task index
     * @return task The auction task
     */
    function getTask(uint32 taskIndex) external view returns (AuctionTask memory) {
        return auctionTasks[taskIndex];
    }
    
    /**
     * @notice Get operator response for a task
     * @param taskIndex The task index
     * @param operator The operator address
     * @return response The task response
     */
    function getTaskResponse(uint32 taskIndex, address operator) 
        external 
        view 
        returns (TaskResponse memory) 
    {
        return taskResponses[taskIndex][operator];
    }
    
    /**
     * @notice Get number of registered operators
     * @return The number of operators
     */
    function getOperatorCount() external view returns (uint256) {
        return registeredOperators.length;
    }
    
    /**
     * @notice Check if minimum quorum is available
     * @return Whether quorum is available
     */
    function hasQuorum() external view returns (bool) {
        return registeredOperators.length >= MINIMUM_QUORUM_SIZE;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Emergency function to slash operator stake
     * @param operator The operator to slash
     * @param amount The amount to slash
     */
    function slashOperator(address operator, uint256 amount) external onlyOwner {
        require(operatorStakes[operator] >= amount, "Insufficient stake");
        
        operatorStakes[operator] -= amount;
        rewardPool += amount;
        
        emit StakeSlashed(operator, amount);
    }
    
    /**
     * @notice Withdraw contract balance (owner only)
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Transfer failed");
        }
    }
    
    /**
     * @notice Fund reward pool
     */
    function fundRewardPool() external payable {
        rewardPool += msg.value;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Remove operator from array
     * @param operator The operator to remove
     */
    function _removeOperator(address operator) internal {
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == operator) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
    }
    
    /**
     * @notice Receive ETH
     */
    receive() external payable {
        rewardPool += msg.value;
    }
}