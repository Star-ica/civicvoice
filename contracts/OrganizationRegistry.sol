// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title OrganizationRegistry — registers official organizations that can respond to petitions
contract OrganizationRegistry is Ownable {

    struct Organization {
        uint256 id;
        address wallet;
        string name;
        string orgType;     // "Government", "NGO", "Corporate", "Community"
        string website;
        bool verified;
        bool exists;
        uint256 registeredAt;
    }

    uint256 public orgCount;
    mapping(uint256 => Organization) public organizations;
    mapping(address => uint256) public orgIdByWallet;   // wallet → orgId (0 = not registered)
    mapping(address => bool) public isRegistered;

    event OrganizationRegistered(uint256 indexed orgId, address indexed wallet, string name);
    event OrganizationVerified(uint256 indexed orgId, bool verified);

    constructor() Ownable(msg.sender) {}

    /// @notice Register an organization profile
    function registerOrganization(
        string calldata name,
        string calldata orgType,
        string calldata website
    ) external returns (uint256 orgId) {
        require(!isRegistered[msg.sender], "Wallet already registered");
        require(bytes(name).length > 0 && bytes(name).length <= 200, "Invalid name");

        orgId = ++orgCount;
        organizations[orgId] = Organization({
            id: orgId,
            wallet: msg.sender,
            name: name,
            orgType: orgType,
            website: website,
            verified: false,
            exists: true,
            registeredAt: block.timestamp
        });

        orgIdByWallet[msg.sender] = orgId;
        isRegistered[msg.sender] = true;

        emit OrganizationRegistered(orgId, msg.sender, name);
    }

    /// @notice Admin verifies an organization (adds a verified badge)
    function setVerified(uint256 orgId, bool verified) external onlyOwner {
        require(organizations[orgId].exists, "Not found");
        organizations[orgId].verified = verified;
        emit OrganizationVerified(orgId, verified);
    }

    /// @notice Get org info
    function getOrganization(uint256 orgId) external view returns (Organization memory) {
        require(organizations[orgId].exists, "Not found");
        return organizations[orgId];
    }

    /// @notice Check if a wallet is a registered organization
    function isOrg(address wallet) external view returns (bool) {
        return isRegistered[wallet];
    }

    /// @notice Get org ID for a wallet
    function getOrgId(address wallet) external view returns (uint256) {
        return orgIdByWallet[wallet];
    }
}
