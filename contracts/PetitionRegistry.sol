// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PetitionRegistry — stores all petition data on-chain
contract PetitionRegistry is Ownable {

    enum PetitionStatus { Active, GoalReached, Closed, Cancelled }

    struct Petition {
        uint256 id;
        address creator;
        string title;
        string description;
        string category;
        uint256 targetSignatures;
        uint256 currentSignatures;
        uint256 deadline;        // 0 = no deadline
        PetitionStatus status;
        uint256 createdAt;
        bool exists;
    }

    mapping(uint256 => Petition) public petitions;
    mapping(uint256 => address[]) private petitionSigners;      // id → signers list
    mapping(uint256 => mapping(address => bool)) public hasSigned; // id → signer → signed

    // Index: creator → their petition IDs
    mapping(address => uint256[]) public petitionsByCreator;
    // Index: category → petition IDs
    mapping(string => uint256[]) public petitionsByCategory;

    address public factory;

    event PetitionRegistered(uint256 indexed petitionId, address indexed creator);
    event PetitionStatusUpdated(uint256 indexed petitionId, PetitionStatus status);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier petitionExists(uint256 petitionId) {
        require(petitions[petitionId].exists, "Petition not found");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /// @notice Set the authorized factory address (called once after deployment)
    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid factory");
        factory = _factory;
    }

    /// @notice Register a new petition (called by factory only)
    function registerPetition(
        uint256 petitionId,
        address creator,
        string calldata title,
        string calldata description,
        string calldata category,
        uint256 targetSignatures,
        uint256 deadline
    ) external onlyFactory {
        petitions[petitionId] = Petition({
            id: petitionId,
            creator: creator,
            title: title,
            description: description,
            category: category,
            targetSignatures: targetSignatures,
            currentSignatures: 0,
            deadline: deadline,
            status: PetitionStatus.Active,
            createdAt: block.timestamp,
            exists: true
        });

        petitionsByCreator[creator].push(petitionId);
        petitionsByCategory[category].push(petitionId);

        emit PetitionRegistered(petitionId, creator);
    }

    /// @notice Get petition info
    function getPetition(uint256 petitionId) external view petitionExists(petitionId)
        returns (Petition memory) {
        return petitions[petitionId];
    }

    /// @notice Check if a wallet has signed
    function checkSigned(uint256 petitionId, address wallet) external view returns (bool) {
        return hasSigned[petitionId][wallet];
    }

    /// @notice Get all signers for a petition
    function getSigners(uint256 petitionId, uint256 offset, uint256 limit)
        external view petitionExists(petitionId)
        returns (address[] memory signers, uint256 total) {
        address[] storage all = petitionSigners[petitionId];
        total = all.length;
        uint256 end = offset + limit > total ? total : offset + limit;
        signers = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            signers[i - offset] = all[i];
        }
    }

    /// @notice Record a signature (called by SignatureManager)
    function recordSignature(uint256 petitionId, address signer) external onlyFactory {
        Petition storage p = petitions[petitionId];
        require(p.exists, "Not found");
        require(p.status == PetitionStatus.Active, "Not active");
        require(p.deadline == 0 || block.timestamp <= p.deadline, "Deadline passed");
        require(!hasSigned[petitionId][signer], "Already signed");

        hasSigned[petitionId][signer] = true;
        petitionSigners[petitionId].push(signer);
        p.currentSignatures++;

        if (p.currentSignatures >= p.targetSignatures) {
            p.status = PetitionStatus.GoalReached;
            emit PetitionStatusUpdated(petitionId, PetitionStatus.GoalReached);
        }
    }

    /// @notice Close a petition (by creator or owner)
    function closePetition(uint256 petitionId) external petitionExists(petitionId) {
        Petition storage p = petitions[petitionId];
        require(msg.sender == p.creator || msg.sender == owner(), "Not authorized");
        require(p.status != PetitionStatus.Cancelled, "Already cancelled");
        p.status = PetitionStatus.Closed;
        emit PetitionStatusUpdated(petitionId, PetitionStatus.Closed);
    }

    /// @notice Cancel a petition (by creator only, before any signatures)
    function cancelPetition(uint256 petitionId) external petitionExists(petitionId) {
        Petition storage p = petitions[petitionId];
        require(msg.sender == p.creator, "Only creator");
        require(p.currentSignatures == 0, "Has signatures");
        p.status = PetitionStatus.Cancelled;
        emit PetitionStatusUpdated(petitionId, PetitionStatus.Cancelled);
    }

    /// @notice Get petitions by creator
    function getPetitionsByCreator(address creator) external view returns (uint256[] memory) {
        return petitionsByCreator[creator];
    }

    /// @notice Get petitions by category
    function getPetitionsByCategory(string calldata category) external view returns (uint256[] memory) {
        return petitionsByCategory[category];
    }
}
