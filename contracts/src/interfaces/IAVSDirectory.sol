// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAVSDirectory
 * @notice Interface for EigenLayer AVS Directory
 */
interface IAVSDirectory {
    /**
     * @notice Register as an AVS operator
     * @param operatorSignature The operator's signature
     */
    function registerOperatorToAVS(
        address operator,
        bytes calldata operatorSignature
    ) external;

    /**
     * @notice Deregister an AVS operator
     */
    function deregisterOperatorFromAVS(address operator) external;

    /**
     * @notice Check if an operator is registered for an AVS
     * @param avs The AVS address
     * @param operator The operator address
     * @return Whether the operator is registered
     */
    function isOperatorRegistered(address avs, address operator) external view returns (bool);

    /**
     * @notice Get operator's stake for an AVS
     * @param avs The AVS address
     * @param operator The operator address
     * @return The operator's stake amount
     */
    function getOperatorStake(address avs, address operator) external view returns (uint256);
}