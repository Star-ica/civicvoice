// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PetitionRegistry.sol";

/// @title PetitionFactory — deploys and indexes CivicVoice petitions
/// @notice Creates new Petition entries stored in PetitionRegistry
contract PetitionFactory is Ownable, Pausable {

    PetitionRegistry public immutable registry;

    uint256 public petitionCount;

    event PetitionCreated(
        uint256 indexed petitionId,
        address indexed creator,
        string title,
        string category,
        uint256 targetSignatures,
        uint256 deadline
    );

    constructor(address _registry) Ownable(msg.sender) {
        require(_registry != address(0), "Invalid registry");
        registry = PetitionRegistry(_registry);
    }

    /// @notice Create a new petition
    /// @param title Short petition title
    /// @param description Full petition description
    /// @param category Topic category (e.g. "Environment", "Education")
    /// @param targetSignatures Signature goal
    /// @param deadline Unix timestamp after which no new signatures accepted
    /// @return petitionId The assigned petition ID
    function createPetition(
        string calldata title,
        string calldata description,
        string calldata category,
        uint256 targetSignatures,
        uint256 deadline
    ) external whenNotPaused returns (uint256 petitionId) {
        require(bytes(title).length > 0 && bytes(title).length <= 200, "Invalid title length");
        require(bytes(description).length > 0 && bytes(description).length <= 5000, "Invalid description length");
        require(bytes(category).length > 0 && bytes(category).length <= 60, "Invalid category");
        require(targetSignatures > 0, "Target must be > 0");
        require(deadline == 0 || deadline > block.timestamp, "Deadline must be future or 0");

        petitionId = ++petitionCount;

        registry.registerPetition(
            petitionId,
            msg.sender,
            title,
            description,
            category,
            targetSignatures,
            deadline
        );

        emit PetitionCreated(petitionId, msg.sender, title, category, targetSignatures, deadline);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
