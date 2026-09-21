import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { maxUint256, zeroAddress } from "viem";

const NFT_PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningFactoryV2", async function () {
  const { viem } = await network.connect();
  const [ownerClient, userClient, nextOwnerClient] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner = ownerClient.account.address;
  const user = userClient.account.address;
  const nextOwner = nextOwnerClient.account.address;

  async function deploy() {
    const hapToken = await viem.deployContract("MockERC20");
    const factoryV1 = await viem.deployContract("HeroArenaMiningFactoryV1", [
      hapToken.address,
      NFT_PRICE,
    ]);
    const avatarsAddress = await factoryV1.read.HeroArenaAvatarsSC();
    const avatars = await viem.getContractAt("HeroArenaAvatars", avatarsAddress);
    const factoryV2 = await viem.deployContract("HeroArenaMiningFactoryV2", [
      hapToken.address,
      avatars.address,
      NFT_PRICE,
    ]);

    await hapToken.write.mint([user, 1_000n * 10n ** 18n]);
    await hapToken.write.approve([factoryV2.address, maxUint256], {
      account: userClient.account,
    });

    return { hapToken, factoryV1, factoryV2, avatars };
  }

  async function migrateAndInitialize(
    deployment: Awaited<ReturnType<typeof deploy>>,
  ) {
    const { factoryV1, factoryV2 } = deployment;
    await factoryV1.write.proposeNFTContractOwnership([factoryV2.address]);
    await factoryV2.write.acceptAvatarOwnershipFromV1([factoryV1.address]);
    await factoryV2.write.setAvatarJson();
  }

  it("stores the immutable configuration and starts disabled", async function () {
    const { hapToken, factoryV2, avatars } = await deploy();
    assert.equal((await factoryV2.read.HapToken()).toLowerCase(), hapToken.address.toLowerCase());
    assert.equal(
      (await factoryV2.read.heroArenaAvatarsSC()).toLowerCase(),
      avatars.address.toLowerCase(),
    );
    assert.equal(
      (await factoryV2.read.HeroArenaAvatarsSC()).toLowerCase(),
      avatars.address.toLowerCase(),
    );
    assert.equal(await factoryV2.read.nftPrice(), NFT_PRICE);
    assert.equal(await factoryV2.read.availableClaim(), false);
    assert.equal(await factoryV2.read.avatarMetadataInitialized(), false);
  });

  it("rejects an EOA as the HAP token", async function () {
    const factoryV1 = await viem.deployContract("HeroArenaMiningFactoryV1", [
      (await viem.deployContract("MockERC20")).address,
      NFT_PRICE,
    ]);
    const avatarsAddress = await factoryV1.read.HeroArenaAvatarsSC();

    await assert.rejects(
      viem.deployContract("HeroArenaMiningFactoryV2", [user, avatarsAddress, NFT_PRICE]),
      /HapToken must be a contract/,
    );
  });

  it("rejects an EOA as the avatar contract", async function () {
    const hapToken = await viem.deployContract("MockERC20");
    await assert.rejects(
      viem.deployContract("HeroArenaMiningFactoryV2", [hapToken.address, user, NFT_PRICE]),
      /Avatars must be a contract/,
    );
  });

  it("cannot enable claiming before migration", async function () {
    const { factoryV2 } = await deploy();
    await assert.rejects(
      factoryV2.write.updateAvailableClaim([true]),
      /V2 does not own Avatars/,
    );
  });

  it("cannot enable claiming before metadata initialization", async function () {
    const { factoryV1, factoryV2 } = await deploy();
    await factoryV1.write.proposeNFTContractOwnership([factoryV2.address]);
    await factoryV2.write.acceptAvatarOwnershipFromV1([factoryV1.address]);
    await assert.rejects(
      factoryV2.write.updateAvailableClaim([true]),
      /Avatar metadata not initialized/,
    );
  });

  it("migrates the existing avatar contract from V1", async function () {
    const { factoryV1, factoryV2, avatars } = await deploy();
    await factoryV1.write.proposeNFTContractOwnership([factoryV2.address]);
    const hash = await factoryV2.write.acceptAvatarOwnershipFromV1([factoryV1.address]);
    const receipt = await publicClient.getTransactionReceipt({ hash });

    assert.equal(receipt.status, "success");
    assert.equal((await avatars.read.owner()).toLowerCase(), factoryV2.address.toLowerCase());
    assert.equal(await factoryV1.read.pendingNFTContractOwner(), zeroAddress);
  });

  it("rejects migration until V2 is the pending avatar owner", async function () {
    const { factoryV1, factoryV2 } = await deploy();
    await assert.rejects(
      factoryV2.write.acceptAvatarOwnershipFromV1([factoryV1.address]),
      /Factory is not the pending Avatar owner/,
    );
  });

  it("uses the generic migration interface for V2 to a successor", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    const successor = await viem.deployContract("HeroArenaMiningFactoryV2", [
      deployment.hapToken.address,
      deployment.avatars.address,
      NFT_PRICE,
    ]);

    await deployment.factoryV2.write.proposeNFTContractOwnership([successor.address]);
    await successor.write.acceptAvatarOwnershipFromFactory([deployment.factoryV2.address]);

    assert.equal(
      (await deployment.avatars.read.owner()).toLowerCase(),
      successor.address.toLowerCase(),
    );
    assert.equal(await deployment.factoryV2.read.pendingNFTContractOwner(), zeroAddress);
  });

  it("rejects a V1 factory with a different avatar contract", async function () {
    const deployment = await deploy();
    const otherV1 = await viem.deployContract("HeroArenaMiningFactoryV1", [
      deployment.hapToken.address,
      NFT_PRICE,
    ]);
    await assert.rejects(
      deployment.factoryV2.write.acceptAvatarOwnershipFromV1([otherV1.address]),
      /Avatars mismatch/,
    );
  });

  it("initializes metadata for IDs 30 through 59 exactly once", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    const [names, timestamps] =
      await deployment.avatars.read.getAvatarNameAndCreatedTimestampBatch([[30, 41, 48, 59]]);

    assert.deepEqual(names, ["VoidMonk_v0", "Impaler_v5", "Necro_v0", "Wraith_v5"]);
    assert.ok(timestamps.every((timestamp) => timestamp > 0n));
    assert.equal(await deployment.factoryV2.read.avatarMetadataInitialized(), true);
    await assert.rejects(
      deployment.factoryV2.write.setAvatarJson(),
      /Avatar metadata already initialized/,
    );
  });

  it("mints both boundary IDs and collects HAP", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    await deployment.factoryV2.write.updateAvailableClaim([true]);
    await deployment.factoryV2.write.mintNFT([0, NFT_PRICE], { account: userClient.account });
    await deployment.factoryV2.write.mintNFT([59, NFT_PRICE], { account: userClient.account });

    assert.equal(await deployment.avatars.read.balanceOf([user]), 2n);
    assert.equal(await deployment.avatars.read.avatarCount([0]), 1n);
    assert.equal(await deployment.avatars.read.avatarCount([59]), 1n);
    assert.equal(
      await deployment.hapToken.read.balanceOf([deployment.factoryV2.address]),
      NFT_PRICE * 2n,
    );
  });

  it("rejects the first avatar ID above the supported range", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    await deployment.factoryV2.write.updateAvailableClaim([true]);
    await assert.rejects(
      deployment.factoryV2.write.mintNFT([60, NFT_PRICE], { account: userClient.account }),
      /Input avatarId unavailable/,
    );
  });

  it("enforces the caller's maximum price", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    await deployment.factoryV2.write.updateAvailableClaim([true]);
    await deployment.factoryV2.write.updateNFTPrice([NFT_PRICE + 1n]);
    await assert.rejects(
      deployment.factoryV2.write.mintNFT([30, NFT_PRICE], { account: userClient.account }),
      /Price exceeds maximum/,
    );
  });

  it("transfers avatar ownership through the two-step flow", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    await deployment.factoryV2.write.proposeNFTContractOwnership([nextOwner]);
    await deployment.factoryV2.write.acceptNFTContractOwnership([], {
      account: nextOwnerClient.account,
    });

    assert.equal((await deployment.avatars.read.owner()).toLowerCase(), nextOwner.toLowerCase());
    assert.equal(await deployment.factoryV2.read.pendingNFTContractOwner(), zeroAddress);
    await assert.rejects(
      deployment.factoryV2.write.mintNFT([30, NFT_PRICE], { account: userClient.account }),
      /V2 does not own Avatars/,
    );
  });

  it("clears a pending avatar owner when factory ownership changes", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    await deployment.factoryV2.write.proposeNFTContractOwnership([nextOwner]);
    await deployment.factoryV2.write.transferOwnership([nextOwner]);

    assert.equal(await deployment.factoryV2.read.pendingNFTContractOwner(), zeroAddress);
    assert.equal((await deployment.factoryV2.read.owner()).toLowerCase(), nextOwner.toLowerCase());
  });

  it("allows only the factory owner to withdraw collected fees", async function () {
    const deployment = await deploy();
    await migrateAndInitialize(deployment);
    await deployment.factoryV2.write.updateAvailableClaim([true]);
    await deployment.factoryV2.write.mintNFT([30, NFT_PRICE], { account: userClient.account });

    await assert.rejects(
      deployment.factoryV2.write.claimFee([NFT_PRICE], { account: userClient.account }),
      /OwnableUnauthorizedAccount/,
    );
    const before = await deployment.hapToken.read.balanceOf([owner]);
    await deployment.factoryV2.write.claimFee([NFT_PRICE]);
    assert.equal(await deployment.hapToken.read.balanceOf([owner]), before + NFT_PRICE);
  });
});
