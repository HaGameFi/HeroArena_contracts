import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, padHex, parseEther, stringToHex, zeroAddress } from "viem";

// ─── Helpers ─────────────────────────────────────────────────────────────────

const ONE_MONTH = 30n * 24n * 60n * 60n;
const ONE_HOUR  = 3600n;
const P = parseEther;

// Right-zero-padded bytes32 — matches ethers.encodeBytes32String()
const LABEL = (s: string): `0x${string}` =>
  padHex(stringToHex(s), { size: 32, dir: "right" });

// ─── Suite ───────────────────────────────────────────────────────────────────

describe("HapSystem", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const testClient   = await viem.getTestClient();

  const [deployerClient, guardianClient, userClient] = await viem.getWalletClients();
  const deployer = deployerClient.account.address;
  const guardian = guardianClient.account.address;
  const user     = userClient.account.address;

  // ── Utility ────────────────────────────────────────────────────────────────

  async function advanceTimeTo(ts: bigint) {
    await testClient.setNextBlockTimestamp({ timestamp: ts });
    await testClient.mine({ blocks: 1 });
  }

  // ── Full-system fixture (mirrors deploy-testnet.ts) ────────────────────────

  async function deploySystem() {
    const block        = await publicClient.getBlock();
    const tgeTimestamp = block.timestamp + 2n * ONE_HOUR + 60n;

    const token    = await viem.deployContract("HapToken",    [deployer]);
    const vesting  = await viem.deployContract("HapVesting",  [token.address, tgeTimestamp, deployer]);
    const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);

    // H-2 fix: protect protocol contracts from blacklisting
    await token.write.setProtected([vesting.address,  true]);
    await token.write.setProtected([treasury.address, true]);

    // Fund vesting (970 M); 30 M stays in deployer wallet as IDO allocation
    await token.write.transfer([vesting.address, P("970000000")]);

    // 9 schedules — identical to deploy-testnet.ts
    const schedules = [
      { beneficiary: deployer,         label: LABEL("LIQUIDITY"),       total: P("70000000"),  tge: P("70000000"), cliff: 0n,            vesting: 0n,            revocable: false },
      { beneficiary: treasury.address, label: LABEL("P2E_REWARDS"),     total: P("350000000"), tge: 0n,            cliff: ONE_MONTH,      vesting: 60n*ONE_MONTH, revocable: false },
      { beneficiary: treasury.address, label: LABEL("STAKING_REWARDS"), total: P("100000000"), tge: 0n,            cliff: ONE_MONTH,      vesting: 48n*ONE_MONTH, revocable: false },
      { beneficiary: treasury.address, label: LABEL("ECOSYSTEM"),       total: P("120000000"), tge: P("6000000"),  cliff: 3n*ONE_MONTH,  vesting: 36n*ONE_MONTH, revocable: false },
      { beneficiary: deployer,         label: LABEL("TEAM"),            total: P("150000000"), tge: 0n,            cliff: 12n*ONE_MONTH, vesting: 36n*ONE_MONTH, revocable: true  },
      { beneficiary: deployer,         label: LABEL("ADVISORS"),        total: P("30000000"),  tge: 0n,            cliff: 6n*ONE_MONTH,  vesting: 24n*ONE_MONTH, revocable: true  },
      { beneficiary: treasury.address, label: LABEL("TREASURY"),        total: P("100000000"), tge: 0n,            cliff: 12n*ONE_MONTH, vesting: 48n*ONE_MONTH, revocable: false },
      { beneficiary: deployer,         label: LABEL("MARKETING"),       total: P("40000000"),  tge: P("4000000"),  cliff: 0n,            vesting: 18n*ONE_MONTH, revocable: false },
      { beneficiary: deployer,         label: LABEL("AIRDROP"),         total: P("10000000"),  tge: P("5000000"),  cliff: 0n,            vesting: 6n*ONE_MONTH,  revocable: false },
    ] as const;

    for (const s of schedules) {
      await vesting.write.createVestingSchedule([
        s.beneficiary, s.label, s.total, s.tge, s.cliff, s.vesting, s.revocable,
      ]);
    }

    return { token, vesting, treasury, tgeTimestamp };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HapToken — deployment
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapToken — deployment", async function () {
    it("mints exactly 1 billion HAP to initialAdmin", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      assert.equal(await token.read.totalSupply(),         P("1000000000"));
      assert.equal(await token.read.balanceOf([deployer]), P("1000000000"));
    });

    it("grants DEFAULT_ADMIN, PAUSER, BLACKLIST roles to initialAdmin", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      assert.ok(await token.read.hasRole([await token.read.DEFAULT_ADMIN_ROLE(), deployer]));
      assert.ok(await token.read.hasRole([await token.read.PAUSER_ROLE(),        deployer]));
      assert.ok(await token.read.hasRole([await token.read.BLACKLIST_ROLE(),     deployer]));
    });

    it("reverts when initialAdmin is zero address", async function () {
      await assert.rejects(viem.deployContract("HapToken", [zeroAddress]));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapToken — burn tracking  (audit fix H-1)
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapToken — burn tracking (H-1)", async function () {
    it("burnFromRevenue() increments totalBurned", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.burnFromRevenue([P("1000"), "WAGER_RAKE"]);
      assert.equal(await token.read.totalBurned(), P("1000"));
    });

    it("standard burn() also increments totalBurned", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.burn([P("500")]);
      assert.equal(await token.read.totalBurned(), P("500"));
    });

    it("totalBurned accumulates across both burn paths", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.burnFromRevenue([P("600"), "RAKE"]);
      await token.write.burn([P("400")]);
      assert.equal(await token.read.totalBurned(), P("1000"));
      // totalSupply must shrink by the same amount
      assert.equal(await token.read.totalSupply(), P("1000000000") - P("1000"));
    });

    it("burnStats() returns consistent burned + remaining", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.burn([P("250")]);
      const stats = await token.read.burnStats();
      // viem returns named tuple outputs as an array: [burned, remaining]
      assert.equal(stats[0], P("250"));
      assert.equal(stats[1], P("1000000000") - P("250"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapToken — blacklist  (audit fix H-2)
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapToken — blacklist (H-2)", async function () {
    it("cannot blacklist the vesting contract (protected)", async function () {
      const { token, vesting } = await deploySystem();
      await assert.rejects(token.write.blacklist([vesting.address]));
    });

    it("cannot blacklist the treasury contract (protected)", async function () {
      const { token, treasury } = await deploySystem();
      await assert.rejects(token.write.blacklist([treasury.address]));
    });

    it("blacklisted sender cannot transfer", async function () {
      const { token } = await deploySystem();
      await token.write.transfer([user, P("1000")]);
      await token.write.blacklist([user]);
      await assert.rejects(
        token.write.transfer([deployer, P("1")], { account: userClient.account }),
      );
    });

    it("blacklisted recipient cannot receive", async function () {
      const { token } = await deploySystem();
      await token.write.blacklist([user]);
      await assert.rejects(token.write.transfer([user, P("1")]));
    });

    it("unblacklist restores transfer ability", async function () {
      const { token } = await deploySystem();
      await token.write.transfer([user, P("1000")]);
      await token.write.blacklist([user]);
      await token.write.unblacklist([user]);
      // must not revert
      await token.write.transfer([deployer, P("1")], { account: userClient.account });
    });

    it("cannot blacklist zero address", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await assert.rejects(token.write.blacklist([zeroAddress]));
    });

    it("non-BLACKLIST_ROLE cannot blacklist", async function () {
      const { token } = await deploySystem();
      await assert.rejects(
        token.write.blacklist([deployer], { account: userClient.account }),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapToken — pause
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapToken — pause", async function () {
    it("paused contract rejects all transfers", async function () {
      const { token } = await deploySystem();
      await token.write.pause();
      await assert.rejects(token.write.transfer([user, P("1")]));
    });

    it("unpause restores transfers", async function () {
      const { token } = await deploySystem();
      await token.write.pause();
      await token.write.unpause();
      await token.write.transfer([user, P("1")]); // must not revert
    });

    it("non-PAUSER_ROLE cannot pause", async function () {
      const { token } = await deploySystem();
      await assert.rejects(token.write.pause({ account: userClient.account }));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — deployment
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — deployment", async function () {
    it("stores hapToken address and tgeTimestamp correctly", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      const block = await publicClient.getBlock();
      const tge   = block.timestamp + 2n * ONE_HOUR + 60n;
      const v = await viem.deployContract("HapVesting", [token.address, tge, deployer]);
      assert.equal(await v.read.hapToken(),       getAddress(token.address));
      assert.equal(await v.read.tgeTimestamp(),   tge);
    });

    it("reverts when TGE is less than 1 hour in the future", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      const block = await publicClient.getBlock();
      await assert.rejects(
        viem.deployContract("HapVesting", [token.address, block.timestamp + 30n * 60n, deployer]),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — post-setup state
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — setup state", async function () {
    it("vesting contract holds 970 M HAP", async function () {
      const { token, vesting } = await deploySystem();
      assert.equal(await token.read.balanceOf([vesting.address]), P("970000000"));
    });

    it("totalAllocated equals 970 M", async function () {
      const { vesting } = await deploySystem();
      assert.equal(await vesting.read.totalAllocated(), P("970000000"));
    });

    it("scheduleCount is 9", async function () {
      const { vesting } = await deploySystem();
      assert.equal(await vesting.read.scheduleCount(), 9n);
    });

    it("deployer retains 30 M HAP (IDO allocation)", async function () {
      const { token } = await deploySystem();
      assert.equal(await token.read.balanceOf([deployer]), P("30000000"));
    });

    it("LIQUIDITY (id=0): vestingDuration=0, 100% TGE", async function () {
      const { vesting } = await deploySystem();
      const s = await vesting.read.getSchedule([0n]);
      assert.equal(s.totalAmount,     P("70000000"));
      assert.equal(s.tgeUnlockAmount, P("70000000"));
      assert.equal(s.vestingDuration, 0n);
      assert.equal(s.revocable,       false);
    });

    it("TEAM (id=4): revocable, cliff=12 months, no TGE unlock", async function () {
      const { vesting } = await deploySystem();
      const s = await vesting.read.getSchedule([4n]);
      assert.equal(s.revocable,      true);
      assert.equal(s.cliffDuration,  12n * ONE_MONTH);
      assert.equal(s.tgeUnlockAmount, 0n);
    });

    it("setProtected flags are set for vesting and treasury", async function () {
      const { token, vesting, treasury } = await deploySystem();
      assert.equal(await token.read.protectedFromBlacklist([vesting.address]),  true);
      assert.equal(await token.read.protectedFromBlacklist([treasury.address]), true);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — before TGE
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — before TGE", async function () {
    it("all 9 schedules have 0 releasable before TGE", async function () {
      const { vesting } = await deploySystem();
      for (let id = 0n; id < 9n; id++) {
        assert.equal(
          await vesting.read.computeReleasableAmount([id]), 0n,
          `schedule ${id} should be 0 before TGE`,
        );
      }
    });

    it("release() reverts before TGE", async function () {
      const { vesting } = await deploySystem();
      await assert.rejects(vesting.write.release([0n]));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — at TGE
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — at TGE", async function () {
    it("LIQUIDITY (id=0) is fully releasable at TGE (70 M)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      assert.equal(await vesting.read.computeReleasableAmount([0n]), P("70000000"));
    });

    it("TEAM (id=4) is not releasable at TGE (cliff=12mo, tge=0)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      assert.equal(await vesting.read.computeReleasableAmount([4n]), 0n);
    });

    it("MARKETING (id=7) has 4 M releasable at TGE (TGE portion)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      assert.equal(await vesting.read.computeReleasableAmount([7n]), P("4000000"));
    });

    it("AIRDROP (id=8) has 5 M releasable at TGE (TGE portion)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      assert.equal(await vesting.read.computeReleasableAmount([8n]), P("5000000"));
    });

    it("ECOSYSTEM (id=3) has 6 M releasable at TGE (TGE portion), despite 3-month cliff", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      // cliff only blocks linear vesting, not the tgeUnlockAmount
      assert.equal(await vesting.read.computeReleasableAmount([3n]), P("6000000"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — release()
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — release()", async function () {
    it("release(0) sends 70 M LIQUIDITY tokens to deployer", async function () {
      const { token, vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      const before = await token.read.balanceOf([deployer]);
      await vesting.write.release([0n]);
      assert.equal(await token.read.balanceOf([deployer]) - before, P("70000000"));
    });

    it("totalReleased is updated after release", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      await vesting.write.release([0n]);
      assert.equal(await vesting.read.totalReleased(), P("70000000"));
    });

    it("double release() reverts (NothingToRelease)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      await vesting.write.release([0n]);
      await assert.rejects(vesting.write.release([0n]));
    });

    it("releaseAllMine() releases ≥79 M for deployer at TGE (70+4+5 M TGE portions)", async function () {
      const { token, vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      const before = await token.read.balanceOf([deployer]);
      await vesting.write.releaseAllMine();
      const released = await token.read.balanceOf([deployer]) - before;
      // At minimum: LIQUIDITY 70M + MARKETING 4M TGE + AIRDROP 5M TGE = 79M.
      // A few blocks may have elapsed by the time the tx is mined, adding a tiny
      // linear-vesting increment on MARKETING/AIRDROP (cliff=0), so we allow up
      // to +10 000 HAP (≈ linear rate × 3 600 s, far beyond any test window).
      assert.ok(released >= P("79000000"), `released ${released} < 79M`);
      assert.ok(released < P("79000000") + P("10000"), `released ${released} unexpectedly large`);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — revoke()  (audit fix L-4: auto-release vested portion)
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — revoke() (L-4)", async function () {
    it("revokes TEAM (id=4) — marks schedule as revoked", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      await vesting.write.revoke([4n]);
      const s = await vesting.read.getSchedule([4n]);
      assert.equal(s.revoked, true);
    });

    it("revoke on non-revocable schedule reverts", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      await assert.rejects(vesting.write.revoke([0n])); // LIQUIDITY not revocable
    });

    it("double revoke() reverts (AlreadyRevoked)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      await vesting.write.revoke([4n]);
      await assert.rejects(vesting.write.revoke([4n]));
    });

    it("non-VESTING_ADMIN_ROLE cannot revoke", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      await advanceTimeTo(tgeTimestamp);
      await assert.rejects(
        vesting.write.revoke([4n], { account: userClient.account }),
      );
    });

    it("auto-releases vested portion to beneficiary on revoke", async function () {
      const { token, vesting, tgeTimestamp } = await deploySystem();
      // Advance past ADVISORS cliff (6 months) so some tokens are vested
      await advanceTimeTo(tgeTimestamp + 6n * ONE_MONTH + ONE_HOUR);
      const before = await token.read.balanceOf([deployer]);
      await vesting.write.revoke([5n]); // ADVISORS (id=5), revocable
      const after = await token.read.balanceOf([deployer]);
      // Some tokens should have been auto-released (vested > 0 past cliff)
      assert.ok(after > before, "auto-release should have transferred vested tokens");
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapTreasury — deployment
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapTreasury — deployment", async function () {
    it("grants correct roles", async function () {
      const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);
      assert.ok(await treasury.read.hasRole([await treasury.read.DEFAULT_ADMIN_ROLE(), deployer]));
      assert.ok(await treasury.read.hasRole([await treasury.read.GUARDIAN_ROLE(),      guardian]));
      assert.ok(await treasury.read.hasRole([await treasury.read.PROPOSAL_ROLE(),      deployer]));
      assert.ok(await treasury.read.hasRole([await treasury.read.EXECUTOR_ROLE(),      deployer]));
    });

    it("reverts when admin equals guardian", async function () {
      await assert.rejects(viem.deployContract("HapTreasury", [deployer, deployer]));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapTreasury — proposal flow
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapTreasury — proposal flow", async function () {
    async function freshTreasury() {
      const token    = await viem.deployContract("HapToken",   [deployer]);
      const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);
      return { token, treasury };
    }

    it("createProposal sets status to PENDING_APPROVAL", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      assert.equal(await treasury.read.proposalStatus([0n]), "PENDING_APPROVAL");
    });

    it("cannot execute before approval", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await assert.rejects(treasury.write.executeProposal([0n]));
    });

    it("status is TIMELOCK immediately after approval", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await treasury.write.approveProposal([0n]);
      assert.equal(await treasury.read.proposalStatus([0n]), "TIMELOCK");
    });

    it("cannot execute during timelock", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await treasury.write.approveProposal([0n]);
      await assert.rejects(treasury.write.executeProposal([0n]));
    });

    it("executes successfully after 7-day timelock", async function () {
      const { token, treasury } = await freshTreasury();
      await token.write.transfer([treasury.address, P("100")]);
      await treasury.write.createProposal([token.address, user, P("50"), "Payout"]);
      await treasury.write.approveProposal([0n]);

      const block = await publicClient.getBlock();
      await advanceTimeTo(block.timestamp + 7n * 24n * 60n * 60n + 2n);

      await treasury.write.executeProposal([0n]);
      assert.equal(await treasury.read.proposalStatus([0n]), "EXECUTED");
      assert.equal(await token.read.balanceOf([user]), P("50"));
    });

    it("proposer can cancel their own proposal", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await treasury.write.cancelProposal([0n]);
      assert.equal(await treasury.read.proposalStatus([0n]), "CANCELLED");
    });

    it("non-authorized user cannot cancel (L-5 fix)", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await assert.rejects(
        treasury.write.cancelProposal([0n], { account: userClient.account }),
      );
    });

    it("cannot approve when paused (M-3 fix)", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await treasury.write.emergencyPause({ account: guardianClient.account });
      await assert.rejects(treasury.write.approveProposal([0n]));
    });

    it("can cancel even when paused (intentional design)", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await treasury.write.emergencyPause({ account: guardianClient.account });
      await treasury.write.cancelProposal([0n]); // must not revert
      assert.equal(await treasury.read.proposalStatus([0n]), "CANCELLED");
    });

    it("emergencyWithdraw reverts when not paused", async function () {
      const { token, treasury } = await freshTreasury();
      await token.write.transfer([treasury.address, P("100")]);
      await assert.rejects(
        treasury.write.emergencyWithdraw([token.address, user, P("50")]),
      );
    });

    it("emergencyWithdraw transfers funds when paused", async function () {
      const { token, treasury } = await freshTreasury();
      await token.write.transfer([treasury.address, P("100")]);
      await treasury.write.emergencyPause({ account: guardianClient.account });
      await treasury.write.emergencyWithdraw([token.address, user, P("100")]);
      assert.equal(await token.read.balanceOf([user]), P("100"));
    });

    it("timeUntilExecutable returns max before approval", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      const t = await treasury.read.timeUntilExecutable([0n]);
      assert.equal(t, (2n ** 256n) - 1n); // type(uint256).max
    });

    it("timeUntilExecutable returns 0 after timelock", async function () {
      const { token, treasury } = await freshTreasury();
      await treasury.write.createProposal([token.address, user, P("1"), "Test"]);
      await treasury.write.approveProposal([0n]);

      const block = await publicClient.getBlock();
      await advanceTimeTo(block.timestamp + 7n * 24n * 60n * 60n + 2n);

      assert.equal(await treasury.read.timeUntilExecutable([0n]), 0n);
    });

    it("receiveFunds updates totalReceived", async function () {
      const { token, treasury } = await freshTreasury();
      await token.write.approve([treasury.address, P("500")]);
      await treasury.write.receiveFunds([token.address, P("500"), "WAGER_RAKE"]);
      assert.equal(await treasury.read.totalReceived([token.address]), P("500"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapToken — TBB: transferFrom blacklist bypass
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapToken — TBB transferFrom spender blacklist", async function () {
    it("blacklisted spender cannot call transferFrom even with prior allowance", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      // Owner approves `user` as a spender of 1000 HAP.
      await token.write.approve([user, P("1000")]);
      // Then `user` is blacklisted.
      await token.write.blacklist([user]);
      // The spender (`user`) must now be blocked from calling transferFrom,
      // even though both `from` and `to` are clean.
      await assert.rejects(
        token.write.transferFrom(
          [deployer, guardian, P("1")],
          { account: userClient.account },
        ),
      );
    });

    it("non-blacklisted spender can transferFrom normally (sanity)", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.approve([user, P("1000")]);
      await token.write.transferFrom(
        [deployer, guardian, P("100")],
        { account: userClient.account },
      );
      assert.equal(await token.read.balanceOf([guardian]), P("100"));
    });

    it("blacklisted spender cannot call burnFrom either (consistency)", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.approve([user, P("1000")]);
      await token.write.blacklist([user]);
      await assert.rejects(
        token.write.burnFrom(
          [deployer, P("1")],
          { account: userClient.account },
        ),
      );
    });

    it("non-blacklisted spender can burnFrom (sanity)", async function () {
      const token = await viem.deployContract("HapToken", [deployer]);
      await token.write.approve([user, P("1000")]);
      const supplyBefore = await token.read.totalSupply();
      await token.write.burnFrom(
        [deployer, P("100")],
        { account: userClient.account },
      );
      assert.equal(await token.read.totalSupply(), supplyBefore - P("100"));
      assert.equal(await token.read.totalBurned(), P("100"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — RBV: revoke() before TGE
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — RBV pre-TGE revoke safety", async function () {
    it("revoke() before TGE does not break vested/releasable views after TGE", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      // Revoke a revocable schedule (TEAM id=4) BEFORE TGE.
      await vesting.write.revoke([4n]);

      // Now jump well past TGE. The vested/releasable arithmetic must remain
      // safe — without the fix, `effectiveTime - tgeTimestamp` would underflow
      // and these calls would revert permanently for the revoked schedule.
      await advanceTimeTo(tgeTimestamp + 24n * ONE_MONTH);

      assert.equal(await vesting.read.computeVestedAmount([4n]), 0n);
      assert.equal(await vesting.read.computeReleasableAmount([4n]), 0n);
    });

    it("post-TGE behaviour of an un-revoked schedule is unchanged (regression)", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      // ADVISORS (id=5): cliff 6mo. After 6mo + a tick, some linear vesting is due.
      await advanceTimeTo(tgeTimestamp + 6n * ONE_MONTH + ONE_HOUR);
      const vested = await vesting.read.computeVestedAmount([5n]);
      assert.ok(vested > 0n, "ADVISORS should have positive vested after cliff");
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapVesting — CSP: completed/revoked schedules free their slot
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapVesting — CSP active slot recycling", async function () {
    async function freshVesting() {
      const token = await viem.deployContract("HapToken", [deployer]);
      const block = await publicClient.getBlock();
      const tge   = block.timestamp + 2n * ONE_HOUR + 60n;
      const v     = await viem.deployContract("HapVesting", [token.address, tge, deployer]);
      // Fund vesting with enough HAP to support many small schedules.
      await token.write.transfer([v.address, P("1000")]);
      return { token, vesting: v, tge };
    }

    it("createVestingSchedule increments activeScheduleCount", async function () {
      const { vesting } = await freshVesting();
      assert.equal(await vesting.read.activeScheduleCount([user]), 0n);
      await vesting.write.createVestingSchedule(
        [user, LABEL("LIQ"), P("1"), P("1"), 0n, 0n, false],
      );
      assert.equal(await vesting.read.activeScheduleCount([user]), 1n);
    });

    it("full release frees the slot, allowing a new schedule even after cap", async function () {
      const { vesting, tge } = await freshVesting();

      // Create 50 LIQUIDITY-style schedules for `user` (100% TGE, vestingDuration=0).
      for (let i = 0; i < 50; i++) {
        await vesting.write.createVestingSchedule(
          [user, LABEL("LIQ"), P("1"), P("1"), 0n, 0n, false],
        );
      }
      assert.equal(await vesting.read.activeScheduleCount([user]), 50n);

      // The 51st must revert (cap == 50 active).
      await assert.rejects(
        vesting.write.createVestingSchedule(
          [user, LABEL("LIQ"), P("1"), P("1"), 0n, 0n, false],
        ),
      );

      // After TGE, releaseAllMine() makes every schedule fully released.
      await advanceTimeTo(tge);
      await vesting.write.releaseAllMine({ account: userClient.account });
      assert.equal(await vesting.read.activeScheduleCount([user]), 0n);

      // Now a fresh schedule can be created — the cap is on active, not historical.
      await vesting.write.createVestingSchedule(
        [user, LABEL("LIQ_NEW"), P("1"), P("1"), 0n, 0n, false],
      );
      assert.equal(await vesting.read.activeScheduleCount([user]), 1n);
    });

    it("revoke decrements activeScheduleCount", async function () {
      const { vesting, tgeTimestamp } = await deploySystem();
      const before = await vesting.read.activeScheduleCount([deployer]);
      // TEAM (id=4) is revocable, beneficiary=deployer.
      await advanceTimeTo(tgeTimestamp + ONE_HOUR);
      await vesting.write.revoke([4n]);
      assert.equal(await vesting.read.activeScheduleCount([deployer]), before - 1n);
    });

    it("historical beneficiarySchedules entries are NOT removed (preserves audit trail)", async function () {
      const { vesting, tge } = await freshVesting();
      await vesting.write.createVestingSchedule(
        [user, LABEL("LIQ"), P("1"), P("1"), 0n, 0n, false],
      );
      await advanceTimeTo(tge);
      await vesting.write.releaseAllMine({ account: userClient.account });
      // activeScheduleCount drops to 0, but the historical list still contains the id.
      assert.equal(await vesting.read.activeScheduleCount([user]), 0n);
      const ids = await vesting.read.getSchedulesOf([user]);
      assert.equal(ids.length, 1);
    });

    it("getActiveSchedulesOf returns only still-active IDs", async function () {
      const { vesting, tge } = await freshVesting();
      // Three schedules — two LIQUIDITY (will fully release at TGE) and one with
      // a long cliff that stays active.
      await vesting.write.createVestingSchedule(
        [user, LABEL("LIQ1"), P("1"), P("1"), 0n, 0n, false],
      );
      await vesting.write.createVestingSchedule(
        [user, LABEL("LIQ2"), P("1"), P("1"), 0n, 0n, false],
      );
      await vesting.write.createVestingSchedule(
        [user, LABEL("LOCK"), P("1"), 0n, 30n * 24n * 60n * 60n, 30n * 24n * 60n * 60n, false],
      );

      assert.equal(await vesting.read.activeScheduleCount([user]), 3n);
      const allActive = await vesting.read.getActiveSchedulesOf([user]);
      assert.equal(allActive.length, 3);

      await advanceTimeTo(tge);
      await vesting.write.releaseAllMine({ account: userClient.account });

      // Two LIQ schedules removed; the long-cliff one still active.
      assert.equal(await vesting.read.activeScheduleCount([user]), 1n);
      const stillActive = await vesting.read.getActiveSchedulesOf([user]);
      assert.equal(stillActive.length, 1);
      // Historical list still has all three.
      assert.equal((await vesting.read.getSchedulesOf([user])).length, 3);
    });

    it("releaseAllMine iterates only the ACTIVE list, not the full history", async function () {
      const { vesting, tge } = await freshVesting();
      // Create N LIQUIDITY schedules, fully release them all, then check that
      // a second releaseAllMine() correctly reverts with NothingToRelease — i.e.
      // it isn't doing work for completed schedules.
      for (let i = 0; i < 10; i++) {
        await vesting.write.createVestingSchedule(
          [user, LABEL(`L${i}`), P("1"), P("1"), 0n, 0n, false],
        );
      }
      await advanceTimeTo(tge);
      await vesting.write.releaseAllMine({ account: userClient.account });
      // Active list is now empty.
      assert.equal(await vesting.read.activeScheduleCount([user]), 0n);
      // A subsequent call must revert because the active list is empty — not
      // succeed by walking the historical entries and finding 0 releasable.
      await assert.rejects(
        vesting.write.releaseAllMine({ account: userClient.account }),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapTreasury — IPG: receive() must respect pause
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapTreasury — IPG paused receive guard", async function () {
    it("direct BNB transfer reverts when paused", async function () {
      const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);
      await treasury.write.emergencyPause({ account: guardianClient.account });
      await assert.rejects(
        deployerClient.sendTransaction({ to: treasury.address, value: P("1") }),
      );
    });

    it("direct BNB transfer succeeds when not paused", async function () {
      const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);
      await deployerClient.sendTransaction({ to: treasury.address, value: P("1") });
      assert.equal(await publicClient.getBalance({ address: treasury.address }), P("1"));
      assert.equal(await treasury.read.totalReceived([zeroAddress]), P("1"));
    });

    it("unpause restores direct BNB acceptance", async function () {
      const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);
      await treasury.write.emergencyPause({ account: guardianClient.account });
      await treasury.write.unpause();
      await deployerClient.sendTransaction({ to: treasury.address, value: P("1") });
      assert.equal(await treasury.read.totalReceived([zeroAddress]), P("1"));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // HapTreasury — PTAI: fee-on-transfer accounting
  // ══════════════════════════════════════════════════════════════════════════

  describe("HapTreasury — PTAI fee-on-transfer accounting", async function () {
    it("credits totalReceived with the ACTUAL amount delivered, not the requested amount", async function () {
      const treasury = await viem.deployContract("HapTreasury", [deployer, guardian]);
      const fot      = await viem.deployContract("MockFeeOnTransferERC20");
      await fot.write.mint([deployer, P("1000")]);
      await fot.write.approve([treasury.address, P("1000")]);

      // FoT burns 1% on transfer; calling receiveFunds(100) should credit 99.
      await treasury.write.receiveFunds([fot.address, P("100"), "TEST"]);
      assert.equal(await treasury.read.totalReceived([fot.address]), P("99"));
      assert.equal(await fot.read.balanceOf([treasury.address]), P("99"));
    });

    it("standard ERC20 transfer (no fee) credits the full amount (regression)", async function () {
      const { token, treasury } = await (async () => {
        const t  = await viem.deployContract("HapToken",   [deployer]);
        const tr = await viem.deployContract("HapTreasury", [deployer, guardian]);
        return { token: t, treasury: tr };
      })();
      await token.write.approve([treasury.address, P("100")]);
      await treasury.write.receiveFunds([token.address, P("100"), "TEST"]);
      assert.equal(await treasury.read.totalReceived([token.address]), P("100"));
    });
  });
});
