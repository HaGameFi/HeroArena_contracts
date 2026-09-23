import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { maxUint256, zeroAddress } from "viem";

const PRICE = 100n * 10n ** 18n;

describe("HeroArenaMiningBattleFieldV1", async function () {
  const { viem } = await network.connect();
  const [ownerClient, userClient, newOwnerClient, recipientClient] = await viem.getWalletClients();
  const user = userClient.account.address;
  const newOwner = newOwnerClient.account.address;
  const recipient = recipientClient.account.address;

  async function deploy() {
    const hap = await viem.deployContract("MockERC20");
    const battleFields = await viem.deployContract("HeroArenaBattleFields");
    const mining = await viem.deployContract("HeroArenaMiningBattleFieldV1", [
      hap.address,
      battleFields.address,
      PRICE,
    ]);
    await battleFields.write.transferOwnership([mining.address]);
    await mining.write.initializeBattleFields();
    await hap.write.mint([user, 2_000n * 10n ** 18n]);
    await hap.write.approve([mining.address, maxUint256], { account: userClient.account });
    return { hap, mining, battleFields };
  }

  it("configures ids 2 through 9 after the mining contract becomes NFT owner", async function () {
    const { mining, battleFields } = await deploy();
    assert.equal(await mining.read.nftPrice(), PRICE);
    assert.equal(
      (await mining.read.heroArenaBattleFieldsSC()).toLowerCase(),
      battleFields.address.toLowerCase(),
    );
    assert.equal(await mining.read.battleFieldsInitialized(), true);
    assert.equal((await battleFields.read.owner()).toLowerCase(), mining.address.toLowerCase());
    const [names] = await battleFields.read.getBattleFieldNameAndCreatedTimestampBatch([[2, 3, 4, 5, 6, 7, 8, 9]]);
    assert.deepEqual(names, ["MapId002", "MapId003", "MapId004", "MapId005", "MapId006", "MapId007", "MapId008", "MapId009"]);
  });

  it("deploys before ownership transfer and initializes exactly once", async function () {
    const hap = await viem.deployContract("MockERC20");
    const battleFields = await viem.deployContract("HeroArenaBattleFields");
    const mining = await viem.deployContract("HeroArenaMiningBattleFieldV1", [
      hap.address,
      battleFields.address,
      PRICE,
    ]);
    await assert.rejects(mining.write.initializeBattleFields(), /V1 is not BattleFields owner/);
    await battleFields.write.transferOwnership([mining.address]);
    await mining.write.initializeBattleFields();
    await assert.rejects(mining.write.initializeBattleFields(), /BattleFields already initialized/);
  });

  it("mints every valid id and collects fees", async function () {
    const { hap, mining, battleFields } = await deploy();
    await mining.write.updateAvailableClaim([true]);
    for (let id = 2; id < 10; id++) {
      await mining.write.mintNFT([id], { account: userClient.account });
    }
    assert.equal(await battleFields.read.balanceOf([user]), 8n);
    assert.equal(await hap.read.balanceOf([mining.address]), PRICE * 8n);
  });

  it("prevents buying the same BattleField while it is still owned", async function () {
    const { hap, mining, battleFields } = await deploy();
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([2], { account: userClient.account });
    await assert.rejects(
      mining.write.mintNFT([2], { account: userClient.account }),
      /BattleField already owned/,
    );
    assert.equal(await battleFields.read.balanceOf([user]), 1n);
    assert.equal(await hap.read.balanceOf([mining.address]), PRICE);
  });

  it("allows buying the same BattleField again after transferring it", async function () {
    const { hap, mining, battleFields } = await deploy();
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([2], { account: userClient.account });
    await battleFields.write.transferFrom([user, recipient, 1n], {
      account: userClient.account,
    });
    await mining.write.mintNFT([2], { account: userClient.account });
    assert.equal(await battleFields.read.hasBattleField([user, 2]), true);
    assert.equal(await battleFields.read.hasBattleField([recipient, 2]), true);
    assert.equal(await hap.read.balanceOf([mining.address]), PRICE * 2n);
  });

  it("rejects disabled claims and both invalid id boundaries", async function () {
    const { mining } = await deploy();
    await assert.rejects(mining.write.mintNFT([2], { account: userClient.account }), /Cannot claim/);
    await mining.write.updateAvailableClaim([true]);
    await assert.rejects(mining.write.mintNFT([1], { account: userClient.account }), /Input battleFieldId too low/);
    await assert.rejects(mining.write.mintNFT([10], { account: userClient.account }), /Input battleFieldId unavailable/);
  });

  it("updates price and emits the corrected BattleFieldPriceUpdated event", async function () {
    const { hap, mining } = await deploy();
    const publicClient = await viem.getPublicClient();
    const hash = await mining.write.updateNFTPrice([25n * 10n ** 18n]);
    assert.equal((await publicClient.getTransactionReceipt({ hash })).status, "success");
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([2], { account: userClient.account });
    assert.equal(await hap.read.balanceOf([mining.address]), 25n * 10n ** 18n);
  });

  it("enforces owner-only administration", async function () {
    const { mining } = await deploy();
    await assert.rejects(mining.write.updateNFTPrice([1n], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await assert.rejects(mining.write.updateAvailableClaim([true], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await assert.rejects(mining.write.proposeNFTContractOwnership([newOwner], { account: userClient.account }), /OwnableUnauthorizedAccount/);
    await assert.rejects(mining.write.claimFee([0n], { account: userClient.account }), /OwnableUnauthorizedAccount/);
  });

  it("claims fees and transfers the BattleFields ownership in two steps", async function () {
    const { hap, mining, battleFields } = await deploy();
    await mining.write.updateAvailableClaim([true]);
    await mining.write.mintNFT([2], { account: userClient.account });
    await mining.write.claimFee([PRICE]);
    assert.equal(await hap.read.balanceOf([mining.address]), 0n);
    await mining.write.proposeNFTContractOwnership([newOwner]);
    await assert.rejects(mining.write.acceptNFTContractOwnership({ account: userClient.account }), /Not the pending owner/);
    await mining.write.acceptNFTContractOwnership({ account: newOwnerClient.account });
    assert.equal((await battleFields.read.owner()).toLowerCase(), newOwner.toLowerCase());
    assert.equal(await mining.read.pendingNFTContractOwner(), zeroAddress);
  });
});
