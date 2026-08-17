import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, maxUint256, toBytes, zeroAddress } from "viem";

const OPERATOR_ROLE = keccak256(toBytes("OPERATOR_ROLE"));
const POINT_ROLE = keccak256(toBytes("POINT_ROLE"));
const CHALLENGE_ADMIN_ROLE = keccak256(toBytes("CHALLENGE_ADMIN_ROLE"));

describe("HeroArenaMeetTheDarkElf", async function () {
  const { viem } = await network.connect();
  const [ownerClient, operatorClient, userClient, strangerClient] = await viem.getWalletClients();
  const owner = ownerClient.account.address;
  const operator = operatorClient.account.address;
  const user = userClient.account.address;
  const stranger = strangerClient.account.address;

  async function deployAll() {
    const hapToken = await viem.deployContract("MockERC20");
    const profile = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
    const challenges = await viem.deployContract("HeroArenaChallenges");
    const darkElf = await viem.deployContract("HeroArenaMeetTheDarkElf", [
      challenges.address,
      profile.address,
    ]);

    await challenges.write.grantRole([CHALLENGE_ADMIN_ROLE, darkElf.address]);
    await darkElf.write.initLevels();
    await profile.write.grantRole([POINT_ROLE, darkElf.address]);
    await darkElf.write.grantRole([OPERATOR_ROLE, operator]);
    await darkElf.write.updateAvailableSubmit([true]);
    await profile.write.addTeam(["DarkElf", "Dark Elf team"]);
    await profile.write.createProfile([1n, maxUint256], { account: userClient.account });
    return { profile, challenges, darkElf };
  }

  it("initializes contract references, owner, role, and level range", async function () {
    const { profile, challenges, darkElf } = await deployAll();
    assert.equal((await darkElf.read.HeroArenaChallengesSC()).toLowerCase(), challenges.address.toLowerCase());
    assert.equal((await darkElf.read.HeroArenaProfileSC()).toLowerCase(), profile.address.toLowerCase());
    assert.equal((await darkElf.read.owner()).toLowerCase(), owner.toLowerCase());
    assert.equal(await darkElf.read.hasRole([await darkElf.read.DEFAULT_ADMIN_ROLE(), owner]), true);
    assert.equal(await darkElf.read.submitMinLevelId(), 8);
    assert.equal(await darkElf.read.submitMaxLevelId(), 14);
  });

  it("initializes every Dark Elf level name and reward", async function () {
    const { challenges } = await deployAll();
    const [names, points] = await challenges.read.getLevelNameAndPointsBatch([[8, 9, 10, 11, 12, 13, 14]]);
    assert.deepEqual(names, ["Pull Me Around", "Nom Nom Nom", "Knight Crossing", "Hard Target", "Choices, Choices", "Three Vs. Thress", "Let's Be Bad"]);
    assert.deepEqual(points, [10n, 10n, 15n, 20n, 25n, 15n, 25n]);
  });

  it("rejects repeated initialization and non-owner administration", async function () {
    const { darkElf } = await deployAll();
    await assert.rejects(darkElf.write.initLevels(), /Already initialized/);
    await assert.rejects(
      darkElf.write.updateAvailableSubmit([false], { account: strangerClient.account }),
      /OwnableUnauthorizedAccount/,
    );
  });

  it("submits a level and credits the exact profile points", async function () {
    const { profile, challenges, darkElf } = await deployAll();
    await darkElf.write.submitLv([user, 8], { account: operatorClient.account });
    assert.equal(await challenges.read.lvCount([8]), 1n);
    assert.equal(await challenges.read.getSubmitStatus([user, 8]), true);
    const userProfile = await profile.read.getUserProfile([user]);
    assert.equal(userProfile[1], 10n);
  });

  it("submits all valid levels 8 through 14", async function () {
    const { profile, challenges, darkElf } = await deployAll();
    for (let level = 8; level <= 14; level++) {
      await darkElf.write.submitLv([user, level], { account: operatorClient.account });
      assert.equal(await challenges.read.getSubmitStatus([user, level]), true);
    }
    assert.equal((await profile.read.getUserProfile([user]))[1], 120n);
  });

  it("rejects disabled, out-of-range, duplicate, and unauthorized submissions", async function () {
    const { darkElf } = await deployAll();
    await darkElf.write.updateAvailableSubmit([false]);
    await assert.rejects(darkElf.write.submitLv([user, 8], { account: operatorClient.account }), /Cannot submit/);
    await darkElf.write.updateAvailableSubmit([true]);
    await assert.rejects(darkElf.write.submitLv([user, 7], { account: operatorClient.account }), /Input levelId unavailable/);
    await assert.rejects(darkElf.write.submitLv([user, 15], { account: operatorClient.account }), /Input levelId unavailable/);
    await darkElf.write.submitLv([user, 8], { account: operatorClient.account });
    await assert.rejects(darkElf.write.submitLv([user, 8], { account: operatorClient.account }), /User can only submit once/);
    await assert.rejects(darkElf.write.submitLv([user, 9], { account: strangerClient.account }), /Not an operator role/);
  });

  it("synchronizes DEFAULT_ADMIN_ROLE when ownership transfers", async function () {
    const { darkElf } = await deployAll();
    const adminRole = await darkElf.read.DEFAULT_ADMIN_ROLE();
    await darkElf.write.transferOwnership([stranger]);
    assert.equal(await darkElf.read.hasRole([adminRole, stranger]), true);
    assert.equal(await darkElf.read.hasRole([adminRole, owner]), false);
    await darkElf.write.revokeRole([OPERATOR_ROLE, operator], { account: strangerClient.account });
    assert.equal(await darkElf.read.hasRole([OPERATOR_ROLE, operator]), false);
  });

  it("rejects zero dependency addresses", async function () {
    const hapToken = await viem.deployContract("MockERC20");
    const profile = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
    const challenges = await viem.deployContract("HeroArenaChallenges");
    await assert.rejects(viem.deployContract("HeroArenaMeetTheDarkElf", [zeroAddress, profile.address]), /Challenges cannot be zero/);
    await assert.rejects(viem.deployContract("HeroArenaMeetTheDarkElf", [challenges.address, zeroAddress]), /Profile cannot be zero/);
  });
});
