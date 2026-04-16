import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, maxUint256 } from "viem";

const NFT_PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningFactoryV1", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client, newOwnerClient] =
    await viem.getWalletClients();

  const owner    = ownerClient.account.address;
  const user1    = user1Client.account.address;
  const user2    = user2Client.account.address;
  const newOwner = newOwnerClient.account.address;

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deployAll() {
    const hapToken = await viem.deployContract("MockERC20");
    const factory  = await viem.deployContract("HeroArenaMiningFactoryV1", [
      hapToken.address,
      NFT_PRICE,
    ]);
    const avatarsSCAddr = await factory.read.HeroArenaAvatarsSC();
    const avatarsSC = await viem.getContractAt("HeroArenaAvatars", avatarsSCAddr);

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
    it("sets HapToken address", async function () {
      const { hapToken, factory } = await deployAll();
      assert.equal(
        getAddress(await factory.read.HapToken()),
        getAddress(hapToken.address),
      );
    });

    it("sets nftPrice", async function () {
      const { factory } = await deployAll();
      assert.equal(await factory.read.nftPrice(), NFT_PRICE);
    });

    it("deploys HeroArenaAvatarsSC with factory as owner", async function () {
      const { factory, avatarsSC } = await deployAll();
      assert.equal(
        getAddress(await avatarsSC.read.owner()),
        getAddress(factory.address),
      );
    });

    it("initializes Knight_v0 as first avatar", async function () {
      const { avatarsSC } = await deployAll();
      const [names] = await avatarsSC.read.getAvatarNameAndCreatedTimestampsBatch([[0]]);
      assert.equal(names[0], "Knight_v0");
    });

    it("initializes Ninja_v2 as last avatar", async function () {
      const { avatarsSC } = await deployAll();
      const [names] = await avatarsSC.read.getAvatarNameAndCreatedTimestampsBatch([[18]]);
      assert.equal(names[0], "Ninja_v2");
    });

    it("availableClaim is false by default", async function () {
      const { factory } = await deployAll();
      assert.equal(await factory.read.availableClaim(), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAvailableClaim
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAvailableClaim", async function () {
    it("sets availableClaim to true", async function () {
      const { factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      assert.equal(await factory.read.availableClaim(), true);
    });

    it("sets availableClaim back to false", async function () {
      const { factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.updateAvailableClaim([false]);
      assert.equal(await factory.read.availableClaim(), false);
    });

    it("emits AvailableClaimUpdated", async function () {
      const { factory } = await deployAll();
      await viem.assertions.emitWithArgs(
        factory.write.updateAvailableClaim([true]),
        factory,
        "AvailableClaimUpdated",
        [getAddress(owner), true],
      );
    });

    it("reverts if not owner", async function () {
      const { factory } = await deployAll();
      await assert.rejects(
        factory.write.updateAvailableClaim([true], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // mintNFT
  // ═══════════════════════════════════════════════════════════════════════════

  describe("mintNFT", async function () {
    it("deducts HAP from user", async function () {
      const { hapToken, factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      const balBefore = await hapToken.read.balanceOf([user1]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), balBefore - NFT_PRICE);
    });

    it("accumulates HAP in factory contract", async function () {
      const { hapToken, factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([factory.address]), NFT_PRICE);
    });

    it("mints NFT to caller", async function () {
      const { factory, avatarsSC } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await avatarsSC.read.balanceOf([user1]), 1n);
    });

    it("increments avatarCount in NFT contract", async function () {
      const { factory, avatarsSC } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([3], { account: user1Client.account });
      assert.equal(await avatarsSC.read.avatarCount([3]), 1n);
    });

    it("emits AvatarMinted", async function () {
      const { factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await viem.assertions.emitWithArgs(
        factory.write.mintNFT([0], { account: user1Client.account }),
        factory,
        "AvatarMinted",
        [getAddress(user1), 1n, 0],
      );
    });

    it("multiple users can mint", async function () {
      const { factory, avatarsSC } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      await factory.write.mintNFT([1], { account: user2Client.account });
      assert.equal(await avatarsSC.read.balanceOf([user1]), 1n);
      assert.equal(await avatarsSC.read.balanceOf([user2]), 1n);
      assert.equal(await avatarsSC.read.totalSupply(), 2n);
    });

    it("reverts if availableClaim is false", async function () {
      const { factory } = await deployAll();
      await assert.rejects(
        factory.write.mintNFT([0], { account: user1Client.account }),
        /Cannot claim/,
      );
    });

    it("reverts if avatarId out of range (19)", async function () {
      const { factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await assert.rejects(
        factory.write.mintNFT([19], { account: user1Client.account }),
        /Input avatarId unavailable/,
      );
    });

    it("allows max valid avatarId (18)", async function () {
      const { factory, avatarsSC } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([18], { account: user1Client.account });
      assert.equal(await avatarsSC.read.balanceOf([user1]), 1n);
    });

    it("reverts if insufficient HAP allowance", async function () {
      const { hapToken, factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await hapToken.write.approve([factory.address, 0n], { account: user2Client.account });
      await assert.rejects(
        factory.write.mintNFT([0], { account: user2Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateNFTPrice
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateNFTPrice", async function () {
    it("sets new price", async function () {
      const { factory } = await deployAll();
      await factory.write.updateNFTPrice([200n * 10n ** 18n]);
      assert.equal(await factory.read.nftPrice(), 200n * 10n ** 18n);
    });

    it("new price is applied on next mint", async function () {
      const { hapToken, factory } = await deployAll();
      const newPrice = 50n * 10n ** 18n;
      await factory.write.updateNFTPrice([newPrice]);
      await factory.write.updateAvailableClaim([true]);
      const balBefore = await hapToken.read.balanceOf([user1]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), balBefore - newPrice);
    });

    it("emits AvatarPriceUpdated", async function () {
      const { factory } = await deployAll();
      await viem.assertions.emitWithArgs(
        factory.write.updateNFTPrice([200n * 10n ** 18n]),
        factory,
        "AvatarPriceUpdated",
        [200n * 10n ** 18n],
      );
    });

    it("reverts if not owner", async function () {
      const { factory } = await deployAll();
      await assert.rejects(
        factory.write.updateNFTPrice([200n * 10n ** 18n], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // proposeNFTContractOwnership / acceptNFTContractOwnership
  // ═══════════════════════════════════════════════════════════════════════════

  describe("two-step NFT contract ownership", async function () {
    it("propose sets pendingNFTContractOwner", async function () {
      const { factory } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      assert.equal(
        getAddress(await factory.read.pendingNFTContractOwner()),
        getAddress(newOwner),
      );
    });

    it("propose emits NFTContractOwnershipProposed", async function () {
      const { factory } = await deployAll();
      await viem.assertions.emitWithArgs(
        factory.write.proposeNFTContractOwnership([newOwner]),
        factory,
        "NFTContractOwnershipProposed",
        [getAddress(factory.address), getAddress(newOwner)],
      );
    });

    it("propose reverts if not owner", async function () {
      const { factory } = await deployAll();
      await assert.rejects(
        factory.write.proposeNFTContractOwnership([newOwner], { account: user1Client.account }),
      );
    });

    it("propose with address(0) cancels pending proposal", async function () {
      const { factory } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.proposeNFTContractOwnership(["0x0000000000000000000000000000000000000000"]);
      assert.equal(
        await factory.read.pendingNFTContractOwner(),
        "0x0000000000000000000000000000000000000000",
      );
    });

    it("propose can overwrite pending owner", async function () {
      const { factory } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.proposeNFTContractOwnership([user2]);
      assert.equal(
        getAddress(await factory.read.pendingNFTContractOwner()),
        getAddress(user2),
      );
    });

    it("accept transfers NFT contract ownership to pending owner", async function () {
      const { factory, avatarsSC } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      assert.equal(getAddress(await avatarsSC.read.owner()), getAddress(newOwner));
    });

    it("accept clears pendingNFTContractOwner", async function () {
      const { factory } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      assert.equal(
        await factory.read.pendingNFTContractOwner(),
        "0x0000000000000000000000000000000000000000",
      );
    });

    it("accept emits NFTContractOwnershipTransferred", async function () {
      const { factory } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await viem.assertions.emitWithArgs(
        factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account }),
        factory,
        "NFTContractOwnershipTransferred",
        [getAddress(factory.address), getAddress(newOwner)],
      );
    });

    it("accept reverts if caller is not pending owner", async function () {
      const { factory } = await deployAll();
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await assert.rejects(
        factory.write.acceptNFTContractOwnership({ account: user1Client.account }),
        /Not the pending owner/,
      );
    });

    it("accept reverts if no pending proposal exists", async function () {
      const { factory } = await deployAll();
      await assert.rejects(
        factory.write.acceptNFTContractOwnership({ account: user1Client.account }),
        /Not the pending owner/,
      );
    });

    it("mintNFT reverts after NFT contract ownership transferred", async function () {
      const { factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.proposeNFTContractOwnership([newOwner]);
      await factory.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
      await assert.rejects(
        factory.write.mintNFT([0], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // claimFee
  // ═══════════════════════════════════════════════════════════════════════════

  describe("claimFee", async function () {
    it("transfers HAP to owner", async function () {
      const { hapToken, factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      const balBefore = await hapToken.read.balanceOf([owner]);
      await factory.write.claimFee([NFT_PRICE]);
      assert.equal(await hapToken.read.balanceOf([owner]), balBefore + NFT_PRICE);
    });

    it("supports partial withdrawal", async function () {
      const { hapToken, factory } = await deployAll();
      await factory.write.updateAvailableClaim([true]);
      await factory.write.mintNFT([0], { account: user1Client.account });
      await factory.write.mintNFT([0], { account: user2Client.account });
      await factory.write.claimFee([NFT_PRICE]);
      assert.equal(await hapToken.read.balanceOf([factory.address]), NFT_PRICE);
    });

    it("reverts if not owner", async function () {
      const { factory } = await deployAll();
      await assert.rejects(
        factory.write.claimFee([1n], { account: user1Client.account }),
      );
    });
  });
});
