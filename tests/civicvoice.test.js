const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CivicVoice", function () {
  let owner, creator, signer1, signer2, signer3, orgWallet;
  let petitionRegistry, petitionFactory, signatureManager, orgRegistry, responseRegistry;

  const SAMPLE_TITLE = "Improve Public Transport";
  const SAMPLE_DESC = "We demand better bus routes and lower fares in our city.";
  const SAMPLE_CAT = "Transport";
  const TARGET_SIGS = 1000;

  beforeEach(async function () {
    [owner, creator, signer1, signer2, signer3, orgWallet] = await ethers.getSigners();

    // Deploy contracts
    const PetitionRegistry = await ethers.getContractFactory("PetitionRegistry");
    petitionRegistry = await PetitionRegistry.deploy();
    await petitionRegistry.waitForDeployment();

    const PetitionFactory = await ethers.getContractFactory("PetitionFactory");
    petitionFactory = await PetitionFactory.deploy(await petitionRegistry.getAddress());
    await petitionFactory.waitForDeployment();

    // Set factory on registry
    await petitionRegistry.setFactory(await petitionFactory.getAddress());

    const SignatureManager = await ethers.getContractFactory("SignatureManager");
    signatureManager = await SignatureManager.deploy(await petitionRegistry.getAddress());
    await signatureManager.waitForDeployment();

    // Also authorize signatureManager as factory for recordSignature
    // (In production, SignatureManager would be authorized separately)

    const OrganizationRegistry = await ethers.getContractFactory("OrganizationRegistry");
    orgRegistry = await OrganizationRegistry.deploy();
    await orgRegistry.waitForDeployment();

    const ResponseRegistry = await ethers.getContractFactory("ResponseRegistry");
    responseRegistry = await ResponseRegistry.deploy(
      await orgRegistry.getAddress(),
      await petitionRegistry.getAddress()
    );
    await responseRegistry.waitForDeployment();
  });

  // ─────────────────────────────────────────────
  // PETITION CREATION
  // ─────────────────────────────────────────────
  describe("Petition Creation", function () {
    it("creates a petition and increments count", async function () {
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
      );
      expect(await petitionFactory.petitionCount()).to.equal(1);
    });

    it("records petition data correctly in registry", async function () {
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
      );
      const p = await petitionRegistry.getPetition(1);
      expect(p.title).to.equal(SAMPLE_TITLE);
      expect(p.creator).to.equal(creator.address);
      expect(p.targetSignatures).to.equal(TARGET_SIGS);
      expect(p.currentSignatures).to.equal(0);
      expect(p.status).to.equal(0); // Active
    });

    it("reverts on empty title", async function () {
      await expect(
        petitionFactory.connect(creator).createPetition("", SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0)
      ).to.be.revertedWith("Invalid title length");
    });

    it("reverts on zero target signatures", async function () {
      await expect(
        petitionFactory.connect(creator).createPetition(SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, 0, 0)
      ).to.be.revertedWith("Target must be > 0");
    });

    it("reverts on past deadline", async function () {
      const pastDeadline = Math.floor(Date.now() / 1000) - 100;
      await expect(
        petitionFactory.connect(creator).createPetition(
          SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, pastDeadline
        )
      ).to.be.revertedWith("Deadline must be future or 0");
    });

    it("indexes petition by creator", async function () {
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
      );
      const ids = await petitionRegistry.getPetitionsByCreator(creator.address);
      expect(ids.length).to.equal(1);
      expect(ids[0]).to.equal(1);
    });

    it("indexes petition by category", async function () {
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
      );
      const ids = await petitionRegistry.getPetitionsByCategory(SAMPLE_CAT);
      expect(ids.length).to.equal(1);
    });
  });

  // ─────────────────────────────────────────────
  // SIGNING
  // ─────────────────────────────────────────────
  describe("Signing", function () {
    beforeEach(async function () {
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, 3, 0
      );
      // Authorize signatureManager to call recordSignature via factory slot
      await petitionRegistry.setFactory(await signatureManager.getAddress());
    });

    it("allows a wallet to sign a petition", async function () {
      await signatureManager.connect(signer1).sign(1);
      expect(await petitionRegistry.hasSigned(1, signer1.address)).to.be.true;
    });

    it("prevents the same wallet from signing twice", async function () {
      await signatureManager.connect(signer1).sign(1);
      await expect(signatureManager.connect(signer1).sign(1))
        .to.be.revertedWith("Already signed this petition");
    });

    it("increments signature count", async function () {
      await signatureManager.connect(signer1).sign(1);
      await signatureManager.connect(signer2).sign(1);
      const p = await petitionRegistry.getPetition(1);
      expect(p.currentSignatures).to.equal(2);
    });

    it("sets status to GoalReached when target met", async function () {
      await signatureManager.connect(signer1).sign(1);
      await signatureManager.connect(signer2).sign(1);
      await signatureManager.connect(signer3).sign(1);
      const p = await petitionRegistry.getPetition(1);
      expect(p.status).to.equal(1); // GoalReached
    });

    it("emits PetitionSigned event", async function () {
      await expect(signatureManager.connect(signer1).sign(1))
        .to.emit(signatureManager, "PetitionSigned")
        .withArgs(1, signer1.address, await ethers.provider.getBlock("latest").then(b => b.timestamp + 1));
    });
  });

  // ─────────────────────────────────────────────
  // PETITION STATUS
  // ─────────────────────────────────────────────
  describe("Petition Status", function () {
    beforeEach(async function () {
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
      );
    });

    it("creator can close petition", async function () {
      await petitionRegistry.connect(creator).closePetition(1);
      const p = await petitionRegistry.getPetition(1);
      expect(p.status).to.equal(2); // Closed
    });

    it("non-creator cannot close petition", async function () {
      await expect(petitionRegistry.connect(signer1).closePetition(1))
        .to.be.revertedWith("Not authorized");
    });

    it("creator can cancel petition with no signatures", async function () {
      await petitionRegistry.connect(creator).cancelPetition(1);
      const p = await petitionRegistry.getPetition(1);
      expect(p.status).to.equal(3); // Cancelled
    });
  });

  // ─────────────────────────────────────────────
  // ORGANIZATIONS
  // ─────────────────────────────────────────────
  describe("Organizations", function () {
    it("registers an organization", async function () {
      await orgRegistry.connect(orgWallet).registerOrganization(
        "City Council", "Government", "https://citycouncil.example"
      );
      expect(await orgRegistry.isOrg(orgWallet.address)).to.be.true;
    });

    it("prevents duplicate registration", async function () {
      await orgRegistry.connect(orgWallet).registerOrganization(
        "City Council", "Government", "https://citycouncil.example"
      );
      await expect(
        orgRegistry.connect(orgWallet).registerOrganization(
          "City Council 2", "Government", "https://test.example"
        )
      ).to.be.revertedWith("Wallet already registered");
    });

    it("admin can verify organization", async function () {
      await orgRegistry.connect(orgWallet).registerOrganization(
        "City Council", "Government", "https://citycouncil.example"
      );
      const orgId = await orgRegistry.getOrgId(orgWallet.address);
      await orgRegistry.connect(owner).setVerified(orgId, true);
      const org = await orgRegistry.getOrganization(orgId);
      expect(org.verified).to.be.true;
    });
  });

  // ─────────────────────────────────────────────
  // RESPONSES & UPDATES
  // ─────────────────────────────────────────────
  describe("Responses and Updates", function () {
    beforeEach(async function () {
      // Restore factory to petitionFactory for creation
      await petitionRegistry.setFactory(await petitionFactory.getAddress());
      await petitionFactory.connect(creator).createPetition(
        SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
      );
      await orgRegistry.connect(orgWallet).registerOrganization(
        "City Council", "Government", "https://citycouncil.example"
      );
    });

    it("registered org can post a response", async function () {
      await responseRegistry.connect(orgWallet).postResponse(
        1, "We acknowledge this petition and will review routes.", "Under review"
      );
      const rIds = await responseRegistry.getResponsesForPetition(1);
      expect(rIds.length).to.equal(1);
    });

    it("non-org cannot post a response", async function () {
      await expect(
        responseRegistry.connect(signer1).postResponse(1, "Some text", "")
      ).to.be.revertedWith("Not a registered organization");
    });

    it("creator can post an update", async function () {
      await responseRegistry.connect(creator).postUpdate(1, "We submitted this petition to the mayor.");
      const updates = await responseRegistry.getUpdatesForPetition(1);
      expect(updates.length).to.equal(1);
      expect(updates[0].updateText).to.equal("We submitted this petition to the mayor.");
    });

    it("non-creator cannot post an update", async function () {
      await expect(
        responseRegistry.connect(signer1).postUpdate(1, "Fake update")
      ).to.be.revertedWith("Only creator");
    });
  });

  // ─────────────────────────────────────────────
  // PAUSE
  // ─────────────────────────────────────────────
  describe("Pause", function () {
    it("owner can pause factory", async function () {
      await petitionFactory.connect(owner).pause();
      await expect(
        petitionFactory.connect(creator).createPetition(
          SAMPLE_TITLE, SAMPLE_DESC, SAMPLE_CAT, TARGET_SIGS, 0
        )
      ).to.be.reverted;
    });

    it("non-owner cannot pause", async function () {
      await expect(petitionFactory.connect(signer1).pause())
        .to.be.revertedWithCustomError(petitionFactory, "OwnableUnauthorizedAccount");
    });
  });
});
