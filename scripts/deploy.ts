// scripts/deploy.ts
// Hero Arena BSC Mainnet — production deployment script
//
// Usage:
//   npx hardhat run scripts/deploy.ts --network bscMainnet
//
// Prerequisites:
//   - .env: DEPLOYER_PRIVATE_KEY  (deployer EOA, ≥ 0.5 BNB for gas)
//   - .env: BSCSCAN_API_KEY       (for post-deploy verification)
//   - All TODO addresses below must be replaced with real values before running

import { network } from "hardhat";
import { parseEther, padHex, stringToHex, formatEther } from "viem";
import { writeFile } from "node:fs/promises";

// ============================================================================
// ⚙️  CONFIGURATION — edit ALL values before mainnet deployment
// ============================================================================

// TGE Unix timestamp (seconds). Must be in the future.
// Compute: Math.floor(new Date("2026-09-01T12:00:00Z").getTime() / 1000)
const TGE_TIMESTAMP_RAW = 0; // TODO: set signed launch-document TGE timestamp, at least 1 hour in the future

// Gnosis Safe 3-of-5 multisig — will receive DEFAULT_ADMIN_ROLE on all contracts
const ADMIN_MULTISIG    = "0x02334708A7069993fe7f14cdbfC9863AcF3598C4"; // TODO: real admin multisig

// Independent guardian multisig — holds GUARDIAN_ROLE on HapTreasury only
// Must be a different address from ADMIN_MULTISIG
const GUARDIAN_MULTISIG = "0xd861Af70b9414762873Ad7387b95E96c6f6E8140"; // TODO: real guardian multisig

// Vesting beneficiary addresses (one per token category)
const BENEFICIARIES = {
  // 9 M — initial PancakeSwap liquidity released at TGE. The other 41 M of
  // Liquidity & Listings is deposited into HapTreasury as a non-circulating reserve.
  INITIAL_LIQUIDITY: ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000010", // TODO: LP provisioning wallet

  // 30 M — 20% at TGE, remaining 80% over 8 months; approved launchpad vault
  PUBLIC_IDO:        ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000011", // TODO

  // 25 M — 3-month cliff, 18-month release; signed strategic/incubator agreements
  STRATEGIC:         ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000012", // TODO

  // 280 M — 3-month cliff, performance-based maximum budget over 72 months
  PLAYER_REWARDS:    ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000013", // TODO: reward controller

  // 60 M — 3-month cliff, dynamic maximum budget over 48 months
  STAKING_REWARDS:   ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000014", // TODO

  // 125 M — 3-month cliff, 48-month availability subject to partner milestones
  ECOSYSTEM:         ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000015", // TODO

  // 150 M — 12-month cliff, 36-month linear; team multisig (revocable)
  TEAM:              ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000016", // TODO

  // 20 M — 6-month cliff, 24-month linear; advisors (revocable)
  ADVISORS:          ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000017", // TODO

  // 150 M — 12-month cliff, 48-month linear; protocol reserve multisig
  TREASURY:          ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000018", // TODO

  // 70 M — 5% at TGE, remaining allocation over 24 months
  MARKETING:         ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000019", // TODO

  // 40 M — 10% at TGE, remaining allocation over 12 months
  COMMUNITY:         ADMIN_MULTISIG,//"0x000000000000000000000000000000000000001a", // TODO
} as const;

// ============================================================================
// Internal constants (do not change)
// ============================================================================

const ONE_MONTH = 30n * 24n * 60n * 60n; // 30 days in seconds (bigint)
const VESTING_FUND = parseEther("959000000");
const LIQUIDITY_LISTINGS_RESERVE = parseEther("41000000");
const EXPECTED_TGE_CIRCULATION = parseEther("22500000");

/** Right-pads a string to bytes32, matching ethers.encodeBytes32String() */
const LABEL = (s: string): `0x${string}` =>
  padHex(stringToHex(s), { size: 32, dir: "right" });

const TODO_PLACEHOLDER = /^0x000000000000000000000000000000000000000[0-9a-f]$/i;

// ============================================================================
// Config validation — aborts early if any placeholder is still present
// ============================================================================

function validateConfig() {
  const errors: string[] = [];

  if (TGE_TIMESTAMP_RAW.toString() === "0") {
    errors.push("TGE_TIMESTAMP_RAW is 0 — set a real Unix timestamp");
  } else {
    const nowSec = Math.floor(Date.now() / 1000);
    if (TGE_TIMESTAMP_RAW <= nowSec + 3600) {
      errors.push(`TGE_TIMESTAMP_RAW ${TGE_TIMESTAMP_RAW} must be more than 1 hour in the future (now=${nowSec})`);
    }
  }

  if (TODO_PLACEHOLDER.test(ADMIN_MULTISIG))    errors.push("ADMIN_MULTISIG is placeholder");
  if (TODO_PLACEHOLDER.test(GUARDIAN_MULTISIG)) errors.push("GUARDIAN_MULTISIG is placeholder");
  if ((ADMIN_MULTISIG as string) === (GUARDIAN_MULTISIG as string)) errors.push("ADMIN_MULTISIG and GUARDIAN_MULTISIG must differ");
  for (const [key, addr] of Object.entries(BENEFICIARIES)) {
    if (TODO_PLACEHOLDER.test(addr as string)) {
      errors.push(`BENEFICIARIES.${key} is placeholder`);
    }
  }

  const schedules = buildSchedules();
  const scheduled = schedules.reduce((sum, schedule) => sum + schedule.total, 0n);
  const tgeCirculation = schedules.reduce((sum, schedule) => sum + schedule.tgeAmount, 0n);
  if (scheduled !== VESTING_FUND) {
    errors.push(`vesting schedules total ${formatEther(scheduled)} HAP, expected 959,000,000`);
  }
  if (tgeCirculation !== EXPECTED_TGE_CIRCULATION) {
    errors.push(`TGE circulation ${formatEther(tgeCirculation)} HAP, expected 22,500,000`);
  }
  if (scheduled + LIQUIDITY_LISTINGS_RESERVE !== parseEther("1000000000")) {
    errors.push("vesting plus Liquidity & Listings reserve does not equal 1,000,000,000 HAP");
  }

  if (errors.length > 0) {
    console.error("\n❌  Configuration errors — fix these before deploying:\n");
    errors.forEach(e => console.error(`   • ${e}`));
    console.error(
      "\nEdit the CONFIG section at the top of scripts/deploy.ts and re-run.\n"
    );
    process.exit(1);
  }
}

// ============================================================================
// Vesting schedule definitions (11 tranches, 959 M HAP total)
//
// HapVesting releases continuously and linearly. GitBook's "monthly" wording
// is represented here as the same maximum contractual availability over the
// stated number of months; claiming does not automatically distribute budgets.
// ============================================================================

function buildSchedules() {
  return [
    {
      label:       LABEL("INITIAL_LIQUIDITY"),
      beneficiary: BENEFICIARIES.INITIAL_LIQUIDITY,
      total:       parseEther("9000000"),
      tgeAmount:   parseEther("9000000"), // US$90k / US$0.01 reference price
      cliff:       0n,
      vesting:     0n,
      revocable:   false,
    },
    {
      label:       LABEL("PUBLIC_IDO"),
      beneficiary: BENEFICIARIES.PUBLIC_IDO,
      total:       parseEther("30000000"),
      tgeAmount:   parseEther("6000000"), // 20% at TGE
      cliff:       0n,
      vesting:     8n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("STRATEGIC"),
      beneficiary: BENEFICIARIES.STRATEGIC,
      total:       parseEther("25000000"),
      tgeAmount:   0n,
      cliff:       3n * ONE_MONTH,
      vesting:     18n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("PLAYER_REWARDS"),
      beneficiary: BENEFICIARIES.PLAYER_REWARDS,
      total:       parseEther("280000000"),
      tgeAmount:   0n,
      cliff:       3n * ONE_MONTH,
      vesting:     72n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("STAKING_REWARDS"),
      beneficiary: BENEFICIARIES.STAKING_REWARDS,
      total:       parseEther("60000000"),
      tgeAmount:   0n,
      cliff:       3n * ONE_MONTH,
      vesting:     48n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("ECOSYSTEM"),
      beneficiary: BENEFICIARIES.ECOSYSTEM,
      total:       parseEther("125000000"),
      tgeAmount:   0n,
      cliff:       3n * ONE_MONTH,
      vesting:     48n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("TEAM"),
      beneficiary: BENEFICIARIES.TEAM,
      total:       parseEther("150000000"),
      tgeAmount:   0n,
      cliff:       12n * ONE_MONTH,
      vesting:     36n * ONE_MONTH,
      revocable:   true,
    },
    {
      label:       LABEL("ADVISORS"),
      beneficiary: BENEFICIARIES.ADVISORS,
      total:       parseEther("20000000"),
      tgeAmount:   0n,
      cliff:       6n * ONE_MONTH,
      vesting:     24n * ONE_MONTH,
      revocable:   true,
    },
    {
      label:       LABEL("TREASURY"),
      beneficiary: BENEFICIARIES.TREASURY,
      total:       parseEther("150000000"),
      tgeAmount:   0n,
      cliff:       12n * ONE_MONTH,
      vesting:     48n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("MARKETING"),
      beneficiary: BENEFICIARIES.MARKETING,
      total:       parseEther("70000000"),
      tgeAmount:   parseEther("3500000"), // 5% at TGE
      cliff:       0n,
      vesting:     24n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("COMMUNITY"),
      beneficiary: BENEFICIARIES.COMMUNITY,
      total:       parseEther("40000000"),
      tgeAmount:   parseEther("4000000"), // 10% at TGE
      cliff:       0n,
      vesting:     12n * ONE_MONTH,
      revocable:   false,
    },
  ];
}

// ============================================================================
// Helpers
// ============================================================================

function sep(char = "=", width = 70) {
  return char.repeat(width);
}

function shortAddr(addr: string) {
  return `${addr.slice(0, 10)}...${addr.slice(-6)}`;
}

// ============================================================================
// Main deployment
// ============================================================================

// 1. Connect using the --network flag passed on the CLI
//    (e.g. --network bscMainnet | bscTestnet | sepolia)
const connection = await network.connect();
const { viem } = connection;
const NETWORK_NAME =
  (connection as any).networkName ??
  (connection as any).config?.name ??
  "unknown";

console.log(sep());
console.log(`Hero Arena Deployment  →  network: ${NETWORK_NAME}`);
console.log(sep());

// 2. Validate config
validateConfig();

const publicClient = await viem.getPublicClient();
const [deployerClient] = await viem.getWalletClients();

const deployer = deployerClient.account.address;
const balance  = await publicClient.getBalance({ address: deployer });

console.log("\nDeployer:     ", deployer);
console.log("Admin multisig:", shortAddr(ADMIN_MULTISIG));
console.log("Guardian:     ", shortAddr(GUARDIAN_MULTISIG));
console.log("Deployer BNB: ", formatEther(balance), "BNB");
console.log(
  "TGE:          ",
  TGE_TIMESTAMP_RAW,
  `(${new Date(TGE_TIMESTAMP_RAW * 1000).toISOString()})`
);

if (balance < parseEther("0.3")) {
  console.error("\n❌  Deployer balance < 0.3 BNB — top up before deploying.");
  process.exit(1);
}

// ============================================================================
// Step 1 — Deploy HapToken
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[1/6] Deploying HapToken...");

const token = await viem.deployContract("HapToken", [deployer]);
const tokenAddress = token.address;

const totalSupply = await token.read.totalSupply();
console.log("✓ HapToken:   ", tokenAddress);
console.log("  Total supply:", formatEther(totalSupply), "HAP");

// ============================================================================
// Step 2 — Deploy HapVesting
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[2/6] Deploying HapVesting...");

const TGE = BigInt(TGE_TIMESTAMP_RAW);
const vesting = await viem.deployContract("HapVesting", [tokenAddress, TGE, deployer]);
const vestingAddress = vesting.address;
console.log("✓ HapVesting: ", vestingAddress);

// ============================================================================
// Step 3 — Deploy HapTreasury
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[3/6] Deploying HapTreasury...");

const treasury = await viem.deployContract("HapTreasury", [deployer, GUARDIAN_MULTISIG]);
const treasuryAddress = treasury.address;
console.log("✓ HapTreasury:", treasuryAddress);

// ============================================================================
// Step 4 — Blacklist-protect core protocol contracts
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[4/6] Registering protocol contracts as blacklist-protected...");

let hash = await token.write.setProtected([vestingAddress, true]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ HapVesting protected");

hash = await token.write.setProtected([treasuryAddress, true]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ HapTreasury protected");

// ============================================================================
// Step 5 — Fund vesting, reserve Liquidity & Listings, create 11 schedules
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[5/6] Funding tokenomics allocations and creating schedules...");

// 959 M is contractually available through vesting schedules. The remaining
// 41 M is the undeployed Liquidity & Listings reserve held in HapTreasury.
hash = await token.write.transfer([vestingAddress, VESTING_FUND]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ 959 M HAP → HapVesting");

hash = await token.write.approve([treasuryAddress, LIQUIDITY_LISTINGS_RESERVE]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await treasury.write.receiveFunds([
  tokenAddress,
  LIQUIDITY_LISTINGS_RESERVE,
  "LIQUIDITY_LISTINGS_RESERVE",
]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ 41 M HAP → HapTreasury (non-circulating Liquidity & Listings reserve)");

const schedules = buildSchedules();
let totalScheduled = 0n;

for (const s of schedules) {
  const name = s.label; // bytes32 hex
  console.log(`  Creating schedule ${name.slice(0, 10)}... (${s.beneficiary.slice(0, 10)}...)`);

  hash = await vesting.write.createVestingSchedule([
    s.beneficiary,
    s.label,
    s.total,
    s.tgeAmount,
    s.cliff,
    s.vesting,
    s.revocable,
  ]);
  await publicClient.waitForTransactionReceipt({ hash });
  totalScheduled += s.total;
}

console.log("  ✓ 11 schedules created. Total scheduled:", formatEther(totalScheduled), "HAP");
console.log("  ✓ Maximum TGE circulation:", formatEther(EXPECTED_TGE_CIRCULATION), "HAP (2.25%)");

// Sanity check: deployer should have ~0 HAP remaining
const deployerBalance = await token.read.balanceOf([deployer]);
if (deployerBalance > 0n) {
  console.warn(
    `  ⚠️  Deployer still holds ${formatEther(deployerBalance)} HAP — verify allocations sum to 1 B`
  );
}

// ============================================================================
// Step 6 — Role handoff: grant all roles to ADMIN_MULTISIG, revoke from deployer
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[6/6] Handing off roles to admin multisig...");

const DEFAULT_ADMIN_ROLE  = "0x0000000000000000000000000000000000000000000000000000000000000000" as `0x${string}`;
const PAUSER_ROLE         = await token.read.PAUSER_ROLE();
const BLACKLIST_ROLE      = await token.read.BLACKLIST_ROLE();
const VESTING_ADMIN_ROLE  = await vesting.read.VESTING_ADMIN_ROLE();
const PROPOSAL_ROLE       = await treasury.read.PROPOSAL_ROLE();
const EXECUTOR_ROLE       = await treasury.read.EXECUTOR_ROLE();

// --- HapToken ---
hash = await token.write.grantRole([PAUSER_ROLE,         ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await token.write.grantRole([BLACKLIST_ROLE,      ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await token.write.grantRole([DEFAULT_ADMIN_ROLE,  ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
// Revoke deployer's own admin last (AFTER granting to multisig or we lose admin)
hash = await token.write.revokeRole([BLACKLIST_ROLE,     deployer]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await token.write.revokeRole([PAUSER_ROLE,        deployer]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await token.write.revokeRole([DEFAULT_ADMIN_ROLE, deployer]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ HapToken roles → multisig, revoked from deployer");

// --- HapVesting ---
hash = await vesting.write.grantRole([VESTING_ADMIN_ROLE, ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await vesting.write.grantRole([DEFAULT_ADMIN_ROLE, ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await vesting.write.revokeRole([VESTING_ADMIN_ROLE, deployer]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await vesting.write.revokeRole([DEFAULT_ADMIN_ROLE, deployer]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ HapVesting roles → multisig, revoked from deployer");

// --- HapTreasury ---
hash = await treasury.write.grantRole([PROPOSAL_ROLE,    ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await treasury.write.grantRole([EXECUTOR_ROLE,    ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await treasury.write.grantRole([DEFAULT_ADMIN_ROLE, ADMIN_MULTISIG as `0x${string}`]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await treasury.write.revokeRole([PROPOSAL_ROLE,   deployer]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await treasury.write.revokeRole([EXECUTOR_ROLE,   deployer]);
await publicClient.waitForTransactionReceipt({ hash });
hash = await treasury.write.revokeRole([DEFAULT_ADMIN_ROLE, deployer]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ HapTreasury roles → multisig, revoked from deployer");

// ============================================================================
// Save deployment record to JSON
// ============================================================================

const deploymentRecord = {
  network:        NETWORK_NAME,
  deployedAt:     new Date().toISOString(),
  deployer,
  adminMultisig:  ADMIN_MULTISIG,
  guardianMultisig: GUARDIAN_MULTISIG,
  tgeTimestamp:   TGE_TIMESTAMP_RAW,
  tgeDate:        new Date(TGE_TIMESTAMP_RAW * 1000).toISOString(),
  contracts: {
    HapToken:    tokenAddress,
    HapVesting:  vestingAddress,
    HapTreasury: treasuryAddress,
  },
  beneficiaries: BENEFICIARIES,
  tokenomics: {
    vestingFundHap: formatEther(VESTING_FUND),
    liquidityListingsReserveHap: formatEther(LIQUIDITY_LISTINGS_RESERVE),
    maximumTgeCirculationHap: formatEther(EXPECTED_TGE_CIRCULATION),
    scheduleCount: schedules.length,
  },
};

const outFile = `deployment-${NETWORK_NAME}-${Date.now()}.json`;
await writeFile(outFile, JSON.stringify(deploymentRecord, null, 2));
console.log(`\n📄 Deployment record saved → ${outFile}`);

// ============================================================================
// Summary
// ============================================================================

console.log(`\n${sep()}`);
console.log("✅  Deployment Complete!");
console.log(sep());
console.log("\n📋 Contract Addresses:");
console.log("  HapToken:    ", tokenAddress);
console.log("  HapVesting:  ", vestingAddress);
console.log("  HapTreasury: ", treasuryAddress);
console.log("\n📅 TGE:", TGE_TIMESTAMP_RAW, `(${new Date(TGE_TIMESTAMP_RAW * 1000).toISOString()})`);
console.log("\n🔍 BscScan:");
console.log(`  https://bscscan.com/address/${tokenAddress}`);
console.log(`  https://bscscan.com/address/${vestingAddress}`);
console.log(`  https://bscscan.com/address/${treasuryAddress}`);

console.log("\n🔐 Role verification checklist:");
console.log("  Run on BscScan to confirm deployer holds NO roles:");
console.log(`  HapToken.hasRole(DEFAULT_ADMIN_ROLE, ${deployer}) → false`);
console.log(`  HapVesting.hasRole(DEFAULT_ADMIN_ROLE, ${deployer}) → false`);
console.log(`  HapTreasury.hasRole(DEFAULT_ADMIN_ROLE, ${deployer}) → false`);

console.log("\n🛠️  Verify contracts:");
console.log(
  `  npx hardhat verify --network ${NETWORK_NAME} ${tokenAddress} ${deployer}`
);
console.log(
  `  npx hardhat verify --network ${NETWORK_NAME} ${vestingAddress} ${tokenAddress} ${TGE_TIMESTAMP_RAW} ${deployer}`
);
console.log(
  `  npx hardhat verify --network ${NETWORK_NAME} ${treasuryAddress} ${deployer} ${GUARDIAN_MULTISIG}`
);

console.log();
