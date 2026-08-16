import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { padHex, parseEther, stringToHex } from "viem";

const DAY = 24n * 60n * 60n;
const YEAR = 365n * DAY;
const P = parseEther;
const option = (value: string): `0x${string}` =>
  padHex(stringToHex(value), { size: 32, dir: "right" });

describe("Hero Arena governance security", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const testClient = await viem.getTestClient();
  const [adminClient, aliceClient, bobClient, delegateClient] = await viem.getWalletClients();
  const admin = adminClient.account.address;
  const alice = aliceClient.account.address;
  const bob = bobClient.account.address;
  const delegate = delegateClient.account.address;

  async function goTo(timestamp: bigint) {
    await testClient.setNextBlockTimestamp({ timestamp });
    await testClient.mine({ blocks: 1 });
  }

  async function fixture() {
    const hap = await viem.deployContract("HapToken", [admin]);
    const escrow = await viem.deployContract("VotingEscrowHAP", [hap.address]);
    const profile = await viem.deployContract("HeroArenaProfile", [hap.address, 0n, 0n]);
    await profile.write.addTeam(["TeamOne", "Governance test team"]);
    await profile.write.createProfile([1n, 0n], { account: aliceClient.account });
    await profile.write.createProfile([1n, 0n], { account: bobClient.account });
    const factory = await viem.deployContract("VoteEventFactory", [escrow.address, profile.address, admin]);
    const vault = await viem.getContractAt("VotingRewardVault", await factory.read.rewardVault());
    await hap.write.transfer([alice, P("1000")]);
    await hap.write.transfer([bob, P("1000")]);
    await hap.write.approve([escrow.address, P("1000")], { account: aliceClient.account });
    await hap.write.approve([escrow.address, P("1000")], { account: bobClient.account });
    const now = (await publicClient.getBlock()).timestamp;
    const lockEnd = now + 2n * YEAR;
    await escrow.write.createLock([P("100"), lockEnd], { account: aliceClient.account });
    await escrow.write.createLock([P("300"), lockEnd], { account: bobClient.account });
    return { hap, escrow, profile, factory, vault, lockEnd };
  }

  async function createEvent(
    system: Awaited<ReturnType<typeof fixture>>,
    reward = P("1000"),
    quorum = 0n,
    options = [option("RED"), option("BLUE")],
    uri = "ipfs://hero-arena-vote",
  ) {
    const now = (await publicClient.getBlock()).timestamp;
    const start = now + 2n * 3600n;
    const end = start + DAY;
    await system.hap.write.approve([system.vault.address, reward]);
    await system.factory.write.createVoteEvent([start, end, quorum, options, uri, reward]);
    const index = (await system.factory.read.eventCount()) - 1n;
    const address = await system.factory.read.eventAt([index]);
    const voteEvent = await viem.getContractAt("VoteEvent", address);
    return { voteEvent, address, start, end };
  }

  it("excludes amount, duration and delegate changes made exactly at startTime (H-01)", async function () {
    const system = await fixture();
    await system.escrow.write.delegate([1n, delegate], { account: aliceClient.account });
    const { voteEvent, start } = await createEvent(system);
    const expectedPower = await system.escrow.read.votingPowerAt([1n, start]);

    // The increase transaction itself is mined with timestamp == startTime.
    await testClient.setNextBlockTimestamp({ timestamp: start });
    await system.escrow.write.increaseAmount([1n, P("50")], { account: aliceClient.account });
    await system.escrow.write.extendLock([1n, system.lockEnd + 30n * DAY], { account: aliceClient.account });
    await system.escrow.write.delegate([1n, bob], { account: aliceClient.account });

    assert.equal(await system.escrow.read.votingPowerAt([1n, start]), expectedPower);
    await assert.rejects(voteEvent.write.vote([1n, option("RED")], { account: bobClient.account }));
    await voteEvent.write.vote([1n, option("RED")], { account: delegateClient.account });
  });

  it("keeps veHAP soulbound and pays the 40/60 split to snapshot owners", async function () {
    const system = await fixture();
    const { voteEvent, address, start, end } = await createEvent(system);
    await assert.rejects(
      system.escrow.write.transferFrom([alice, bob, 1n], { account: aliceClient.account }),
    );
    await goTo(start);
    await voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account });
    await voteEvent.write.vote([2n, option("BLUE")], { account: bobClient.account });
    await goTo(end);
    await voteEvent.write.finalize();
    assert.equal(await system.vault.read.previewClaim([address, 1n]), P("350"));
    assert.equal(await system.vault.read.previewClaim([address, 2n]), P("650"));
    const aliceBefore = await system.hap.read.balanceOf([alice]);
    await system.vault.write.claim([address, 1n], { account: delegateClient.account });
    assert.equal((await system.hap.read.balanceOf([alice])) - aliceBefore, P("350"));
  });

  it("accepts only HAP through the factory and only sponsor top-ups", async function () {
    const system = await fixture();
    const { address, start } = await createEvent(system);
    assert.equal((await system.vault.read.hap()).toLowerCase(), system.hap.address.toLowerCase());
    await system.hap.write.approve([system.vault.address, P("10")]);
    await system.vault.write.addReward([address, P("10")]);
    await system.hap.write.approve([system.vault.address, P("1")], { account: bobClient.account });
    await assert.rejects(system.vault.write.addReward([address, P("1")], { account: bobClient.account }));
    await goTo(start);
    await assert.rejects(system.vault.write.addReward([address, P("1")]));
  });

  it("allows only EVENT_CREATOR_ROLE to create an event", async function () {
    const system = await fixture();
    const now = (await publicClient.getBlock()).timestamp;
    await system.hap.write.approve([system.vault.address, P("10")], { account: aliceClient.account });
    await assert.rejects(system.factory.write.createVoteEvent([
      now + 2n * 3600n,
      now + 3n * 3600n,
      0n,
      [option("YES"), option("NO")],
      "ipfs://unauthorized",
      P("10"),
    ], { account: aliceClient.account }));
    const role = await system.factory.read.EVENT_CREATOR_ROLE();
    await system.factory.write.grantRole([role, alice]);
    await system.factory.write.createVoteEvent([
      now + 2n * 3600n,
      now + 3n * 3600n,
      0n,
      [option("YES"), option("NO")],
      "ipfs://authorized",
      P("10"),
    ], { account: aliceClient.account });
    assert.equal(await system.factory.read.eventCount(), 1n);
  });

  it("moves role-admin authority when factory ownership changes", async function () {
    const system = await fixture();
    const adminRole = await system.factory.read.DEFAULT_ADMIN_ROLE();
    await system.factory.write.transferOwnership([alice]);
    assert.equal(await system.factory.read.hasRole([adminRole, admin]), false);
    assert.equal(await system.factory.read.hasRole([adminRole, alice]), true);
    await assert.rejects(
      system.factory.write.grantRole([await system.factory.read.EVENT_CREATOR_ROLE(), bob]),
    );
  });

  it("requires the snapshot owner to have a Hero Arena Profile", async function () {
    const system = await fixture();
    await system.hap.write.transfer([delegate, P("100")]);
    await system.hap.write.approve([system.escrow.address, P("100")], { account: delegateClient.account });
    await system.escrow.write.createLock([P("100"), system.lockEnd], { account: delegateClient.account });
    const { voteEvent, start } = await createEvent(system);
    await goTo(start);
    await assert.rejects(voteEvent.write.vote([3n, option("RED")], { account: delegateClient.account }));
  });

  it("rejects an EOA as the configured Profile contract", async function () {
    const hap = await viem.deployContract("HapToken", [admin]);
    const escrow = await viem.deployContract("VotingEscrowHAP", [hap.address]);
    await assert.rejects(viem.deployContract("VoteEventFactory", [escrow.address, alice, admin]));
  });

  it("enforces minimum reward and atomic full funding", async function () {
    const system = await fixture();
    const now = (await publicClient.getBlock()).timestamp;
    const args = [
      now + 2n * 3600n,
      now + 3n * 3600n,
      0n,
      [option("YES"), option("NO")],
      "ipfs://funding",
    ] as const;
    await assert.rejects(system.factory.write.createVoteEvent([...args, P("0.5")]));
    await system.hap.write.approve([system.vault.address, P("1") - 1n]);
    await assert.rejects(system.factory.write.createVoteEvent([...args, P("1")]));
    assert.equal(await system.factory.read.eventCount(), 0n);
  });

  it("finalizes a unique winner only after quorum and rejects repeat finalization", async function () {
    const system = await fixture();
    const quorum = P("100");
    const { voteEvent, start, end } = await createEvent(system, P("10"), quorum);
    await goTo(start);
    await voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account });
    await voteEvent.write.vote([2n, option("BLUE")], { account: bobClient.account });
    await assert.rejects(voteEvent.write.finalize());
    await goTo(end);
    await voteEvent.write.finalize();
    assert.equal(await voteEvent.read.finalized(), true);
    assert.equal(await voteEvent.read.passed(), true);
    assert.equal(await voteEvent.read.winningOption(), option("BLUE"));
    await assert.rejects(voteEvent.write.finalize());
  });

  it("marks a tie as not passed", async function () {
    const system = await fixture();
    await system.escrow.write.createLock([P("100"), system.lockEnd], { account: aliceClient.account });
    const { voteEvent, start, end } = await createEvent(system, P("10"));
    await goTo(start);
    await voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account });
    await voteEvent.write.vote([3n, option("BLUE")], { account: aliceClient.account });
    await goTo(end);
    await voteEvent.write.finalize();
    assert.equal(await voteEvent.read.passed(), false);
    assert.equal(await voteEvent.read.tied(), true);
    assert.equal(await voteEvent.read.winningOption(), `0x${"00".repeat(32)}`);
  });

  it("does not pass a unique winner below quorum", async function () {
    const system = await fixture();
    const { voteEvent, start, end } = await createEvent(system, P("10"), P("10000"));
    await goTo(start);
    await voteEvent.write.vote([2n, option("BLUE")], { account: bobClient.account });
    await goTo(end);
    await voteEvent.write.finalize();
    assert.equal(await voteEvent.read.passed(), false);
    assert.equal(await voteEvent.read.tied(), false);
  });

  it("returns rounding dust and unclaimed rewards after the claim window", async function () {
    const system = await fixture();
    const reward = P("10") + 1n;
    const { voteEvent, address, start, end } = await createEvent(system, reward);
    await goTo(start);
    await voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account });
    await voteEvent.write.vote([2n, option("BLUE")], { account: bobClient.account });
    await goTo(end);
    await voteEvent.write.finalize();
    await system.vault.write.claim([address, 1n]);
    await assert.rejects(system.vault.write.sweepRemaining([address]));
    const deadline = await system.vault.read.claimDeadline([address]);
    await goTo(deadline);
    const before = await system.hap.read.balanceOf([admin]);
    await system.vault.write.sweepRemaining([address]);
    assert.ok((await system.hap.read.balanceOf([admin])) > before);
    await assert.rejects(system.vault.write.claim([address, 2n]));
  });

  it("refunds a no-vote event once and only to its sponsor", async function () {
    const system = await fixture();
    const { address, end } = await createEvent(system, P("10"));
    await goTo(end);
    await assert.rejects(system.vault.write.refundIfNoVotes([address], { account: bobClient.account }));
    await system.vault.write.refundIfNoVotes([address]);
    await assert.rejects(system.vault.write.refundIfNoVotes([address]));
  });

  it("lets only the creator cancel before start and refunds atomically", async function () {
    const system = await fixture();
    const { voteEvent, address, start } = await createEvent(system, P("10"));
    await assert.rejects(system.factory.write.cancelVoteEvent([address], { account: aliceClient.account }));
    const before = await system.hap.read.balanceOf([admin]);
    await system.factory.write.cancelVoteEvent([address]);
    assert.equal(await voteEvent.read.cancelled(), true);
    assert.equal((await system.hap.read.balanceOf([admin])) - before, P("10"));
    await assert.rejects(system.factory.write.cancelVoteEvent([address]));
    await goTo(start);
    await assert.rejects(voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account }));
  });

  it("requires finalization before rewards can be claimed", async function () {
    const system = await fixture();
    const { voteEvent, address, start, end } = await createEvent(system, P("10"));
    await goTo(start);
    await voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account });
    await goTo(end);
    await assert.rejects(system.vault.write.claim([address, 1n]));
    await voteEvent.write.finalize();
    await system.vault.write.claim([address, 1n]);
  });

  it("previews zero until finalized and starts the claim window at finalizedAt", async function () {
    const system = await fixture();
    const { voteEvent, address, start, end } = await createEvent(system, P("10"));
    await goTo(start);
    await voteEvent.write.vote([1n, option("RED")], { account: aliceClient.account });
    assert.equal(await system.vault.read.previewClaim([address, 1n]), 0n);
    await goTo(end);
    assert.equal(await system.vault.read.previewClaim([address, 1n]), 0n);
    assert.equal(await system.vault.read.claimDeadline([address]), 0n);
    await assert.rejects(system.vault.write.sweepRemaining([address]));
    await voteEvent.write.finalize();
    const finalizedAt = BigInt(await voteEvent.read.finalizedAt());
    const window = await system.vault.read.CLAIM_WINDOW();
    assert.equal(await system.vault.read.claimDeadline([address]), finalizedAt + window);
    assert.ok((await system.vault.read.previewClaim([address, 1n])) > 0n);
    await goTo(finalizedAt + window);
    assert.equal(await system.vault.read.previewClaim([address, 1n]), 0n);
  });

  it("caps event metadata/options and exposes bounded pagination", async function () {
    const system = await fixture();
    await assert.rejects(createEvent(system, P("10"), 0n, Array.from({ length: 33 }, (_, i) => option(`O${i}`))));
    await assert.rejects(createEvent(system, P("10"), 0n, undefined, "x".repeat(513)));
    await createEvent(system, P("10"));
    assert.equal((await system.factory.read.getEvents([0n, 10n])).length, 1);
    assert.equal((await system.factory.read.getEvents([10n, 10n])).length, 0);
    await assert.rejects(system.factory.read.getEvents([0n, 101n]));
  });
});
