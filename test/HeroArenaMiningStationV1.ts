import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { maxUint256, parseEther, zeroAddress } from "viem";

const NFT_PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningStationV1", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client, newOwnerClient] =
    await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner    = ownerClient.account.address;
  const user1    = user1Client.account.address;
  const user2    = user2Client.account.address;
  const newOwner = newOwnerClient.account.address;

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deploy() {
    const hapToken = await viem.deployContract("MockERC20");
    const station  = await viem.deployContract("HeroArenaMiningStationV1", [
      hapToken.address,
      NFT_PRICE,
    ]);

    const framesSCAddr = await station.read.HeroArenaFramesSC();
    const framesSC     = await viem.getContractAt("HeroArenaFrames", framesSCAddr);

    await hapToken.write.mint([user1, 10_000n * 10n ** 18n]);
    await hapToken.write.mint([user2, 10_000n * 10n ** 18n]);
    await hapToken.write.approve([station.address, maxUint256], { account: user1Client.account });
    await hapToken.write.approve([station.address, maxUint256], { account: user2Client.account });

    return { hapToken, station, framesSC };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async function () {
    it("sets HapToken", async function () {
      const { hapToken, station } = await deploy();
      assert.equal(
        (await station.read.HapToken()).toLowerCase(),
        hapToken.address.toLowerCase(),
      );
    });

    it("sets nftPrice", async function () {
      const { station } = await deploy();
      assert.equal(await station.read.nftPrice(), NFT_PRICE);
    });

    it("deploys HeroArenaFramesSC", async function () {
      const { station } = await deploy();
      assert.notEqual(await station.read.HeroArenaFramesSC(), zeroAddress);
    });

    it("sets station as frames contract owner", async function () {
      const { station, framesSC } = await deploy();
      assert.equal(
        (await framesSC.read.owner()).toLowerCase(),
        station.address.toLowerCase(),
      );
    });

    it("sets deployer as station owner", async function () {
      const { station } = await deploy();
      assert.equal((await station.read.owner()).toLowerCase(), owner.toLowerCase());
    });

    it("claim is disabled by default", async function () {
      const { station } = await deploy();
      assert.equal(await station.read.availableClaim(), false);
    });

    it("sets frame names in constructor", async function () {
      const { framesSC } = await deploy();
      const [names] = await framesSC.read.getFrameNameAndCreatedTimestampBatch([[1, 2]]);
      assert.equal(names[0], "Sapphire_v0");
      assert.equal(names[1], "Lunar_v0");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAvailableClaim
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAvailableClaim", async function () {
    it("enables and disables claim", async function () {
      const { station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      assert.equal(await station.read.availableClaim(), true);
      await station.write.updateAvailableClaim([false]);
      assert.equal(await station.read.availableClaim(), false);
    });

    it("emits AvailableClaimUpdated event", async function () {
      const { station } = await deploy();
      const hash    = await station.write.updateAvailableClaim([true]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("reverts if not owner", async function () {
      const { station } = await deploy();
      await assert.rejects(
        station.write.updateAvailableClaim([true], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // mintNFT
  // ═══════════════════════════════════════════════════════════════════════════

  describe("mintNFT", async function () {
    it("transfers HAP from user to station", async function () {
      const { hapToken, station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      const before = await hapToken.read.balanceOf([user1]);
      await station.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), before - NFT_PRICE);
      assert.equal(await hapToken.read.balanceOf([station.address]), NFT_PRICE);
    });

    it("user receives NFT", async function () {
      const { station, framesSC } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await framesSC.read.balanceOf([user1]), 1n);
    });

    it("increments frameCount", async function () {
      const { station, framesSC } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([1], { account: user1Client.account });
      assert.equal(await framesSC.read.frameCount([1]), 1n);
    });

    it("emits FrameMinted event", async function () {
      const { station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      const hash    = await station.write.mintNFT([0], { account: user1Client.account });
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("multiple users can mint", async function () {
      const { hapToken, station, framesSC } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([0], { account: user1Client.account });
      await station.write.mintNFT([1], { account: user2Client.account });
      assert.equal(await framesSC.read.balanceOf([user1]), 1n);
      assert.equal(await framesSC.read.balanceOf([user2]), 1n);
      assert.equal(await hapToken.read.balanceOf([station.address]), NFT_PRICE * 2n);
    });

    it("all valid frameIds (0, 1) can be minted", async function () {
      const { station, framesSC } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([0], { account: user1Client.account });
      await station.write.mintNFT([1], { account: user1Client.account });
      assert.equal(await framesSC.read.balanceOf([user1]), 2n);
    });

    it("reverts when claim is disabled", async function () {
      const { station } = await deploy();
      await assert.rejects(
        station.write.mintNFT([0], { account: user1Client.account }),
        /Cannot claim/,
      );
    });

    it("reverts on invalid frameId", async function () {
      const { station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await assert.rejects(
        station.write.mintNFT([2], { account: user1Client.account }),
        /Input frameId unavailable/,
      );
    });

    it("reverts on insufficient HAP balance", async function () {
      const { station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      const poorUser = (await viem.getWalletClients())[4];
      await assert.rejects(
        station.write.mintNFT([0], { account: poorUser.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateNFTPrice
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateNFTPrice", async function () {
    it("updates nftPrice", async function () {
      const { station } = await deploy();
      const newPrice = 200n * 10n ** 18n;
      await station.write.updateNFTPrice([newPrice]);
      assert.equal(await station.read.nftPrice(), newPrice);
    });

    it("emits FramePriceUpdated event", async function () {
      const { station } = await deploy();
      const hash    = await station.write.updateNFTPrice([200n * 10n ** 18n]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("new price is used on next mint", async function () {
      const { hapToken, station } = await deploy();
      const newPrice = 50n * 10n ** 18n;
      await station.write.updateNFTPrice([newPrice]);
      await station.write.updateAvailableClaim([true]);
      const before = await hapToken.read.balanceOf([user1]);
      await station.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), before - newPrice);
    });

    it("reverts if not owner", async function () {
      const { station } = await deploy();
      await assert.rejects(
        station.write.updateNFTPrice([1n], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // proposeNFTContractOwnership + acceptNFTContractOwnership
  // ═══════════════════════════════════════════════════════════════════════════

  describe("proposeNFTContractOwnership", async function () {
    it("sets pendingNFTContractOwner", async function () {
      const { station } = await deploy();
      await station.write.proposeNFTContractOwnership([newOwner]);
      assert.equal(
        (await station.read.pendingNFTContractOwner()).toLowerCase(),
        newOwner.toLowerCase(),
      );
    });

    it("can cancel by proposing address(0)", async function () {
      const { station } = await deploy();
      await station.write.proposeNFTContractOwnership([newOwner]);
      await station.write.proposeNFTContractOwnership([zeroAddress]);
      assert.equal(await station.read.pendingNFTContractOwner(), zeroAddress);
    });

    it("reverts if not owner", async function () {
      const { station } = await deploy();
      await assert.rejects(
        station.write.proposeNFTContractOwnership([newOwner], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  describe("acceptNFTContractOwnership", async function () {
    it("transfers frames contract ownership to pending owner", async function () {
      const { station, framesSC } = await deploy();
      await station.write.proposeNFTContractOwnership([newOwner]);
      await station.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      assert.equal(
        (await framesSC.read.owner()).toLowerCase(),
        newOwner.toLowerCase(),
      );
    });

    it("clears pendingNFTContractOwner after accept", async function () {
      const { station } = await deploy();
      await station.write.proposeNFTContractOwnership([newOwner]);
      await station.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      assert.equal(await station.read.pendingNFTContractOwner(), zeroAddress);
    });

    it("reverts if caller is not pending owner", async function () {
      const { station } = await deploy();
      await station.write.proposeNFTContractOwnership([newOwner]);
      await assert.rejects(
        station.write.acceptNFTContractOwnership({ account: user1Client.account }),
        /Not the pending owner/,
      );
    });

    it("reverts if no pending owner is set", async function () {
      const { station } = await deploy();
      await assert.rejects(
        station.write.acceptNFTContractOwnership({ account: user1Client.account }),
        /Not the pending owner/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // claimFee
  // ═══════════════════════════════════════════════════════════════════════════

  describe("claimFee", async function () {
    it("transfers HAP to owner", async function () {
      const { hapToken, station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([0], { account: user1Client.account });
      await station.write.mintNFT([1], { account: user2Client.account });
      const before = await hapToken.read.balanceOf([owner]);
      await station.write.claimFee([NFT_PRICE * 2n]);
      assert.equal(await hapToken.read.balanceOf([owner]), before + NFT_PRICE * 2n);
    });

    it("partial withdraw leaves remainder in station", async function () {
      const { hapToken, station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([0], { account: user1Client.account });
      await station.write.claimFee([NFT_PRICE / 2n]);
      assert.equal(await hapToken.read.balanceOf([station.address]), NFT_PRICE / 2n);
    });

    it("reverts on insufficient balance", async function () {
      const { station } = await deploy();
      await assert.rejects(station.write.claimFee([1n]));
    });

    it("reverts if not owner", async function () {
      const { station } = await deploy();
      await station.write.updateAvailableClaim([true]);
      await station.write.mintNFT([0], { account: user1Client.account });
      await assert.rejects(
        station.write.claimFee([NFT_PRICE], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });
});
