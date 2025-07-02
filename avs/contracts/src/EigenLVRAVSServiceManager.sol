// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@eigenlayer/contracts/middleware/ServiceManagerBase.sol";
import "@eigenlayer/contracts/middleware/BLSSignatureChecker.sol";
import "@eigenlayer/contracts/interfaces/IServiceManager.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EigenLVRAVSServiceManager
 * @notice Service manager for EigenLVR AVS - handles operator registration and task management
 */
contract EigenLVRAVSServiceManager is ServiceManagerBase, BLSSignatureChecker, ReentrancyGuard {
    using BN254 for BN254.G1Point;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint32 public constant TASK_CHALLENGE_WINDOW_BLOCK = 100;
    uint256 public constant TASK_RESPONSE_WINDOW_BLOCK = 30;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct AuctionTask {
        bytes32 poolId;
        uint256 blockNumber;
        uint256 taskCreatedBlock;
        bytes quorumNumbers;
        uint32 quorumThresholdPercentage;
    }

    struct AuctionTaskResponse {
        uint32 referenceTaskIndex;
        address winner;
        uint256 winningBid;
        uint256 totalBids;
    }

    struct AuctionTaskResponseMetadata {
        uint32 taskResponsedBlock;
        bytes32 hashOfNonSigners;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping from task index to auction task hash
    mapping(uint32 => bytes32) public allTaskHashes;
    
    /// @notice Mapping from task index to task response hash
    mapping(uint32 => bytes32) public allTaskResponses;
    
    /// @notice Task index counter
    uint32 public latestTaskNum;
    
    /// @notice Address of the EigenLVR Hook contract
    address public eigenLVRHook;
    
    /// @notice Aggregator address
    address public aggregator;
    
    /// @notice Generator address
    address public generator;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event NewAuctionTaskCreated(uint32 indexed taskIndex, AuctionTask task);
    event AuctionTaskResponded(
        AuctionTaskResponse taskResponse,
        AuctionTaskResponseMetadata taskResponseMetadata
    );
    event TaskCompleted(uint32 indexed taskIndex);
    event TaskChallenged(uint32 indexed taskIndex, address challenger);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyEigenLVRHook() {
        require(msg.sender == eigenLVRHook, "Only EigenLVR Hook can call this function");
        _;
    }
    
    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Only aggregator can call this function");
        _;
    }
    
    modifier onlyGenerator() {
        require(msg.sender == generator, "Only generator can call this function");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IAVSDirectory _avsDirectory,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        address _eigenLVRHook
    ) 
        ServiceManagerBase(_avsDirectory, _registryCoordinator, _stakeRegistry)
        BLSSignatureChecker(_registryCoordinator, _blsApkRegistry)
    {
        eigenLVRHook = _eigenLVRHook;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Called by EigenLVR Hook to create a new auction task
     * @param poolId The pool ID for the auction
     * @param quorumThresholdPercentage The percentage of stake that must sign the response
     * @param quorumNumbers The quorum numbers to use for this task
     */
    function createNewAuctionTask(
        bytes32 poolId,
        uint32 quorumThresholdPercentage,
        bytes calldata quorumNumbers
    ) external onlyEigenLVRHook {
        AuctionTask memory newTask = AuctionTask({
            poolId: poolId,
            blockNumber: block.number,
            taskCreatedBlock: uint32(block.number),
            quorumNumbers: quorumNumbers,
            quorumThresholdPercentage: quorumThresholdPercentage
        });

        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit NewAuctionTaskCreated(latestTaskNum, newTask);
        latestTaskNum++;
    }

    /**
     * @notice Called by aggregator to respond to a task
     * @param task The original task
     * @param taskResponse The aggregated response
     * @param nonSignerStakesAndSignature The BLS signature and non-signer stakes
     */
    function respondToAuctionTask(
        AuctionTask calldata task,
        AuctionTaskResponse calldata taskResponse,
        NonSignerStakesAndSignature memory nonSignerStakesAndSignature
    ) external onlyAggregator {
        uint32 taskCreatedBlock = task.taskCreatedBlock;
        bytes calldata quorumNumbers = task.quorumNumbers;
        uint32 quorumThresholdPercentage = task.quorumThresholdPercentage;

        // Check that the task is valid
        require(
            keccak256(abi.encode(task)) == allTaskHashes[taskResponse.referenceTaskIndex],
            "EigenLVRAVS: Task hash does not match"
        );

        // Check that aggregated response is valid
        require(
            allTaskResponses[taskResponse.referenceTaskIndex] == bytes32(0),
            "EigenLVRAVS: Aggregator has already responded to the task"
        );

        // Check that the response is within the response window
        require(
            uint32(block.number) <= taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK,
            "EigenLVRAVS: Aggregator has responded to the task too late"
        );

        // Verify BLS signature
        (
            QuorumStakeTotals memory quorumStakeTotals,
            bytes32 hashOfNonSigners
        ) = checkSignatures(
            keccak256(abi.encode(taskResponse)),
            quorumNumbers,
            taskCreatedBlock,
            nonSignerStakesAndSignature
        );

        // Check that the signers have at least the required stake
        for (uint i = 0; i < quorumNumbers.length; i++) {
            require(
                quorumStakeTotals.signedStakeForQuorum[i] * THRESHOLD_DENOMINATOR >=
                quorumStakeTotals.totalStakeForQuorum[i] * uint8(quorumThresholdPercentage),
                "EigenLVRAVS: Signers do not own at least threshold percentage of a quorum"
            );
        }

        AuctionTaskResponseMetadata memory taskResponseMetadata = AuctionTaskResponseMetadata({
            taskResponsedBlock: uint32(block.number),
            hashOfNonSigners: hashOfNonSigners
        });

        // Store the response
        allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(abi.encode(taskResponse));

        emit AuctionTaskResponded(taskResponse, taskResponseMetadata);

        // Notify the Hook contract with the result
        IEigenLVRHook(eigenLVRHook).submitAuctionResult(
            task.poolId,
            taskResponse.winner,
            taskResponse.winningBid
        );

        emit TaskCompleted(taskResponse.referenceTaskIndex);
    }

    /**
     * @notice Challenge a task response
     * @param task The original task
     * @param taskResponse The task response to challenge
     * @param taskResponseMetadata The task response metadata
     * @param pubkeysOfNonSigningOperators The public keys of non-signing operators
     */
    function raiseAndResolveChallenge(
        AuctionTask calldata task,
        AuctionTaskResponse calldata taskResponse,
        AuctionTaskResponseMetadata calldata taskResponseMetadata,
        BN254.G1Point[] memory pubkeysOfNonSigningOperators
    ) external {
        uint32 referenceTaskIndex = taskResponse.referenceTaskIndex;
        
        require(
            allTaskResponses[referenceTaskIndex] != bytes32(0),
            "EigenLVRAVS: Task response does not exist"
        );
        
        require(
            allTaskResponses[referenceTaskIndex] == keccak256(abi.encode(taskResponse)),
            "EigenLVRAVS: Task response hash does not match"
        );

        // Check challenge window
        require(
            uint32(block.number) <= taskResponseMetadata.taskResponsedBlock + TASK_CHALLENGE_WINDOW_BLOCK,
            "EigenLVRAVS: Challenge window has passed"
        );

        bytes32 message = keccak256(abi.encode(taskResponse));
        
        // Verify the challenge is valid by checking non-signer pubkeys
        require(
            taskResponseMetadata.hashOfNonSigners == 
            keccak256(abi.encode(pubkeysOfNonSigningOperators)),
            "EigenLVRAVS: Invalid non-signer pubkeys"
        );

        emit TaskChallenged(referenceTaskIndex, msg.sender);
        
        // In a real implementation, you would slash the operators here
        // For now, we'll just emit the challenge event
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Set the aggregator address
     * @param _aggregator The new aggregator address
     */
    function setAggregator(address _aggregator) external onlyOwner {
        aggregator = _aggregator;
    }
    
    /**
     * @notice Set the generator address
     * @param _generator The new generator address
     */
    function setGenerator(address _generator) external onlyOwner {
        generator = _generator;
    }
    
    /**
     * @notice Set the EigenLVR Hook contract address
     * @param _eigenLVRHook The new hook address
     */
    function setEigenLVRHook(address _eigenLVRHook) external onlyOwner {
        eigenLVRHook = _eigenLVRHook;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get task hash by index
     * @param taskIndex The task index
     * @return The task hash
     */
    function getTaskHash(uint32 taskIndex) external view returns (bytes32) {
        return allTaskHashes[taskIndex];
    }
    
    /**
     * @notice Get task response hash by index
     * @param taskIndex The task index
     * @return The task response hash
     */
    function getTaskResponseHash(uint32 taskIndex) external view returns (bytes32) {
        return allTaskResponses[taskIndex];
    }
}

/**
 * @title IEigenLVRHook
 * @notice Interface for EigenLVR Hook contract
 */
interface IEigenLVRHook {
    function submitAuctionResult(
        bytes32 poolId,
        address winner,
        uint256 winningBid
    ) external;
}