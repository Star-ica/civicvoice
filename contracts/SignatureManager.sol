// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PetitionRegistry.sol";

/// @title SignatureManager — handles wallet-based petition signing
/// @notice One wallet = one signature per petition. Does NOT verify unique human identity.
/// @dev WARNING: One person may control multiple wallets. Signatures reflect wallets, not unique humans.
contract SignatureManager is Ownable, Pausable {

    PetitionRegistry public immutable registry;

    event PetitionSigned(uint256 indexed petitionId, address indexed signer, uint256 timestamp);

    constructor(address _registry) Ownable(msg.sender) {
        require(_registry != address(0), "Invalid registry");
        registry = PetitionRegistry(_registry);
    }

    /// @notice Sign a petition with the caller's wallet
    /// @param petitionId The petition to sign
    function sign(uint256 petitionId) external whenNotPaused {
        require(!registry.hasSigned(petitionId, msg.sender), "Already signed this petition");
        registry.recordSignature(petitionId, msg.sender);
        emit PetitionSigned(petitionId, msg.sender, block.timestamp);
    }

    /// @notice Check if an address has signed a petition
    function hasSigned(uint256 petitionId, address wallet) external view returns (bool) {
        return registry.hasSigned(petitionId, wallet);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
