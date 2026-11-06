// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./OrganizationRegistry.sol";
import "./PetitionRegistry.sol";

/// @title ResponseRegistry — stores official organization responses and petition updates
contract ResponseRegistry is Ownable {

    struct Response {
        uint256 id;
        uint256 petitionId;
        uint256 orgId;
        address responder;
        string responseText;    // max 2000 chars
        string actionTaken;     // brief note on what was done
        uint256 timestamp;
        bool exists;
    }

    struct PetitionUpdate {
        uint256 id;
        uint256 petitionId;
        address creator;
        string updateText;
        uint256 timestamp;
    }

    uint256 public responseCount;
    uint256 public updateCount;

    mapping(uint256 => Response) public responses;
    mapping(uint256 => PetitionUpdate[]) public petitionUpdates;    // petitionId → updates
    mapping(uint256 => uint256[]) public responsesByPetition;       // petitionId → response IDs

    OrganizationRegistry public immutable orgRegistry;
    PetitionRegistry public immutable petitionRegistry;

    event ResponsePosted(uint256 indexed responseId, uint256 indexed petitionId, uint256 indexed orgId);
    event UpdatePosted(uint256 indexed petitionId, address indexed creator, uint256 updateIndex);

    constructor(address _orgRegistry, address _petitionRegistry) Ownable(msg.sender) {
        orgRegistry = OrganizationRegistry(_orgRegistry);
        petitionRegistry = PetitionRegistry(_petitionRegistry);
    }

    /// @notice Post an official organization response to a petition
    function postResponse(
        uint256 petitionId,
        string calldata responseText,
        string calldata actionTaken
    ) external returns (uint256 responseId) {
        require(orgRegistry.isOrg(msg.sender), "Not a registered organization");
        require(bytes(responseText).length > 0 && bytes(responseText).length <= 2000, "Invalid response length");

        uint256 orgId = orgRegistry.getOrgId(msg.sender);
        responseId = ++responseCount;

        responses[responseId] = Response({
            id: responseId,
            petitionId: petitionId,
            orgId: orgId,
            responder: msg.sender,
            responseText: responseText,
            actionTaken: actionTaken,
            timestamp: block.timestamp,
            exists: true
        });

        responsesByPetition[petitionId].push(responseId);
        emit ResponsePosted(responseId, petitionId, orgId);
    }

    /// @notice Petition creator posts a progress update
    function postUpdate(uint256 petitionId, string calldata updateText) external {
        PetitionRegistry.Petition memory p = petitionRegistry.getPetition(petitionId);
        require(msg.sender == p.creator, "Only creator");
        require(bytes(updateText).length > 0 && bytes(updateText).length <= 1000, "Invalid update");

        uint256 idx = petitionUpdates[petitionId].length;
        petitionUpdates[petitionId].push(PetitionUpdate({
            id: ++updateCount,
            petitionId: petitionId,
            creator: msg.sender,
            updateText: updateText,
            timestamp: block.timestamp
        }));

        emit UpdatePosted(petitionId, msg.sender, idx);
    }

    /// @notice Get all responses for a petition
    function getResponsesForPetition(uint256 petitionId) external view returns (uint256[] memory) {
        return responsesByPetition[petitionId];
    }

    /// @notice Get a specific response
    function getResponse(uint256 responseId) external view returns (Response memory) {
        require(responses[responseId].exists, "Not found");
        return responses[responseId];
    }

    /// @notice Get all updates for a petition
    function getUpdatesForPetition(uint256 petitionId) external view returns (PetitionUpdate[] memory) {
        return petitionUpdates[petitionId];
    }
}
