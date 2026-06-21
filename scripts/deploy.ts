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
const TGE_TIMESTAMP_RAW = 1782009000; // TODO: set real TGE unix timestamp (seconds) 必须大于1小时

// Gnosis Safe 3-of-5 multisig — will receive DEFAULT_ADMIN_ROLE on all contracts
const ADMIN_MULTISIG    = "0x02334708A7069993fe7f14cdbfC9863AcF3598C4"; // TODO: real admin multisig

// Independent guardian multisig — holds GUARDIAN_ROLE on HapTreasury only
// Must be a different address from ADMIN_MULTISIG
const GUARDIAN_MULTISIG = "0xd861Af70b9414762873Ad7387b95E96c6f6E8140"; // TODO: real guardian multisig

// Vesting beneficiary addresses (one per token category)
const BENEFICIARIES = {
  // 70 M  — immediate TGE unlock; send straight to DEX liquidity pool wallet
  LIQUIDITY:       ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000010", // TODO

  // 350 M — 1-month cliff, 60-month linear; game reward distribution contract
  P2E_REWARDS:     ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000011", // TODO

  // 100 M — 1-month cliff, 48-month linear; staking reward distributor
  STAKING_REWARDS: ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000012", // TODO

  // 120 M — 5 % TGE, 3-month cliff, 36-month linear; ecosystem fund multisig
  ECOSYSTEM:       ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000013", // TODO

  // 150 M — 12-month cliff, 36-month linear; team multisig (revocable)
  TEAM:            ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000014", // TODO

  // 30 M  — 6-month cliff, 24-month linear; advisors (revocable)
  ADVISORS:        ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000015", // TODO

  // 100 M — 12-month cliff, 48-month linear; protocol reserve multisig
  TREASURY:        ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000016", // TODO

  // 40 M  — 10 % TGE, 0-month cliff, 18-month linear; marketing wallet
  MARKETING:       ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000017", // TODO

  // 10 M  — 50 % TGE, 0-month cliff, 6-month linear; airdrop distributor
  AIRDROP:         ADMIN_MULTISIG,//"0x0000000000000000000000000000000000000018", // TODO
} as const;

// Launchpad vault that receives the 30 M public IDO allocation at TGE
const IDO_VAULT = ADMIN_MULTISIG;//"0x0000000000000000000000000000000000000019"; // TODO: Kommunitas vault

// ============================================================================
// Internal constants (do not change)
// ============================================================================

const ONE_MONTH = 30n * 24n * 60n * 60n; // 30 days in seconds (bigint)

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
    if (TGE_TIMESTAMP_RAW <= nowSec) {
      errors.push(`TGE_TIMESTAMP_RAW ${TGE_TIMESTAMP_RAW} is in the past (now=${nowSec})`);
    }
  }

  if (TODO_PLACEHOLDER.test(ADMIN_MULTISIG))    errors.push("ADMIN_MULTISIG is placeholder");
  if (TODO_PLACEHOLDER.test(GUARDIAN_MULTISIG)) errors.push("GUARDIAN_MULTISIG is placeholder");
  if ((ADMIN_MULTISIG as string) === (GUARDIAN_MULTISIG as string)) errors.push("ADMIN_MULTISIG and GUARDIAN_MULTISIG must differ");
  if (TODO_PLACEHOLDER.test(IDO_VAULT))         errors.push("IDO_VAULT is placeholder");

  for (const [key, addr] of Object.entries(BENEFICIARIES)) {
    if (TODO_PLACEHOLDER.test(addr as string)) {
      errors.push(`BENEFICIARIES.${key} is placeholder`);
    }
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
// Vesting schedule definitions (9 tranches, 970 M HAP total)
// ============================================================================

function buildSchedules() {
  const TGE = BigInt(TGE_TIMESTAMP_RAW);

  return [
    {
      label:       LABEL("LIQUIDITY"),
      beneficiary: BENEFICIARIES.LIQUIDITY,
      total:       parseEther("70000000"),
      tgeAmount:   parseEther("70000000"),  // 100 % at TGE
      cliff:       0n,
      vesting:     0n,
      revocable:   false,
    },
    {
      label:       LABEL("P2E_REWARDS"),
      beneficiary: BENEFICIARIES.P2E_REWARDS,
      total:       parseEther("350000000"),
      tgeAmount:   0n,
      cliff:       ONE_MONTH,
      vesting:     60n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("STAKING_REWARDS"),
      beneficiary: BENEFICIARIES.STAKING_REWARDS,
      total:       parseEther("100000000"),
      tgeAmount:   0n,
      cliff:       ONE_MONTH,
      vesting:     48n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("ECOSYSTEM"),
      beneficiary: BENEFICIARIES.ECOSYSTEM,
      total:       parseEther("120000000"),
      tgeAmount:   parseEther("6000000"),   // 5 % at TGE
      cliff:       3n * ONE_MONTH,
      vesting:     36n * ONE_MONTH,
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
      total:       parseEther("30000000"),
      tgeAmount:   0n,
      cliff:       6n * ONE_MONTH,
      vesting:     24n * ONE_MONTH,
      revocable:   true,
    },
    {
      label:       LABEL("TREASURY"),
      beneficiary: BENEFICIARIES.TREASURY,
      total:       parseEther("100000000"),
      tgeAmount:   0n,
      cliff:       12n * ONE_MONTH,
      vesting:     48n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("MARKETING"),
      beneficiary: BENEFICIARIES.MARKETING,
      total:       parseEther("40000000"),
      tgeAmount:   parseEther("4000000"),   // 10 % at TGE
      cliff:       0n,
      vesting:     18n * ONE_MONTH,
      revocable:   false,
    },
    {
      label:       LABEL("AIRDROP"),
      beneficiary: BENEFICIARIES.AIRDROP,
      total:       parseEther("10000000"),
      tgeAmount:   parseEther("5000000"),   // 50 % at TGE
      cliff:       0n,
      vesting:     6n * ONE_MONTH,
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
// Step 5 — Fund vesting contract + create 9 schedules
// ============================================================================

console.log(`\n${sep("-")}`);
console.log("[5/6] Funding vesting and creating schedules...");

// Transfer 970 M HAP to HapVesting (30 M IDO kept in deployer for next step)
hash = await token.write.transfer([vestingAddress, parseEther("970000000")]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ 970 M HAP → HapVesting");

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

console.log("  ✓ Schedules created. Total scheduled:", formatEther(totalScheduled), "HAP");

// Transfer 30 M IDO allocation to launchpad vault
hash = await token.write.transfer([IDO_VAULT, parseEther("30000000")]);
await publicClient.waitForTransactionReceipt({ hash });
console.log("  ✓ 30 M HAP → IDO vault:", shortAddr(IDO_VAULT));

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
  idoVault:      IDO_VAULT,
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
