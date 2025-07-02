// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRAVSServiceManager} from "../src/EigenLVRAVSServiceManager.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";

contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => bool)) public operatorRegistered;
    mapping(address => mapping(address => uint256)) public operatorStakes;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address avs, address operator) external view override returns (uint256) {
        return operatorStakes[avs][operator];
    }
    
    function setOperatorStake(address avs, address operator, uint256 stake) external {
        operatorStakes[avs][operator] = stake;
    }
}

contract EigenLVRAVSServiceManagerTest is Test {
    EigenLVRAVSServiceManager public serviceManager;
    MockAVSDirectory public avsDirectory;
    
    address public owner = address(0x1);
    address public operator1 = address(0x2);
    address public operator2 = address(0x3);
    address public operator3 = address(0x4);
    address public challenger = address(0x5);
    
    bytes32 public constant AUCTION_ID = keccak256("test_auction");
    bytes32 public constant POOL_ID = keccak256("test_pool");
    
    event OperatorRegistered(address indexed operator, uint256 stake);
    event OperatorDeregistered(address indexed operator);
    event NewTaskCreated(uint32 indexed taskIndex, EigenLVRAVSServiceManager.AuctionTask task);
    event TaskResponded(uint32 indexed taskIndex, address indexed operator, EigenLVRAVSServiceManager.TaskResponse response);
    event TaskCompleted(uint32 indexed taskIndex, address winner, uint256 winningBid);
    event TaskChallenged(uint32 indexed taskIndex, address indexed challenger);
    event RewardsDistributed(uint32 indexed taskIndex, uint256 totalReward);
    event StakeSlashed(address indexed operator, uint256 amount);

    function setUp() public {
        avsDirectory = new MockAVSDirectory();
        
        vm.prank(owner);
        serviceManager = new EigenLVRAVSServiceManager(avsDirectory);
        
        // Fund operators
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);
        vm.deal(operator3, 100 ether);
        vm.deal(challenger, 10 ether);
        vm.deal(address(serviceManager), 50 ether);
        vm.deal(owner, 100 ether);
    }
    
    function test_Constructor() public view {
        assertEq(address(serviceManager.avsDirectory()), address(avsDirectory));
        assertEq(serviceManager.latestTaskNum(), 0);
    }
    
    function test_RegisterOperator() public {
        bytes memory signature = "test_signature";
        uint256 stakeAmount = 35 ether;
        
        vm.expectEmit(true, false, false, true);
        emit OperatorRegistered(operator1, stakeAmount);
        
        vm.prank(operator1);
        serviceManager.registerOperator{value: stakeAmount}(signature);
        
        assertTrue(serviceManager.operatorRegistered(operator1));
        assertEq(serviceManager.operatorStakes(operator1), stakeAmount);
        assertEq(serviceManager.registeredOperators(0), operator1);
        assertEq(serviceManager.getOperatorCount(), 1);
    }
    
    function test_RegisterOperator_InsufficientStake() public {
        bytes memory signature = "test_signature";
        uint256 stakeAmount = 10 ether; // Below minimum
        
        vm.prank(operator1);
        vm.expectRevert("Insufficient stake");
        serviceManager.registerOperator{value: stakeAmount}(signature);
    }
    
    function test_RegisterOperator_AlreadyRegistered() public {
        bytes memory signature = "test_signature";
        uint256 stakeAmount = 35 ether;
        
        vm.startPrank(operator1);
        serviceManager.registerOperator{value: stakeAmount}(signature);
        
        vm.expectRevert("Already registered");
        serviceManager.registerOperator{value: stakeAmount}(signature);
        vm.stopPrank();
    }
    
    function test_DeregisterOperator() public {
        // First register
        bytes memory signature = "test_signature";
        uint256 stakeAmount = 35 ether;
        
        vm.prank(operator1);
        serviceManager.registerOperator{value: stakeAmount}(signature);
        
        uint256 balanceBefore = operator1.balance;
        
        vm.expectEmit(true, false, false, false);
        emit OperatorDeregistered(operator1);
        
        vm.prank(operator1);
        serviceManager.deregisterOperator();
        
        assertFalse(serviceManager.operatorRegistered(operator1));
        assertEq(serviceManager.operatorStakes(operator1), 0);
        assertEq(operator1.balance, balanceBefore + stakeAmount);
        assertEq(serviceManager.getOperatorCount(), 0);
    }
    
    function test_DeregisterOperator_NotRegistered() public {
        vm.prank(operator1);
        vm.expectRevert("Not a registered operator");
        serviceManager.deregisterOperator();
    }
    
    function test_AddStake() public {
        // First register
        bytes memory signature = "test_signature";
        uint256 initialStake = 35 ether;
        uint256 additionalStake = 15 ether;
        
        vm.startPrank(operator1);
        serviceManager.registerOperator{value: initialStake}(signature);
        serviceManager.addStake{value: additionalStake}();
        vm.stopPrank();
        
        assertEq(serviceManager.operatorStakes(operator1), initialStake + additionalStake);
    }
    
    function test_AddStake_NotRegistered() public {
        vm.prank(operator1);
        vm.expectRevert("Not a registered operator");
        serviceManager.addStake{value: 10 ether}();
    }
    
    function test_CreateAuctionTask() public {
        // Register minimum operators first
        _registerOperators();
        
        vm.expectEmit(true, false, false, false);
        emit NewTaskCreated(0, EigenLVRAVSServiceManager.AuctionTask({
            auctionId: AUCTION_ID,
            poolId: POOL_ID,
            taskCreatedBlock: uint32(block.number),
            deadline: block.timestamp + 60,
            completed: false
        }));
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        assertEq(taskIndex, 0);
        assertEq(serviceManager.latestTaskNum(), 1);
        
        EigenLVRAVSServiceManager.AuctionTask memory task = serviceManager.getTask(taskIndex);
        assertEq(task.auctionId, AUCTION_ID);
        assertEq(task.poolId, POOL_ID);
        assertEq(task.taskCreatedBlock, uint32(block.number));
        assertFalse(task.completed);
    }
    
    function test_CreateAuctionTask_InsufficientOperators() public {
        vm.prank(owner);
        vm.expectRevert("Insufficient operators");
        serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
    }
    
    function test_CreateAuctionTask_OnlyOwner() public {
        _registerOperators();
        
        vm.prank(operator1);
        vm.expectRevert();
        serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
    }
    
    function test_RespondToTask() public {
        // Setup: register operators and create task
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        address winner = address(0x999);
        uint256 winningBid = 5 ether;
        bytes memory signature = "test_signature";
        
        vm.expectEmit(true, true, false, false);
        emit TaskResponded(taskIndex, operator1, EigenLVRAVSServiceManager.TaskResponse({
            operator: operator1,
            auctionId: AUCTION_ID,
            winner: winner,
            winningBid: winningBid,
            signature: signature,
            timestamp: block.timestamp
        }));
        
        vm.prank(operator1);
        serviceManager.respondToTask(taskIndex, winner, winningBid, signature);
        
        assertTrue(serviceManager.operatorResponded(taskIndex, operator1));
        
        EigenLVRAVSServiceManager.TaskResponse memory response = serviceManager.getTaskResponse(taskIndex, operator1);
        assertEq(response.operator, operator1);
        assertEq(response.winner, winner);
        assertEq(response.winningBid, winningBid);
    }
    
    function test_RespondToTask_NotRegistered() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        vm.prank(address(0x999));
        vm.expectRevert("Not a registered operator");
        serviceManager.respondToTask(taskIndex, address(0x888), 5 ether, "sig");
    }
    
    function test_RespondToTask_AlreadyResponded() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        vm.startPrank(operator1);
        serviceManager.respondToTask(taskIndex, address(0x999), 5 ether, "sig");
        
        vm.expectRevert("Already responded");
        serviceManager.respondToTask(taskIndex, address(0x999), 5 ether, "sig");
        vm.stopPrank();
    }
    
    function test_RespondToTask_DeadlinePassed() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 61);
        
        vm.prank(operator1);
        vm.expectRevert("Task deadline passed");
        serviceManager.respondToTask(taskIndex, address(0x999), 5 ether, "sig");
    }
    
    function test_TaskCompletion_WithQuorum() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        address winner = address(0x999);
        uint256 winningBid = 5 ether;
        bytes memory signature = "test_signature";
        
        // All operators respond with same answer (consensus)
        vm.prank(operator1);
        serviceManager.respondToTask(taskIndex, winner, winningBid, signature);
        
        vm.prank(operator2);
        serviceManager.respondToTask(taskIndex, winner, winningBid, signature);
        
        vm.expectEmit(true, false, false, true);
        emit TaskCompleted(taskIndex, winner, winningBid);
        
        vm.prank(operator3);
        serviceManager.respondToTask(taskIndex, winner, winningBid, signature);
        
        EigenLVRAVSServiceManager.AuctionTask memory task = serviceManager.getTask(taskIndex);
        assertTrue(task.completed);
    }
    
    function test_TaskCompletion_NoConsensus() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        // Operators respond with different answers (no consensus)
        vm.prank(operator1);
        serviceManager.respondToTask(taskIndex, address(0x999), 5 ether, "sig");
        
        vm.prank(operator2);
        serviceManager.respondToTask(taskIndex, address(0x888), 6 ether, "sig");
        
        vm.prank(operator3);
        serviceManager.respondToTask(taskIndex, address(0x777), 7 ether, "sig");
        
        EigenLVRAVSServiceManager.AuctionTask memory task = serviceManager.getTask(taskIndex);
        assertFalse(task.completed); // Should not complete without consensus
    }
    
    function test_ChallengeTask() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        // Complete task first
        address winner = address(0x999);
        uint256 winningBid = 5 ether;
        
        vm.prank(operator1);
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
        vm.prank(operator2);
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
        vm.prank(operator3);
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
        
        // Challenge the completed task
        vm.expectEmit(true, true, false, false);
        emit TaskChallenged(taskIndex, challenger);
        
        vm.prank(challenger);
        serviceManager.challengeTask{value: 0.1 ether}(taskIndex);
        
        assertTrue(serviceManager.taskChallenged(taskIndex));
    }
    
    function test_ChallengeTask_InsufficientStake() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        vm.prank(challenger);
        vm.expectRevert("Insufficient challenge stake");
        serviceManager.challengeTask{value: 0.05 ether}(taskIndex);
    }
    
    function test_SlashOperator() public {
        _registerOperators();
        
        uint256 slashAmount = 10 ether;
        uint256 initialStake = serviceManager.operatorStakes(operator1);
        uint256 initialRewardPool = serviceManager.rewardPool();
        
        vm.expectEmit(true, false, false, true);
        emit StakeSlashed(operator1, slashAmount);
        
        vm.prank(owner);
        serviceManager.slashOperator(operator1, slashAmount);
        
        assertEq(serviceManager.operatorStakes(operator1), initialStake - slashAmount);
        assertEq(serviceManager.rewardPool(), initialRewardPool + slashAmount);
    }
    
    function test_SlashOperator_InsufficientStake() public {
        _registerOperators();
        
        uint256 slashAmount = 100 ether; // More than operator's stake
        
        vm.prank(owner);
        vm.expectRevert("Insufficient stake");
        serviceManager.slashOperator(operator1, slashAmount);
    }
    
    function test_SlashOperator_OnlyOwner() public {
        _registerOperators();
        
        vm.prank(operator1);
        vm.expectRevert();
        serviceManager.slashOperator(operator2, 10 ether);
    }
    
    function test_Withdraw() public {
        // First ensure there's some balance and it can be withdrawn
        uint256 initialBalance = address(serviceManager).balance;
        
        // Only allow withdrawal if there's actual balance
        if (initialBalance > 0) {
            uint256 ownerBalanceBefore = owner.balance;
            
            vm.prank(owner);
            serviceManager.withdraw();
            
            assertEq(address(serviceManager).balance, 0);
            assertEq(owner.balance, ownerBalanceBefore + initialBalance);
        } else {
            // If no balance, test should pass without action
            vm.prank(owner);
            serviceManager.withdraw(); // Should not revert even with 0 balance
        }
    }
    
    function test_Withdraw_OnlyOwner() public {
        vm.prank(operator1);
        vm.expectRevert();
        serviceManager.withdraw();
    }
    
    function test_FundRewardPool() public {
        uint256 fundAmount = 10 ether;
        uint256 initialRewardPool = serviceManager.rewardPool();
        
        vm.deal(address(this), fundAmount);
        serviceManager.fundRewardPool{value: fundAmount}();
        
        assertEq(serviceManager.rewardPool(), initialRewardPool + fundAmount);
    }
    
    function test_HasQuorum() public {
        assertFalse(serviceManager.hasQuorum());
        
        _registerOperators();
        
        assertTrue(serviceManager.hasQuorum());
    }
    
    function test_ReceiveETH() public {
        uint256 initialRewardPool = serviceManager.rewardPool();
        uint256 amount = 5 ether;
        
        vm.deal(address(this), amount);
        (bool success, ) = address(serviceManager).call{value: amount}("");
        assertTrue(success);
        
        assertEq(serviceManager.rewardPool(), initialRewardPool + amount);
    }
    
    function test_InvalidTaskIndex() public {
        _registerOperators();
        
        vm.prank(operator1);
        vm.expectRevert("Invalid task index");
        serviceManager.respondToTask(999, address(0x999), 5 ether, "sig");
    }
    
    function test_TaskAlreadyCompleted() public {
        _registerOperators();
        
        vm.prank(owner);
        uint32 taskIndex = serviceManager.createAuctionTask(AUCTION_ID, POOL_ID);
        
        // Complete the task
        address winner = address(0x999);
        uint256 winningBid = 5 ether;
        
        vm.prank(operator1);
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
        vm.prank(operator2);
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
        vm.prank(operator3);
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
        
        // Try to respond again after completion
        vm.prank(operator1);
        vm.expectRevert("Task already completed");
        serviceManager.respondToTask(taskIndex, winner, winningBid, "sig");
    }
    
    // Helper function to register minimum required operators
    function _registerOperators() internal {
        bytes memory signature = "test_signature";
        uint256 stakeAmount = 35 ether;
        
        vm.prank(operator1);
        serviceManager.registerOperator{value: stakeAmount}(signature);
        
        vm.prank(operator2);
        serviceManager.registerOperator{value: stakeAmount}(signature);
        
        vm.prank(operator3);
        serviceManager.registerOperator{value: stakeAmount}(signature);
    }
}