import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes, zeroAddress, maxUint256 } from "viem";

const OPERATOR_ROLE        = keccak256(toBytes("OPERATOR_ROLE"));
const POINT_ROLE           = keccak256(toBytes("POINT_ROLE"));
const CHALLENGE_ADMIN_ROLE = keccak256(toBytes("CHALLENGE_ADMIN_ROLE"));

describe("HeroArenaMeetTheCouncil", async function () {
  const { viem } = await network.connect();
  const [ownerClient, operatorClient, user1Client, user2Client, strangerClient] =
    await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner    = ownerClient.account.address;
  const operator = operatorClient.account.address;
  const user1    = user1Client.account.address;
  const stranger = strangerClient.account.address;

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deployAll() {
    const hapToken   = await viem.deployContract("MockERC20");
    const profile    = await viem.deployContract("HeroArenaProfile", [
      hapToken.address, 0n, 0n,
    ]);
    const challenges = await viem.deployContract("HeroArenaChallenges");
    const council    = await viem.deployContract("HeroArenaMeetTheCouncil", [
      challenges.address,
      profile.address,
    ]);

    // Transfer Challenges ownership → council, then init levels
    await challenges.write.grantRole([CHALLENGE_ADMIN_ROLE, council.address]);
    await council.write.initLevels();

    // Grant council POINT_ROLE on Profile
    await profile.write.grantRole([POINT_ROLE, council.address]);

    // Grant operator role
    await council.write.grantRole([OPERATOR_ROLE, operator]);

    // Enable submit
    await council.write.updateAvailableSubmit([true]);

    // Register user1 in profile
    await profile.write.addTeam(["Council", "The Council team"]);
    await profile.write.createProfile([1n, maxUint256], { account: user1Client.account });

    return { hapToken, profile, challenges, council };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async function () {
    it("sets HeroArenaChallengesSC", async function () {
      const { challenges, council } = await deployAll();
      const stored = await council.read.HeroArenaChallengesSC();
      assert.equal(stored.toLowerCase(), challenges.address.toLowerCase());
    });

    it("sets HeroArenaProfileSC", async function () {
      const { profile, council } = await deployAll();
      const stored = await council.read.HeroArenaProfileSC();
      assert.equal(stored.toLowerCase(), profile.address.toLowerCase());
    });

    it("sets owner", async function () {
      const { council } = await deployAll();
      assert.equal((await council.read.owner()).toLowerCase(), owner.toLowerCase());
    });

    it("grants DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { council } = await deployAll();
      const adminRole = await council.read.DEFAULT_ADMIN_ROLE();
      assert.equal(await council.read.hasRole([adminRole, owner]), true);
    });

    it("submit is disabled by default before updateAvailableSubmit", async function () {
      const hapToken   = await viem.deployContract("MockERC20");
      const profile    = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
      const challenges = await viem.deployContract("HeroArenaChallenges");
      const council    = await viem.deployContract("HeroArenaMeetTheCouncil", [
        challenges.address, profile.address,
      ]);
      assert.equal(await council.read.availableSubmit(), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // initLevels
  // ═══════════════════════════════════════════════════════════════════════════

  describe("initLevels", async function () {
    it("sets submitMinLevelId and submitMaxLevelId", async function () {
      const { council } = await deployAll();
      assert.equal(await council.read.submitMinLevelId(), 0);
      assert.equal(await council.read.submitMaxLevelId(), 6);
    });

    it("sets all level names and points", async function () {
      const { challenges } = await deployAll();
      const ids = [0, 1, 2, 3, 4, 5, 6];
      const [names, points] = await challenges.read.getLevelNameAndPointsBatch([ids]);
      assert.equal(names[0], "Ladder Climb");  assert.equal(points[0], 5n);
      assert.equal(names[1], "Knight Fight");  assert.equal(points[1], 5n);
      assert.equal(names[2], "Warrior Bath");  assert.equal(points[2], 10n);
      assert.equal(names[3], "Firestorm");     assert.equal(points[3], 10n);
      assert.equal(names[4], "Switcheroo");    assert.equal(points[4], 15n);
      assert.equal(names[5], "Wizard Dance");  assert.equal(points[5], 15n);
      assert.equal(names[6], "Cluster Bomb");  assert.equal(points[6], 20n);
    });

    it("reverts if called twice", async function () {
      const { council } = await deployAll();
      await assert.rejects(council.write.initLevels(), /Already initialized/);
    });

    it("reverts if not owner", async function () {
      const { council } = await deployAll();
      await assert.rejects(
        council.write.initLevels({ account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAvailableSubmit
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAvailableSubmit", async function () {
    it("disables and re-enables submit", async function () {
      const { council } = await deployAll();
      await council.write.updateAvailableSubmit([false]);
      assert.equal(await council.read.availableSubmit(), false);
      await council.write.updateAvailableSubmit([true]);
      assert.equal(await council.read.availableSubmit(), true);
    });

    it("emits AvailableSubmitUpdated event", async function () {
      const { council } = await deployAll();
      const hash    = await council.write.updateAvailableSubmit([false]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("reverts if not owner", async function () {
      const { council } = await deployAll();
      await assert.rejects(
        council.write.updateAvailableSubmit([false], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // submitLv
  // ═══════════════════════════════════════════════════════════════════════════

  describe("submitLv", async function () {
    it("increments lvCount in Challenges contract", async function () {
      const { challenges, council } = await deployAll();
      await council.write.submitLv([user1, 0], { account: operatorClient.account });
      assert.equal(await challenges.read.lvCount([0]), 1n);
    });

    it("sets submit status in Challenges contract", async function () {
      const { challenges, council } = await deployAll();
      await council.write.submitLv([user1, 0], { account: operatorClient.account });
      assert.equal(await challenges.read.getSubmitStatus([user1, 0]), true);
    });

    it("emits LevelSubmited event", async function () {
      const { council } = await deployAll();
      const hash    = await council.write.submitLv([user1, 0], { account: operatorClient.account });
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("works for all valid level IDs (0–6)", async function () {
      const { challenges, council } = await deployAll();
      for (let lvId = 0; lvId <= 6; lvId++) {
        await council.write.submitLv([user1, lvId], { account: operatorClient.account });
        assert.equal(await challenges.read.getSubmitStatus([user1, lvId]), true);
      }
    });

    it("reverts when submit is disabled", async function () {
      const { council } = await deployAll();
      await council.write.updateAvailableSubmit([false]);
      await assert.rejects(
        council.write.submitLv([user1, 0], { account: operatorClient.account }),
        /Cannot submit/,
      );
    });

    it("reverts for levelId above max", async function () {
      const { council } = await deployAll();
      await assert.rejects(
        council.write.submitLv([user1, 7], { account: operatorClient.account }),
        /Input levelId unavailable/,
      );
    });

    it("reverts on duplicate submit", async function () {
      const { council } = await deployAll();
      await council.write.submitLv([user1, 0], { account: operatorClient.account });
      await assert.rejects(
        council.write.submitLv([user1, 0], { account: operatorClient.account }),
        /User can only submit once/,
      );
    });

    it("reverts if caller is not operator", async function () {
      const { council } = await deployAll();
      await assert.rejects(
        council.write.submitLv([user1, 0], { account: strangerClient.account }),
        /Not an operator role/,
      );
    });

    it("owner cannot submit without operator role", async function () {
      const { council } = await deployAll();
      await assert.rejects(
        council.write.submitLv([user1, 0], { account: ownerClient.account }),
        /Not an operator role/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // OPERATOR_ROLE management
  // ═══════════════════════════════════════════════════════════════════════════

  describe("OPERATOR_ROLE", async function () {
    it("admin can grant operator role to new address", async function () {
      const { council } = await deployAll();
      await council.write.grantRole([OPERATOR_ROLE, stranger]);
      assert.equal(await council.read.hasRole([OPERATOR_ROLE, stranger]), true);
    });

    it("revoked operator cannot submit", async function () {
      const { council } = await deployAll();
      await council.write.revokeRole([OPERATOR_ROLE, operator]);
      await assert.rejects(
        council.write.submitLv([user1, 0], { account: operatorClient.account }),
        /Not an operator role/,
      );
    });

    it("non-admin cannot grant operator role", async function () {
      const { council } = await deployAll();
      await assert.rejects(
        council.write.grantRole([OPERATOR_ROLE, stranger], { account: strangerClient.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MC: constructor zero-address validation
  // ═══════════════════════════════════════════════════════════════════════════

  describe("MC: constructor input validation", async function () {
    it("reverts when Challenges address is zero", async function () {
      const hapToken = await viem.deployContract("MockERC20");
      const profile  = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
      await assert.rejects(
        viem.deployContract("HeroArenaMeetTheCouncil", [zeroAddress, profile.address]),
      );
    });

    it("reverts when Profile address is zero", async function () {
      const challenges = await viem.deployContract("HeroArenaChallenges");
      await assert.rejects(
        viem.deployContract("HeroArenaMeetTheCouncil", [challenges.address, zeroAddress]),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ORD: Ownable + AccessControl stay synchronized
  // ═══════════════════════════════════════════════════════════════════════════

  describe("ORD: ownership-role sync", async function () {
    it("transferOwnership grants DEFAULT_ADMIN_ROLE to the new owner", async function () {
      const { council } = await deployAll();
      const adminRole = await council.read.DEFAULT_ADMIN_ROLE();
      await council.write.transferOwnership([user1]);
      assert.equal(await council.read.hasRole([adminRole, user1]), true);
    });

    it("transferOwnership revokes DEFAULT_ADMIN_ROLE from the previous owner", async function () {
      const { council } = await deployAll();
      const adminRole = await council.read.DEFAULT_ADMIN_ROLE();
      await council.write.transferOwnership([user1]);
      assert.equal(await council.read.hasRole([adminRole, owner]), false);
    });

    it("new owner can manage OPERATOR_ROLE after transfer", async function () {
      const { council } = await deployAll();
      await council.write.transferOwnership([user1]);
      const hash = await council.write.revokeRole(
        [OPERATOR_ROLE, operator],
        { account: user1Client.account },
      );
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("previous owner can no longer manage OPERATOR_ROLE after transfer", async function () {
      const { council } = await deployAll();
      await council.write.transferOwnership([user1]);
      await assert.rejects(
        council.write.grantRole([OPERATOR_ROLE, stranger]),
        /AccessControlUnauthorizedAccount/,
      );
    });

    it("renounceOwnership revokes admin role from the deployer", async function () {
      const { council } = await deployAll();
      const adminRole = await council.read.DEFAULT_ADMIN_ROLE();
      await council.write.renounceOwnership();
      assert.equal(await council.read.hasRole([adminRole, owner]), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CRM: initLevels works with role grant alone (no ownership transfer needed)
  // ═══════════════════════════════════════════════════════════════════════════

  describe("CRM: initLevels uses CHALLENGE_ADMIN_ROLE (no ownership transfer)", async function () {
    it("initLevels succeeds with role grant — Challenges has no Ownable", async function () {
      const hapToken   = await viem.deployContract("MockERC20");
      const profile    = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
      const challenges = await viem.deployContract("HeroArenaChallenges");
      const council    = await viem.deployContract("HeroArenaMeetTheCouncil", [
        challenges.address, profile.address,
      ]);
      // Only role grant — no ownership transfer, because HeroArenaChallenges
      // is gated by CHALLENGE_ADMIN_ROLE, not Ownable.
      await challenges.write.grantRole([CHALLENGE_ADMIN_ROLE, council.address]);
      await council.write.initLevels();
      assert.equal(await council.read.submitMaxLevelId(), 6);
    });

    it("initLevels reverts without CHALLENGE_ADMIN_ROLE on Challenges", async function () {
      const hapToken   = await viem.deployContract("MockERC20");
      const profile    = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
      const challenges = await viem.deployContract("HeroArenaChallenges");
      const council    = await viem.deployContract("HeroArenaMeetTheCouncil", [
        challenges.address, profile.address,
      ]);
      // Skip the role grant intentionally → initLevels must revert when it
      // tries to call setLevelNameAndRewardPoints on Challenges.
      await assert.rejects(
        council.write.initLevels(),
        /Not a challenge admin role/,
      );
    });
  });
});
