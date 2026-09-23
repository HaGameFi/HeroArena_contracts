import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { maxUint256, zeroAddress } from "viem";

const PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningBattleFieldV0", async function () {
  const { viem } = await network.connect();
  const [ownerClient, userClient, newOwnerClient] = await viem.getWalletClients();
  const owner = ownerClient.account.address;
  const user = userClient.account.address;
  const newOwner = newOwnerClient.account.address;

  async function deploy() {
    const hap = await viem.deployContract("MockERC20");
    const mining = await viem.deployContract("HeroArenaMiningBattleFieldV0", [hap.address, PRICE]);
    const battleFields = await viem.getContractAt(
      "HeroArenaBattleFields",
      await mining.read.HeroArenaBattleFieldsSC(),
    );
    await hap.write.mint([user, 1_000n * 10n ** 18n]);
    await hap.write.approve([mining.address, maxUint256], { account: userClient.account });
    return { hap, mining, battleFields };
  }

  it("initializes token, price, ownership and V0 metadata", async function () {
    const { hap, mining, battleFields } = await deploy();
    assert.equal((await mining.read.HapToken()).toLowerCase(), hap.address.toLowerCase());
    assert.equal(await mining.read.nftPrice(), PRICE);
    assert.equal(await mining.read.availableClaim(), false);
    assert.equal((await mining.read.owner()).toLowerCase(), owner.toLowerCase());
    assert.equal((await battleFields.read.owner()).toLowerCase(), mining.address.toLowerCase());
    const [names] = await battleFields.read.getBattleFieldNameAndCreatedTimestampBatch([[0, 1]]);
    assert.deepEqual(names, ["Blank", "Default"]);
  });

  it("mints ids 0 and 1 and collects the exact HAP fee", async function () {
    const { hap, mining, battleFields } = await deploy();
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([0], { account: userClient.account });
    await mining.write.mintNFT([1], { account: userClient.account });
    assert.equal(await battleFields.read.balanceOf([user]), 2n);
    assert.equal(await battleFields.read.battleFieldCount([0]), 1n);
    assert.equal(await battleFields.read.battleFieldCount([1]), 1n);
    assert.equal(await hap.read.balanceOf([mining.address]), PRICE * 2n);
    assert.deepEqual(await battleFields.read.getBattleFieldIdBatch([[1n, 2n]]), [0, 1]);
  });

  it("rejects disabled claims, invalid ids and missing allowance", async function () {
    const { mining } = await deploy();
    await assert.rejects(mining.write.mintNFT([0], { account: userClient.account }), /Cannot claim/);
    await mining.write.updateAvailableClaim([true]);
    await assert.rejects(mining.write.mintNFT([2], { account: userClient.account }), /Input battleFieldId unavailable/);
    await assert.rejects(mining.write.mintNFT([0], { account: newOwnerClient.account }));
  });

  it("updates price and charges the new price", async function () {
    const { hap, mining } = await deploy();
    await mining.write.updateNFTPrice([25n * 10n ** 18n]);
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([0], { account: userClient.account });
    assert.equal(await hap.read.balanceOf([mining.address]), 25n * 10n ** 18n);
  });

  it("enforces owner-only administration and allows partial fee claims", async function () {
    const { hap, mining } = await deploy();
    await assert.rejects(mining.write.updateNFTPrice([1n], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await assert.rejects(mining.write.updateAvailableClaim([true], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([0], { account: userClient.account });
    await assert.rejects(mining.write.claimFee([PRICE], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await mining.write.claimFee([40n * 10n ** 18n]);
    assert.equal(await hap.read.balanceOf([mining.address]), 60n * 10n ** 18n);
  });

  it("uses a cancellable two-step NFT ownership transfer", async function () {
    const { mining, battleFields } = await deploy();
    await mining.write.proposeNFTContractOwnership([newOwner]);
    await assert.rejects(mining.write.acceptNFTContractOwnership({ account: userClient.account }), /Not the pending owner/);
    await mining.write.proposeNFTContractOwnership([zeroAddress]);
    assert.equal(await mining.read.pendingNFTContractOwner(), zeroAddress);
    await mining.write.proposeNFTContractOwnership([newOwner]);
    await mining.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
    assert.equal((await battleFields.read.owner()).toLowerCase(), newOwner.toLowerCase());
    assert.equal(await mining.read.pendingNFTContractOwner(), zeroAddress);
  });
});
