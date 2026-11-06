# CivicVoice — Deployment Guide

## Prerequisites
- Node.js >= 18, npm >= 9
- MetaMask with BOT Chain configured
- Funded deployer wallet

## 1. Setup

```bash
mkdir civicvoice-deploy && cd civicvoice-deploy
npm init -y
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npm install @openzeppelin/contracts dotenv
npx hardhat init
```

Copy all `.sol` files from `contracts/` into `contracts/`.

## 2. Environment Variables

```env
PRIVATE_KEY=0xyour_deployer_private_key
BOT_RPC_URL=https://rpc.botchain.tg
EXPLORER_API_KEY=your_key
```

## 3. hardhat.config.js

```js
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: { version: "0.8.20", settings: { optimizer: { enabled: true, runs: 200 } } },
  networks: {
    botchain: { url: process.env.BOT_RPC_URL, chainId: 677, accounts: [process.env.PRIVATE_KEY] }
  },
  etherscan: {
    apiKey: { botchain: process.env.EXPLORER_API_KEY || "none" },
    customChains: [{ network: "botchain", chainId: 677,
      urls: { apiURL: "https://explorer.botchain.tg/api", browserURL: "https://explorer.botchain.tg" } }]
  }
};
```

## 4. Deploy Script

Create `scripts/deploy.js`:

```js
const { ethers } = require("hardhat");
const fs = require("fs");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // 1. PetitionRegistry
  const PetitionRegistry = await ethers.getContractFactory("PetitionRegistry");
  const registry = await PetitionRegistry.deploy();
  await registry.waitForDeployment();
  console.log("PetitionRegistry:", await registry.getAddress());

  // 2. OrganizationRegistry
  const OrganizationRegistry = await ethers.getContractFactory("OrganizationRegistry");
  const orgRegistry = await OrganizationRegistry.deploy();
  await orgRegistry.waitForDeployment();
  console.log("OrganizationRegistry:", await orgRegistry.getAddress());

  // 3. PetitionFactory
  const PetitionFactory = await ethers.getContractFactory("PetitionFactory");
  const factory = await PetitionFactory.deploy(await registry.getAddress());
  await factory.waitForDeployment();
  console.log("PetitionFactory:", await factory.getAddress());

  // 4. Set factory on registry
  await (await registry.setFactory(await factory.getAddress())).wait();
  console.log("Factory authorized on registry");

  // 5. SignatureManager
  const SignatureManager = await ethers.getContractFactory("SignatureManager");
  const sigMgr = await SignatureManager.deploy(await registry.getAddress());
  await sigMgr.waitForDeployment();
  console.log("SignatureManager:", await sigMgr.getAddress());

  // 6. Authorize SignatureManager as factory for signing calls
  await (await registry.setFactory(await sigMgr.getAddress())).wait();
  console.log("SignatureManager authorized on registry");

  // 7. ResponseRegistry
  const ResponseRegistry = await ethers.getContractFactory("ResponseRegistry");
  const respRegistry = await ResponseRegistry.deploy(
    await orgRegistry.getAddress(), await registry.getAddress()
  );
  await respRegistry.waitForDeployment();
  console.log("ResponseRegistry:", await respRegistry.getAddress());

  const addresses = {
    PetitionRegistry: await registry.getAddress(),
    OrganizationRegistry: await orgRegistry.getAddress(),
    PetitionFactory: await factory.getAddress(),
    SignatureManager: await sigMgr.getAddress(),
    ResponseRegistry: await respRegistry.getAddress()
  };
  fs.writeFileSync("deployed-addresses.json", JSON.stringify(addresses, null, 2));
  console.log("\nAll deployed. See deployed-addresses.json");
}

main().catch(e => { console.error(e); process.exit(1); });
```

```bash
npx hardhat compile
npx hardhat run scripts/deploy.js --network botchain
```

## 5. Verify Contracts

```bash
npx hardhat verify --network botchain <PETITION_REGISTRY_ADDRESS>
npx hardhat verify --network botchain <ORG_REGISTRY_ADDRESS>
npx hardhat verify --network botchain <PETITION_FACTORY_ADDRESS> "<PETITION_REGISTRY_ADDRESS>"
npx hardhat verify --network botchain <SIGNATURE_MANAGER_ADDRESS> "<PETITION_REGISTRY_ADDRESS>"
npx hardhat verify --network botchain <RESPONSE_REGISTRY_ADDRESS> "<ORG_REGISTRY_ADDRESS>" "<PETITION_REGISTRY_ADDRESS>"
```

## 6. Update Frontend

Open `index.html`, find the `CONFIG` block:

```js
const CONFIG = {
  contracts: {
    PetitionFactory: "PASTE_ADDRESS",
    PetitionRegistry: "PASTE_ADDRESS",
    SignatureManager: "PASTE_ADDRESS",
    OrganizationRegistry: "PASTE_ADDRESS",
    ResponseRegistry: "PASTE_ADDRESS"
  }
};
```

Also set `const DEMO = false;` to disable demo mode.

## 7. Post-Deployment Checklist
- [ ] All 5 contracts deployed and verified
- [ ] SignatureManager authorized on PetitionRegistry
- [ ] Create a test petition via frontend
- [ ] Sign the petition with a second wallet
- [ ] Verify signature count increments
- [ ] Register a test organization
- [ ] Admin verifies the organization
- [ ] Organization posts a response
- [ ] Creator posts an update
- [ ] Test pause/unpause from admin dashboard
