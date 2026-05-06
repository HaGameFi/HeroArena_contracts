// scripts/verify.ts
// Reads the most recent deployment-*.json record and verifies all three
// contracts on BscScan in one go.
//
// Usage:
//   pnpm hardhat run scripts/verify.ts --network bscMainnet
//
// The --network flag is required by hardhat's runner but the actual network
// for verification is read from the deployment JSON (so it always matches the
// contract being verified).

import { readFile, readdir } from "node:fs/promises";
import { spawn } from "node:child_process";

// ============================================================================
// Locate the most recent deployment record in the project root
// ============================================================================

const files = (await readdir("."))
  .filter(f => /^deployment-.+\.json$/.test(f))
  .sort()
  .reverse();

if (files.length === 0) {
  console.error("❌  No deployment-*.json file found in project root.");
  console.error("    Run scripts/deploy.ts first.\n");
  process.exit(1);
}

const latestFile = files[0];
const record = JSON.parse(await readFile(latestFile, "utf-8")) as {
  network: string;
  deployedAt: string;
  deployer: string;
  guardianMultisig: string;
  tgeTimestamp: number;
  contracts: { HapToken: string; HapVesting: string; HapTreasury: string };
};

console.log(`📄  Using deployment record: ${latestFile}`);
console.log(`    Network:     ${record.network}`);
console.log(`    Deployed at: ${record.deployedAt}\n`);

const NETWORK = record.network;

// ============================================================================
// Verify one contract via subprocess `hardhat verify`
// ============================================================================

function verify(label: string, address: string, args: (string | number)[]) {
  return new Promise<number>((resolve) => {
    console.log(`\n${"━".repeat(60)}`);
    console.log(`Verifying ${label}  →  ${address}`);
    console.log("━".repeat(60));

    const proc = spawn(
      "npx",
      ["hardhat", "verify", "--network", NETWORK, address, ...args.map(String)],
      { stdio: "inherit" }
    );

    // Don't reject on non-zero — "already verified" exits non-zero but is fine.
    proc.on("close", code => resolve(code ?? 0));
  });
}

// ============================================================================
// Run all three verifications sequentially
// ============================================================================

await verify("HapToken", record.contracts.HapToken, [record.deployer]);

await verify("HapVesting", record.contracts.HapVesting, [
  record.contracts.HapToken,
  record.tgeTimestamp,
  record.deployer,
]);

await verify("HapTreasury", record.contracts.HapTreasury, [
  record.deployer,
  record.guardianMultisig,
]);

console.log(`\n${"━".repeat(60)}`);
console.log("✅  Verification run complete.");
console.log("    Check BscScan to confirm each contract shows");
console.log("    'Contract Source Code Verified' before announcing addresses.");
console.log(`${"━".repeat(60)}\n`);
