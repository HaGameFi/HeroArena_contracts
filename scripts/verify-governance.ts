// Verify the Hero Arena governance contracts on the configured explorer.
//
// Required:
//   VOTING_ESCROW_HAP_ADDRESS=0x...
//   VOTE_EVENT_FACTORY_ADDRESS=0x...
//   VOTING_REWARD_VAULT_ADDRESS=0x...
//
// Optional: comma-separated VoteEvent addresses to verify as well:
//   VOTE_EVENT_ADDRESSES=0x...,0x...
//
// Usage:
//   pnpm hardhat run scripts/verify-governance.ts --network bscTestnet

import hre, { network } from "hardhat";
import { getAddress, isAddress, zeroAddress, type Address } from "viem";

const DEFAULTS = {
  hapToken: "0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f",
  heroArenaProfile: "0x48B3f5Ea324d8e0AFaF63c8469f664Bc659B3bbc",
  governanceAdmin: "0x02334708A7069993fe7f14cdbfC9863AcF3598C4",
} as const;



function addressFromEnv(variable: string, fallback?: string): Address {
  const value = process.env[variable] ?? fallback;
  if (value === undefined || !isAddress(value) || value.toLowerCase() === zeroAddress) {
    throw new Error(`${variable} must be set to a valid non-zero address`);
  }
  return getAddress(value);
}

async function main() {
  const hapToken = addressFromEnv("HAP_TOKEN_ADDRESS", DEFAULTS.hapToken);
  const heroArenaProfile = addressFromEnv(
    "HERO_ARENA_PROFILE_ADDRESS",
    DEFAULTS.heroArenaProfile,
  );
  const governanceAdmin = addressFromEnv(
    "GOVERNANCE_ADMIN_ADDRESS",
    DEFAULTS.governanceAdmin,
  );
  const escrowAddress = addressFromEnv("VOTING_ESCROW_HAP_ADDRESS");
  const factoryAddress = addressFromEnv("VOTE_EVENT_FACTORY_ADDRESS");
  const rewardVaultAddress = addressFromEnv("VOTING_REWARD_VAULT_ADDRESS");
  const eventAddresses = (process.env.VOTE_EVENT_ADDRESSES ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length !== 0)
    .map((value, index) => {
      if (!isAddress(value) || value.toLowerCase() === zeroAddress) {
        throw new Error(`VOTE_EVENT_ADDRESSES[${index}] is invalid: ${value}`);
      }
      return getAddress(value);
    });

  const connection = await network.connect();
  const { viem, networkName } = connection;
  const publicClient = await viem.getPublicClient();
  console.log(`Verifying governance contracts on ${networkName} (${await publicClient.getChainId()})`);

  for (const address of [escrowAddress, factoryAddress, rewardVaultAddress, ...eventAddresses]) {
    const bytecode = await publicClient.getCode({ address });
    if (bytecode === undefined || bytecode === "0x") {
      throw new Error(`No deployed bytecode at ${address}`);
    }
  }

  // Check that supplied addresses belong to one internally consistent deployment.
  const factory = await viem.getContractAt("VoteEventFactory", factoryAddress);
  if (getAddress((await factory.read.votingEscrow()) as Address) !== escrowAddress) {
    throw new Error("VOTE_EVENT_FACTORY_ADDRESS points to a different VotingEscrowHAP");
  }
  if (getAddress((await factory.read.heroArenaProfile()) as Address) !== heroArenaProfile) {
    throw new Error("VOTE_EVENT_FACTORY_ADDRESS points to a different HeroArenaProfile");
  }
  if (getAddress((await factory.read.hap()) as Address) !== hapToken) {
    throw new Error("VOTE_EVENT_FACTORY_ADDRESS points to a different HAP token");
  }
  if (getAddress((await factory.read.owner()) as Address) !== governanceAdmin) {
    throw new Error("VOTE_EVENT_FACTORY_ADDRESS has a different constructor owner");
  }
  if (getAddress((await factory.read.rewardVault()) as Address) !== rewardVaultAddress) {
    throw new Error("VOTING_REWARD_VAULT_ADDRESS does not belong to this factory");
  }

  // Run the explorer task directly. The aggregate `verify` task also runs
  // Sourcify and communicates provider failures through process.exitCode;
  // that makes an already-verified Sourcify contract look like a failure of
  // the current contract and hides which explorer actually failed.
  const verifyTask = hre.tasks.getTask(["verify", "etherscan"]);
  async function verify(
    label: string,
    address: Address,
    constructorArgs: unknown[],
    contract: string,
  ) {
    console.log(`\nVerifying ${label}: ${address}`);
    await verifyTask.run({
      address,
      constructorArgs,
      contract,
      force: false,
    });
  }

  await verify(
    "VotingEscrowHAP",
    escrowAddress,
    [hapToken],
    "contracts/governance/VotingEscrowHAP.sol:VotingEscrowHAP",
  );
  await verify(
    "VoteEventFactory",
    factoryAddress,
    [escrowAddress, heroArenaProfile, governanceAdmin],
    "contracts/governance/VoteEventFactory.sol:VoteEventFactory",
  );
  await verify(
    "VotingRewardVault",
    rewardVaultAddress,
    [factoryAddress, hapToken],
    "contracts/governance/VotingRewardVault.sol:VotingRewardVault",
  );

  for (const eventAddress of eventAddresses) {
    if (!(await factory.read.isVoteEvent([eventAddress]))) {
      throw new Error(`${eventAddress} is not registered by VoteEventFactory`);
    }
    const event = await viem.getContractAt("VoteEvent", eventAddress);
    const constructorArgs = [
      escrowAddress,
      heroArenaProfile,
      factoryAddress,
      await event.read.creator(),
      await event.read.startTime(),
      await event.read.endTime(),
      await event.read.quorumVotePower(),
      await event.read.options(),
      await event.read.metadataURI(),
    ];
    await verify(
      "VoteEvent",
      eventAddress,
      constructorArgs,
      "contracts/governance/VoteEvent.sol:VoteEvent",
    );
  }
}

await main();
