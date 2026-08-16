// Deploy the Hero Arena governance base contracts.
//
// Usage (BSC testnet defaults are provided for HAP/Profile/Admin):
//   pnpm hardhat run scripts/deploy-governance.ts --network bscTestnet
//
// Optional overrides:
//   HAP_TOKEN_ADDRESS=0x... HERO_ARENA_PROFILE_ADDRESS=0x... \
//   GOVERNANCE_ADMIN_ADDRESS=0x... pnpm hardhat run ...

import { network } from "hardhat";
import { writeFile } from "node:fs/promises";
import {
  encodeFunctionData,
  formatEther,
  getAddress,
  isAddress,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";

const DEFAULTS = {
  hapToken: "0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f",
  heroArenaProfile: "0x48B3f5Ea324d8e0AFaF63c8469f664Bc659B3bbc",
  governanceAdmin: "0x02334708A7069993fe7f14cdbfC9863AcF3598C4",
} as const;

function configuredAddress(variable: string, fallback: string): Address {
  const value = process.env[variable] ?? fallback;
  if (!isAddress(value) || value.toLowerCase() === zeroAddress) {
    throw new Error(`${variable} is not a valid non-zero address: ${value}`);
  }
  return getAddress(value);
}

async function main() {
  const hapToken = configuredAddress("HAP_TOKEN_ADDRESS", DEFAULTS.hapToken);
  const heroArenaProfile = configuredAddress(
    "HERO_ARENA_PROFILE_ADDRESS",
    DEFAULTS.heroArenaProfile,
  );
  const governanceAdmin = configuredAddress(
    "GOVERNANCE_ADMIN_ADDRESS",
    DEFAULTS.governanceAdmin,
  );

  const connection = await network.connect();
  const { viem, networkName } = connection;
  const publicClient = await viem.getPublicClient();
  const [deployerClient] = await viem.getWalletClients();
  if (deployerClient === undefined) throw new Error("No deployer wallet configured");
  const deployer = getAddress(deployerClient.account.address);
  const chainId = await publicClient.getChainId();

  console.log(`Network: ${networkName} (${chainId})`);
  console.log(`Deployer: ${deployer}`);
  console.log(`Balance: ${formatEther(await publicClient.getBalance({ address: deployer }))} native token`);
  console.log(`HAP: ${hapToken}`);
  console.log(`HeroArenaProfile: ${heroArenaProfile}`);
  console.log(`Governance admin: ${governanceAdmin}`);

  for (const [name, address] of [
    ["HAP_TOKEN_ADDRESS", hapToken],
    ["HERO_ARENA_PROFILE_ADDRESS", heroArenaProfile],
  ] as const) {
    const bytecode = await publicClient.getCode({ address });
    if (bytecode === undefined || bytecode === "0x") {
      throw new Error(`${name} has no deployed bytecode at ${address}`);
    }
  }

  const profile = await viem.getContractAt("HeroArenaProfile", heroArenaProfile);
  const profileHap = getAddress((await profile.read.HapToken()) as Address);
  if (profileHap !== hapToken) {
    throw new Error(`HeroArenaProfile uses HAP ${profileHap}, expected ${hapToken}`);
  }

  console.log("\n[1/2] Deploying VotingEscrowHAP...");
  const escrow = await viem.deployContract("VotingEscrowHAP", [hapToken]);
  const escrowAddress = getAddress(escrow.address);
  console.log(`VotingEscrowHAP: ${escrowAddress}`);

  console.log("\n[2/2] Deploying VoteEventFactory (creates VotingRewardVault internally)...");
  const factory = await viem.deployContract("VoteEventFactory", [
    escrowAddress,
    heroArenaProfile,
    governanceAdmin,
  ]);
  const factoryAddress = getAddress(factory.address);
  const rewardVaultAddress = getAddress((await factory.read.rewardVault()) as Address);
  console.log(`VoteEventFactory: ${factoryAddress}`);
  console.log(`VotingRewardVault: ${rewardVaultAddress}`);

  const vault = await viem.getContractAt("VotingRewardVault", rewardVaultAddress);
  const eventCreatorRole = await factory.read.EVENT_CREATOR_ROLE();
  const checks = {
    factoryEscrow: getAddress((await factory.read.votingEscrow()) as Address) === escrowAddress,
    factoryProfile: getAddress((await factory.read.heroArenaProfile()) as Address) === heroArenaProfile,
    factoryHap: getAddress((await factory.read.hap()) as Address) === hapToken,
    factoryOwner: getAddress((await factory.read.owner()) as Address) === governanceAdmin,
    adminCanCreateEvents: await factory.read.hasRole([eventCreatorRole, governanceAdmin]),
    vaultFactory: getAddress((await vault.read.factory()) as Address) === factoryAddress,
    vaultHap: getAddress((await vault.read.hap()) as Address) === hapToken,
  };
  const failedChecks = Object.entries(checks).filter(([, passed]) => !passed);
  if (failedChecks.length !== 0) {
    throw new Error(`Post-deployment checks failed: ${failedChecks.map(([name]) => name).join(", ")}`);
  }

  // HAP blacklist protection is essential: otherwise locked deposits or reward
  // payouts can be frozen. Apply it when this deployer is still a HAP admin;
  // otherwise emit exact calldata for the HAP admin multisig.
  const hap = await viem.getContractAt("HapToken", hapToken);
  const defaultAdminRole = await hap.read.DEFAULT_ADMIN_ROLE();
  const deployerIsHapAdmin = await hap.read.hasRole([defaultAdminRole, deployer]);
  const protectedContracts: Address[] = [];
  const pendingAdminCalls: Array<{ target: Address; data: Hex; description: string }> = [];

  for (const [name, address] of [
    ["VotingEscrowHAP", escrowAddress],
    ["VotingRewardVault", rewardVaultAddress],
  ] as const) {
    if (await hap.read.protectedFromBlacklist([address])) {
      protectedContracts.push(address);
      continue;
    }

    if (deployerIsHapAdmin) {
      const hash = await hap.write.setProtected([address, true]);
      await publicClient.waitForTransactionReceipt({ hash });
      if (!(await hap.read.protectedFromBlacklist([address]))) {
        throw new Error(`Failed to protect ${name} from the HAP blacklist`);
      }
      protectedContracts.push(address);
      console.log(`Protected ${name} from the HAP blacklist`);
    } else {
      pendingAdminCalls.push({
        target: hapToken,
        data: encodeFunctionData({
          abi: hap.abi,
          functionName: "setProtected",
          args: [address, true],
        }),
        description: `HapToken.setProtected(${address}, true) for ${name}`,
      });
    }
  }

  const deployment = {
    network: networkName,
    chainId,
    deployedAt: new Date().toISOString(),
    deployer,
    governanceAdmin,
    contracts: {
      HapToken: hapToken,
      HeroArenaProfile: heroArenaProfile,
      VotingEscrowHAP: escrowAddress,
      VoteEventFactory: factoryAddress,
      VotingRewardVault: rewardVaultAddress,
    },
    constructorArguments: {
      VotingEscrowHAP: [hapToken],
      VoteEventFactory: [escrowAddress, heroArenaProfile, governanceAdmin],
      VotingRewardVault: [factoryAddress, hapToken],
    },
    checks,
    hapBlacklistProtection: {
      complete: pendingAdminCalls.length === 0,
      protectedContracts,
      pendingAdminCalls,
    },
  };

  const outputFile = `deployment-governance-${networkName}-${chainId}.json`;
  await writeFile(outputFile, `${JSON.stringify(deployment, null, 2)}\n`, "utf8");
  console.log(`\nDeployment record: ${outputFile}`);

  if (pendingAdminCalls.length !== 0) {
    console.warn("\nACTION REQUIRED: the HAP admin multisig must execute these calls before use:");
    for (const call of pendingAdminCalls) {
      console.warn(`- ${call.description}`);
      console.warn(`  target: ${call.target}`);
      console.warn(`  data:   ${call.data}`);
    }
  }

  console.log("\nVoteEvent is intentionally not deployed here; each event is created by VoteEventFactory.");
}

await main();
