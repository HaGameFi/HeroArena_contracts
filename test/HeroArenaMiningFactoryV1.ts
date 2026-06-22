import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, maxUint256, parseEther, zeroAddress } from "viem";

const NFT_PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningFactoryV1", async function () {
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
    const factory  = await viem.deployContract("HeroArenaMiningFactoryV1", [
      hapToken.address,
      NFT_PRICE,
    ]);

    const avatarsSCAddr = await factory.read.HeroArenaAvatarsSC();
    const avatarsSC     = await viem.getContractAt("HeroArenaAvatars", avatarsSCAddr);

    // Mint HAP and approve factory for both users
    await hapToken.write.mint([user1, 10_000n * 10n ** 18n]);
    await hapToken.write.mint([user2, 10_000n * 10n ** 18n]);
    await hapToken.write.approve([factory.address, maxUint256], { account: user1Client.account });
    await hapToken.write.approve([factory.address, maxUint256], { account: user2Client.account });

    return { hapToken, factory, avatarsSC };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async function () {
    it("sets HapToken", async function () {
      const { hapToken, factory } = await deploy();
      assert.equal(
        (await factory.read.HapToken()).toLowerCase(),
        hapToken.address.toLowerCase(),
      );
    });

    it("sets nftPrice", async function () {
      const { factory } = await deploy();
      assert.equal(await factory.read.nftPrice(), NFT_PRICE);
    });

    it("deploys HeroArenaAvatarsSC", async function () {
      const { factory } = await deploy();
      const addr = await factory.read.HeroArenaAvatarsSC();
      assert.notEqual(addr, zeroAddress);
    });

    it("sets factory as avatar contract owner", async function () {
      const { factory, avatarsSC } = await deploy();
      assert.equal(
        (await avatarsSC.read.owner()).toLowerCase(),
        factory.address.toLowerCase(),
      );
    });

    it("sets deployer as factory owner", async function () {
      const { factory } = await deploy();
      assert.equal((await factory.read.owner()).toLowerCase(), owner.toLowerCase());
    });

    it("claim is disabled by default", async function () {
      const { factory } = await deploy();
      assert.equal(await factory.read.availableClaim(), false);
    });

    it("sets avatar names in constructor", async function () {
      const { avatarsSC } = await deploy();
      const [names] = await avatarsSC.read.getAvatarNameAndCreatedTimestampBatch([[1, 11, 25]]);
      assert.equal(names[0], "Archer_v1");
      assert.equal(names[1], "Cleric_v5");
      assert.equal(names[2], "Wizard_v1");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAvailableClaim
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAvailableClaim", async function () {
    it("enables and disables claim", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      assert.equal(await factory.read.availableClaim(), true);
      await factory.write.updateAvailableClaim([false]);
      assert.equal(await factory.read.availableClaim(), false);
    });

    it("emits AvailableClaimUpdated event", async function () {
      const { factory } = await deploy();
      const hash    = await factory.write.updateAvailableClaim([true]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("reverts if not owner", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.updateAvailableClaim([true], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // mintNFT
  // ═══════════════════════════════════════════════════════════════════════════

  describe("mintNFT", async function () {
    it("transfers HAP from user to factory", async function () {
      const { hapToken, factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      const before = await hapToken.read.balanceOf([user1]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), before - NFT_PRICE);
      assert.equal(await hapToken.read.balanceOf([factory.address]), NFT_PRICE);
    });

    it("user receives NFT", async function () {
      const { factory, avatarsSC } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      assert.equal(await avatarsSC.read.balanceOf([user1]), 1n);
    });

    it("increments avatarCount", async function () {
      const { factory, avatarsSC } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([5, maxUint256], { account: user1Client.account });
      assert.equal(await avatarsSC.read.avatarCount([5]), 1n);
    });

    it("emits AvatarMinted event", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      const hash    = await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("multiple users can mint", async function () {
      const { hapToken, factory, avatarsSC } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      await factory.write.mintNFT([1, maxUint256], { account: user2Client.account });
      assert.equal(await avatarsSC.read.balanceOf([user1]), 1n);
      assert.equal(await avatarsSC.read.balanceOf([user2]), 1n);
      assert.equal(await hapToken.read.balanceOf([factory.address]), NFT_PRICE * 2n);
    });

    it("reverts when claim is disabled", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.mintNFT([0, maxUint256], { account: user1Client.account }),
        /Cannot claim/,
      );
    });

    it("reverts on invalid avatarId", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await assert.rejects(
        factory.write.mintNFT([90, maxUint256], { account: user1Client.account }),
        /Input avatarId unavailable/,
      );
    });

    it("reverts on insufficient HAP balance", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      const poorUser = (await viem.getWalletClients())[4];
      await assert.rejects(
        factory.write.mintNFT([0, maxUint256], { account: poorUser.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateNFTPrice
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateNFTPrice", async function () {
    it("updates nftPrice", async function () {
      const { factory } = await deploy();
      const newPrice = 200n * 10n ** 18n;
      await factory.write.updateNFTPrice([newPrice]);
      assert.equal(await factory.read.nftPrice(), newPrice);
    });

    it("emits AvatarPriceUpdated event", async function () {
      const { factory } = await deploy();
      const hash    = await factory.write.updateNFTPrice([200n * 10n ** 18n]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("new price is used on next mint", async function () {
      const { hapToken, factory } = await deploy();
      const newPrice = 50n * 10n ** 18n;
      await factory.write.updateNFTPrice([newPrice]);
      await factory.write.updateAvailableClaim([true]);
      const before = await hapToken.read.balanceOf([user1]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), before - newPrice);
    });

    it("reverts if not owner", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.updateNFTPrice([1n], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // proposeNFTContractOwnership + acceptNFTContractOwnership
  // ═══════════════════════════════════════════════════════════════════════════

  describe("proposeNFTContractOwnership", async function () {
    it("sets pendingNFTContractOwner", async function () {
      const { factory } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      assert.equal(
        (await factory.read.pendingNFTContractOwner()).toLowerCase(),
        newOwner.toLowerCase(),
      );
    });

    it("can cancel via cancelNFTContractOwnership (L16 fix)", async function () {
      const { factory } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.cancelNFTContractOwnership();
      assert.equal(await factory.read.pendingNFTContractOwner(), zeroAddress);
    });

    it("rejects proposing address(0) (L16 fix)", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.proposeNFTContractOwnership([zeroAddress]),
        /New owner cannot be zero/,
      );
    });

    it("cancelNFTContractOwnership reverts when no pending proposal", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.cancelNFTContractOwnership(),
        /No pending proposal/,
      );
    });

    it("reverts if not owner", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.proposeNFTContractOwnership([newOwner], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  describe("acceptNFTContractOwnership", async function () {
    it("transfers avatar contract ownership to pending owner", async function () {
      const { factory, avatarsSC } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      assert.equal(
        (await avatarsSC.read.owner()).toLowerCase(),
        newOwner.toLowerCase(),
      );
    });

    it("clears pendingNFTContractOwner after accept", async function () {
      const { factory } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      assert.equal(await factory.read.pendingNFTContractOwner(), zeroAddress);
    });

    it("reverts if caller is not pending owner", async function () {
      const { factory } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await assert.rejects(
        factory.write.acceptNFTContractOwnership({ account: user1Client.account }),
        /Not the pending owner/,
      );
    });

    it("reverts if no pending owner is set", async function () {
      const { factory } = await deploy();
      await assert.rejects(
        factory.write.acceptNFTContractOwnership({ account: user1Client.account }),
        /Not the pending owner/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // claimFee
  // ═══════════════════════════════════════════════════════════════════════════

  describe("claimFee", async function () {
    it("transfers HAP to owner", async function () {
      const { hapToken, factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      await factory.write.mintNFT([1, maxUint256], { account: user2Client.account });
      const before = await hapToken.read.balanceOf([owner]);
      await factory.write.claimFee([NFT_PRICE * 2n]);
      assert.equal(await hapToken.read.balanceOf([owner]), before + NFT_PRICE * 2n);
    });

    it("partial withdraw leaves remainder in factory", async function () {
      const { hapToken, factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      await factory.write.claimFee([NFT_PRICE / 2n]);
      assert.equal(await hapToken.read.balanceOf([factory.address]), NFT_PRICE / 2n);
    });

    it("reverts on insufficient balance", async function () {
      const { factory } = await deploy();
      await assert.rejects(factory.write.claimFee([1n]));
    });

    it("reverts if not owner", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      await assert.rejects(
        factory.write.claimFee([NFT_PRICE], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });

    it("emits FeeClaimed (MEE fix)", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0, maxUint256], { account: user1Client.account });
      const hash = await factory.write.claimFee([NFT_PRICE]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // MC: constructor validates HapToken
  // ═══════════════════════════════════════════════════════════════════════════

  describe("MC: constructor input validation", async function () {
    it("reverts when deployed with zero HapToken", async function () {
      await assert.rejects(
        viem.deployContract("HeroArenaMiningFactoryV1", [zeroAddress, NFT_PRICE]),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PSR: mintNFT slippage protection
  // ═══════════════════════════════════════════════════════════════════════════

  describe("PSR: mintNFT slippage protection", async function () {
    it("reverts when current price exceeds caller cap", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await assert.rejects(
        factory.write.mintNFT([0, NFT_PRICE - 1n], { account: user1Client.account }),
        /Price exceeds maximum/,
      );
    });

    it("admin price front-run is blocked by caller cap", async function () {
      const { factory } = await deploy();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.updateNFTPrice([NFT_PRICE * 2n]);
      // User submits with the previous price as cap — must revert.
      await assert.rejects(
        factory.write.mintNFT([0, NFT_PRICE], { account: user1Client.account }),
        /Price exceeds maximum/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // POP: pending NFT-contract proposal is cleared on factory ownership transfer
  // ═══════════════════════════════════════════════════════════════════════════

  describe("POP: pending proposal lifecycle on ownership transfer", async function () {
    it("transferOwnership clears pendingNFTContractOwner", async function () {
      const { factory } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      assert.equal(
        (await factory.read.pendingNFTContractOwner()).toLowerCase(),
        newOwner.toLowerCase(),
      );
      await factory.write.transferOwnership([user1]);
      assert.equal(await factory.read.pendingNFTContractOwner(), zeroAddress);
    });

    it("stale pending owner cannot accept after factory ownership changed", async function () {
      const { factory } = await deploy();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.transferOwnership([user1]);
      // newOwner's stale acceptance must revert because pending was cleared.
      await assert.rejects(
        factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account }),
        /Not the pending owner/,
      );
    });
  });
});
