import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { maxUint256, zeroAddress } from "viem";

const PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningStationV1", async function () {
  const { viem } = await network.connect();
  const [ownerClient, userClient, recipientClient, newOwnerClient] = await viem.getWalletClients();
  const user = userClient.account.address;
  const recipient = recipientClient.account.address;
  const newOwner = newOwnerClient.account.address;

  async function deploy() {
    const hap = await viem.deployContract("MockERC20");
    const frames = await viem.deployContract("HeroArenaFrames");
    const station = await viem.deployContract("HeroArenaMiningStationV1", [
      hap.address,
      frames.address,
      PRICE,
    ]);
    await frames.write.transferOwnership([station.address]);
    await station.write.initializeFrames();
    await hap.write.mint([user, 1_000n * 10n ** 18n]);
    await hap.write.approve([station.address, maxUint256], { account: userClient.account });
    return { hap, frames, station };
  }

  it("configures frame 1 after Station becomes Frames owner", async function () {
    const { hap, frames, station } = await deploy();
    assert.equal((await station.read.HapToken()).toLowerCase(), hap.address.toLowerCase());
    assert.equal((await station.read.heroArenaFramesSC()).toLowerCase(), frames.address.toLowerCase());
    assert.equal(await station.read.framesInitialized(), true);
    assert.equal((await frames.read.owner()).toLowerCase(), station.address.toLowerCase());
    const [names] = await frames.read.getFrameNameAndCreatedTimestampBatch([[1]]);
    assert.deepEqual(names, ["Sapphire_v0"]);
  });

  it("deploys before ownership transfer and initializes exactly once", async function () {
    const hap = await viem.deployContract("MockERC20");
    const frames = await viem.deployContract("HeroArenaFrames");
    const station = await viem.deployContract("HeroArenaMiningStationV1", [hap.address, frames.address, PRICE]);
    await assert.rejects(station.write.initializeFrames(), /V1 is not Frames owner/);
    await frames.write.transferOwnership([station.address]);
    await station.write.initializeFrames();
    await assert.rejects(station.write.initializeFrames(), /Frames already initialized/);
  });

  it("mints frame 1 and collects the exact HAP fee", async function () {
    const { hap, frames, station } = await deploy();
    await station.write.updateAvailableClaim([true]);
    await station.write.mintNFT([1], { account: userClient.account });
    assert.equal(await frames.read.balanceOf([user]), 1n);
    assert.equal(await frames.read.frameCount([1]), 1n);
    assert.equal(await hap.read.balanceOf([station.address]), PRICE);
  });

  it("rejects disabled claims and frame ids outside the V1 range", async function () {
    const { station } = await deploy();
    await assert.rejects(station.write.mintNFT([1], { account: userClient.account }), /Cannot claim/);
    await station.write.updateAvailableClaim([true]);
    await assert.rejects(station.write.mintNFT([0], { account: userClient.account }), /Input frameId too low/);
    await assert.rejects(station.write.mintNFT([2], { account: userClient.account }), /Input frameId unavailable/);
  });

  it("prevents buying frame 1 twice while it is owned", async function () {
    const { hap, frames, station } = await deploy();
    await station.write.updateAvailableClaim([true]);
    await station.write.mintNFT([1], { account: userClient.account });
    await assert.rejects(station.write.mintNFT([1], { account: userClient.account }), /Frame already owned/);
    assert.equal(await frames.read.balanceOf([user]), 1n);
    assert.equal(await hap.read.balanceOf([station.address]), PRICE);
  });

  it("allows buying frame 1 again after transfer", async function () {
    const { hap, frames, station } = await deploy();
    await station.write.updateAvailableClaim([true]);
    await station.write.mintNFT([1], { account: userClient.account });
    await frames.write.transferFrom([user, recipient, 1n], { account: userClient.account });
    await station.write.mintNFT([1], { account: userClient.account });
    assert.equal(await frames.read.hasFrame([user, 1]), true);
    assert.equal(await frames.read.hasFrame([recipient, 1]), true);
    assert.equal(await hap.read.balanceOf([station.address]), PRICE * 2n);
  });

  it("uses an updated price and enforces owner-only administration", async function () {
    const { hap, station } = await deploy();
    await assert.rejects(station.write.updateNFTPrice([1n], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await assert.rejects(station.write.updateAvailableClaim([true], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await station.write.updateNFTPrice([25n * 10n ** 18n]);
    await station.write.updateAvailableClaim([true]);
    await station.write.mintNFT([1], { account: userClient.account });
    assert.equal(await hap.read.balanceOf([station.address]), 25n * 10n ** 18n);
  });

  it("claims fees and transfers Frames ownership in two steps", async function () {
    const { hap, frames, station } = await deploy();
    await station.write.updateAvailableClaim([true]);
    await station.write.mintNFT([1], { account: userClient.account });
    await station.write.claimFee([PRICE]);
    assert.equal(await hap.read.balanceOf([station.address]), 0n);
    await station.write.proposeNFTContractOwnership([newOwner]);
    await assert.rejects(station.write.acceptNFTContractOwnership({ account: userClient.account }), /Not the pending owner/);
    await station.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
    assert.equal((await frames.read.owner()).toLowerCase(), newOwner.toLowerCase());
    assert.equal(await station.read.pendingNFTContractOwner(), zeroAddress);
  });
});
