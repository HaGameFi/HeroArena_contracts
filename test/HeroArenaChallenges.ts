import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes } from "viem";

const CHALLENGE_ADMIN_ROLE = keccak256(toBytes("CHALLENGE_ADMIN_ROLE"));

describe("HeroArenaChallenges", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client, strangerClient] =
    await viem.getWalletClients();

  const owner   = ownerClient.account.address;
  const user1   = user1Client.account.address;
  const user2   = user2Client.account.address;
  const stranger = strangerClient.account.address;

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deploy() {
    const challenges = await viem.deployContract("HeroArenaChallenges");

    // Deployer has DEFAULT_ADMIN_ROLE — grant CHALLENGE_ADMIN_ROLE to self
    await challenges.write.grantRole([CHALLENGE_ADMIN_ROLE, owner]);
    await challenges.write.setLevelNameAndRewardPoints([0, "Ladder Climb", 5n]);
    await challenges.write.setLevelNameAndRewardPoints([1, "Knight Fight", 10n]);
    return { challenges };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async function () {
    it("grants DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { challenges } = await deploy();
      const adminRole = await challenges.read.DEFAULT_ADMIN_ROLE();
      assert.equal(await challenges.read.hasRole([adminRole, owner]), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // setLevelNameAndRewardPoints
  // ═══════════════════════════════════════════════════════════════════════════

  describe("setLevelNameAndRewardPoints", async function () {
    it("sets name and points", async function () {
      const { challenges } = await deploy();
      const [names, points] = await challenges.read.getLevelNameAndPointsBatch([[0]]);
      assert.equal(names[0], "Ladder Climb");
      assert.equal(points[0], 5n);
    });

    it("can overwrite existing level", async function () {
      const { challenges } = await deploy();
      await challenges.write.setLevelNameAndRewardPoints([0, "Ladder Climb v2", 99n]);
      const [names, points] = await challenges.read.getLevelNameAndPointsBatch([[0]]);
      assert.equal(names[0], "Ladder Climb v2");
      assert.equal(points[0], 99n);
    });

    it("reverts if not challenge admin", async function () {
      const { challenges } = await deploy();
      await assert.rejects(
        challenges.write.setLevelNameAndRewardPoints([0, "Hack", 9999n], {
          account: strangerClient.account,
        }),
        /Not a challenge admin role/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // submit
  // ═══════════════════════════════════════════════════════════════════════════

  describe("submit", async function () {
    it("returns sequential challenge IDs", async function () {
      const { challenges } = await deploy();
      // submit returns value — read via simulate
      const publicClient = await viem.getPublicClient();
      const hash1 = await challenges.write.submit([user1, 0]);
      const hash2 = await challenges.write.submit([user2, 0]);
      const r1 = await publicClient.getTransactionReceipt({ hash: hash1 });
      const r2 = await publicClient.getTransactionReceipt({ hash: hash2 });
      assert.equal(r1.status, "success");
      assert.equal(r2.status, "success");
    });

    it("increments lvCount", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      await challenges.write.submit([user2, 0]);
      assert.equal(await challenges.read.lvCount([0]), 2n);
    });

    it("sets submit status to true", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      assert.equal(await challenges.read.getSubmitStatus([user1, 0]), true);
    });

    it("different users can submit the same level", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      await challenges.write.submit([user2, 0]);
      assert.equal(await challenges.read.getSubmitStatus([user1, 0]), true);
      assert.equal(await challenges.read.getSubmitStatus([user2, 0]), true);
    });

    it("same user can submit different levels", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      await challenges.write.submit([user1, 1]);
      assert.equal(await challenges.read.getSubmitStatus([user1, 0]), true);
      assert.equal(await challenges.read.getSubmitStatus([user1, 1]), true);
    });

    it("reverts on duplicate submit", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      await assert.rejects(
        challenges.write.submit([user1, 0]),
        /User can only submit once/,
      );
    });

    it("reverts if not challenge admin", async function () {
      const { challenges } = await deploy();
      await assert.rejects(
        challenges.write.submit([user1, 0], { account: strangerClient.account }),
        /Not a challenge admin role/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getLevelRewardPoints
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getLevelRewardPoints", async function () {
    it("returns correct points", async function () {
      const { challenges } = await deploy();
      assert.equal(await challenges.read.getLevelRewardPoints([0]), 5n);
      assert.equal(await challenges.read.getLevelRewardPoints([1]), 10n);
    });

    it("returns zero for unset level", async function () {
      const { challenges } = await deploy();
      assert.equal(await challenges.read.getLevelRewardPoints([99]), 0n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getSubmitStatus
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getSubmitStatus", async function () {
    it("returns false before submit", async function () {
      const { challenges } = await deploy();
      assert.equal(await challenges.read.getSubmitStatus([user1, 0]), false);
    });

    it("returns true after submit", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      assert.equal(await challenges.read.getSubmitStatus([user1, 0]), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getLevelIdBatch
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getLevelIdBatch", async function () {
    it("returns correct levelId for single challengeId", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 1]);
      const result = await challenges.read.getLevelIdBatch([[1n]]);
      assert.equal(result[0], 1);
    });

    it("returns correct levelIds for multiple challengeIds", async function () {
      const { challenges } = await deploy();
      await challenges.write.submit([user1, 0]);
      await challenges.write.submit([user2, 1]);
      const result = await challenges.read.getLevelIdBatch([[1n, 2n]]);
      assert.equal(result[0], 0);
      assert.equal(result[1], 1);
    });

    it("returns empty array for empty input", async function () {
      const { challenges } = await deploy();
      const result = await challenges.read.getLevelIdBatch([[]]);
      assert.equal(result.length, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getLevelNameAndPointsBatch
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getLevelNameAndPointsBatch", async function () {
    it("returns correct names and points", async function () {
      const { challenges } = await deploy();
      const [names, points] = await challenges.read.getLevelNameAndPointsBatch([[0, 1]]);
      assert.equal(names[0], "Ladder Climb");
      assert.equal(names[1], "Knight Fight");
      assert.equal(points[0], 5n);
      assert.equal(points[1], 10n);
    });

    it("returns empty string and zero for unset level", async function () {
      const { challenges } = await deploy();
      const [names, points] = await challenges.read.getLevelNameAndPointsBatch([[99]]);
      assert.equal(names[0], "");
      assert.equal(points[0], 0n);
    });

    it("reverts if length exceeds 1000", async function () {
      const { challenges } = await deploy();
      const ids = Array.from({ length: 1001 }, (_, i) => i % 256);
      await assert.rejects(
        challenges.read.getLevelNameAndPointsBatch([ids as number[]]),
        /Group size must be < 1001/,
      );
    });

    it("allows exactly 1000 elements", async function () {
      const { challenges } = await deploy();
      const ids = Array.from({ length: 1000 }, () => 0);
      const [names] = await challenges.read.getLevelNameAndPointsBatch([ids as number[]]);
      assert.equal(names.length, 1000);
    });
  });
});
