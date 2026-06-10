import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes, zeroAddress, parseEther, maxUint256 } from "viem";

const LIQUIDATOR_ROLE = keccak256(toBytes("LIQUIDATOR_ROLE"));

const BET_AMOUNT   = parseEther("1");
const BONUS_AMOUNT = parseEther("0.5");

describe("HeroArenaBattle", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client, liquidatorClient, strangerClient, user3Client] =
    await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner      = ownerClient.account.address;
  const user1      = user1Client.account.address;
  const user2      = user2Client.account.address;
  const liquidator = liquidatorClient.account.address;
  const stranger   = strangerClient.account.address;
  const user3      = user3Client.account.address;

  // ─── deploy helpers ───────────────────────────────────────────────────────

  async function deploy() {
    const hapToken   = await viem.deployContract("MockERC20");
    const profile    = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
    const betToken   = await viem.deployContract("MockERC20");
    const bonusToken = await viem.deployContract("MockERC20");

    await profile.write.addTeam(["Warriors", "Warriors team"]);
    await profile.write.createProfile([1n, maxUint256], { account: user1Client.account });
    await profile.write.createProfile([1n, maxUint256], { account: user2Client.account });
    await profile.write.createProfile([1n, maxUint256], { account: user3Client.account });

    const battle = await viem.deployContract("HeroArenaBattle", [profile.address]);
    await battle.write.grantRole([LIQUIDATOR_ROLE, liquidator]);

    await betToken.write.mint([user1, parseEther("10000")]);
    await betToken.write.mint([user2, parseEther("10000")]);

    await betToken.write.approve([battle.address, maxUint256], { account: user1Client.account });
    await betToken.write.approve([battle.address, maxUint256], { account: user2Client.account });

    return { profile, battle, betToken, bonusToken };
  }

  async function deployWithNative() {
    const d = await deploy();
    await d.battle.write.updateAvailableCreateBattle([true]);
    await d.battle.write.updateAllowedBetToken([zeroAddress, true]);
    await d.battle.write.updateMinimumBetTokenAmount([parseEther("0.01"), 0n]);
    return d;
  }

  async function deployWithERC20() {
    const d = await deploy();
    await d.battle.write.updateAvailableCreateBattle([true]);
    await d.battle.write.updateAllowedBetToken([d.betToken.address, true]);
    await d.battle.write.updateMinimumBetTokenAmount([0n, 1n]);
    return d;
  }

  async function createNativeOpenBattle() {
    const d = await deployWithNative();
    await d.battle.write.createBattle(
      [zeroAddress, BET_AMOUNT, zeroAddress],
      { account: user1Client.account, value: BET_AMOUNT },
    );
    return { ...d, battleId: 1n };
  }

  async function createERC20OpenBattle() {
    const d = await deployWithERC20();
    await d.battle.write.createBattle(
      [d.betToken.address, BET_AMOUNT, zeroAddress],
      { account: user1Client.account },
    );
    return { ...d, battleId: 1n };
  }

  async function startNativeBattle() {
    const d = await createNativeOpenBattle();
    await d.battle.write.joinExistBattle(
      [d.battleId],
      { account: user2Client.account, value: BET_AMOUNT },
    );
    return d;
  }

  async function startERC20Battle() {
    const d = await createERC20OpenBattle();
    await d.battle.write.joinExistBattle([d.battleId], { account: user2Client.account });
    return d;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async function () {
    it("sets HeroArenaProfileSC", async function () {
      const { profile, battle } = await deploy();
      assert.equal(
        (await battle.read.HeroArenaProfileSC()).toLowerCase(),
        profile.address.toLowerCase(),
      );
    });

    it("grants DEFAULT_ADMIN_ROLE to deployer", async function () {
      const { battle } = await deploy();
      const adminRole = await battle.read.DEFAULT_ADMIN_ROLE();
      assert.equal(await battle.read.hasRole([adminRole, owner]), true);
    });

    it("availableCreateBattle is false by default", async function () {
      const { battle } = await deploy();
      assert.equal(await battle.read.availableCreateBattle(), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAvailableCreateBattle
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAvailableCreateBattle", async function () {
    it("toggles the flag", async function () {
      const { battle } = await deploy();
      await battle.write.updateAvailableCreateBattle([true]);
      assert.equal(await battle.read.availableCreateBattle(), true);
      await battle.write.updateAvailableCreateBattle([false]);
      assert.equal(await battle.read.availableCreateBattle(), false);
    });

    it("emits AvailableCreateBattleUpdated", async function () {
      const { battle } = await deploy();
      const hash    = await battle.write.updateAvailableCreateBattle([true]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.updateAvailableCreateBattle([true], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateForbiddenToPlay
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateForbiddenToPlay", async function () {
    it("sets the flag", async function () {
      const { battle } = await deploy();
      await battle.write.updateForbiddenToPlay([user1, true]);
      assert.equal(await battle.read.forbiddenToPlay([user1]), true);
      await battle.write.updateForbiddenToPlay([user1, false]);
      assert.equal(await battle.read.forbiddenToPlay([user1]), false);
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.updateForbiddenToPlay([user1, true], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateBonusToken
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateBonusToken", async function () {
    it("sets bonus token and amount", async function () {
      const { battle, bonusToken } = await deploy();
      await battle.write.updateBonusToken([bonusToken.address, BONUS_AMOUNT]);
      assert.equal((await battle.read.bonusToken()).toLowerCase(), bonusToken.address.toLowerCase());
      assert.equal(await battle.read.bonusAmount(), BONUS_AMOUNT);
    });

    it("reverts if not owner", async function () {
      const { battle, bonusToken } = await deploy();
      await assert.rejects(
        battle.write.updateBonusToken(
          [bonusToken.address, BONUS_AMOUNT],
          { account: strangerClient.account },
        ),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAllowedBetToken
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAllowedBetToken", async function () {
    it("sets the whitelist flag", async function () {
      const { battle, betToken } = await deploy();
      await battle.write.updateAllowedBetToken([betToken.address, true]);
      assert.equal(await battle.read.allowedBetTokens([betToken.address]), true);
      await battle.write.updateAllowedBetToken([betToken.address, false]);
      assert.equal(await battle.read.allowedBetTokens([betToken.address]), false);
    });

    it("reverts if not owner", async function () {
      const { battle, betToken } = await deploy();
      await assert.rejects(
        battle.write.updateAllowedBetToken([betToken.address, true], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateMinimumBetTokenAmount
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateMinimumBetTokenAmount", async function () {
    it("sets min amounts", async function () {
      const { battle } = await deploy();
      await battle.write.updateMinimumBetTokenAmount([parseEther("0.5"), parseEther("10")]);
      assert.equal(await battle.read.minBetAmount([0n]), parseEther("0.5"));
      assert.equal(await battle.read.minBetAmount([1n]), parseEther("10"));
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.updateMinimumBetTokenAmount([1n, 1n], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // createBattle — native ETH
  // ═══════════════════════════════════════════════════════════════════════════

  describe("createBattle (native ETH)", async function () {
    it("transfers ETH to contract", async function () {
      const { battle } = await deployWithNative();
      const before = await publicClient.getBalance({ address: battle.address });
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, zeroAddress],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      assert.equal(await publicClient.getBalance({ address: battle.address }), before + BET_AMOUNT);
    });

    it("stores correct battle info", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      const info = await battle.read.getBattleInfo([battleId]);
      assert.equal(info.selfAddress.toLowerCase(), user1.toLowerCase());
      assert.equal(info.targetAddress, zeroAddress);
      assert.equal(info.betTokenAddress, zeroAddress);
      assert.equal(info.betAmount, BET_AMOUNT);
      assert.equal(info.isStarted, false);
      assert.equal(info.isEnded, false);
    });

    it("increments battle count", async function () {
      const { battle } = await deployWithNative();
      assert.equal(await battle.read.getBattleCount(), 0n);
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, zeroAddress],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      assert.equal(await battle.read.getBattleCount(), 1n);
    });

    it("sets private target address", async function () {
      const { battle } = await deployWithNative();
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, user2],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      const info = await battle.read.getBattleInfo([1n]);
      assert.equal(info.targetAddress.toLowerCase(), user2.toLowerCase());
    });

    it("reverts on wrong ETH amount", async function () {
      const { battle } = await deployWithNative();
      await assert.rejects(
        battle.write.createBattle(
          [zeroAddress, BET_AMOUNT, zeroAddress],
          { account: user1Client.account, value: parseEther("0.5") },
        ),
        /Incorrect ETH amount sent/,
      );
    });

    it("reverts if bet below minimum", async function () {
      const { battle } = await deployWithNative();
      await battle.write.updateMinimumBetTokenAmount([parseEther("2"), 0n]);
      await assert.rejects(
        battle.write.createBattle(
          [zeroAddress, BET_AMOUNT, zeroAddress],
          { account: user1Client.account, value: BET_AMOUNT },
        ),
        /Bet amount below minimum/,
      );
    });

    it("reverts if not available", async function () {
      const { battle } = await deploy();
      await battle.write.updateAllowedBetToken([zeroAddress, true]);
      await assert.rejects(
        battle.write.createBattle(
          [zeroAddress, BET_AMOUNT, zeroAddress],
          { account: user1Client.account, value: BET_AMOUNT },
        ),
        /Cannot create battle/,
      );
    });

    it("reverts if not registered", async function () {
      const { battle } = await deployWithNative();
      await assert.rejects(
        battle.write.createBattle(
          [zeroAddress, BET_AMOUNT, zeroAddress],
          { account: strangerClient.account, value: BET_AMOUNT },
        ),
        /Profile not registered/,
      );
    });

    it("reverts if forbidden", async function () {
      const { battle } = await deployWithNative();
      await battle.write.updateForbiddenToPlay([user1, true]);
      await assert.rejects(
        battle.write.createBattle(
          [zeroAddress, BET_AMOUNT, zeroAddress],
          { account: user1Client.account, value: BET_AMOUNT },
        ),
        /Forbidden to play/,
      );
    });

    it("reverts if targeting self", async function () {
      const { battle } = await deployWithNative();
      await assert.rejects(
        battle.write.createBattle(
          [zeroAddress, BET_AMOUNT, user1],
          { account: user1Client.account, value: BET_AMOUNT },
        ),
        /Cannot target yourself/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // createBattle — ERC20
  // ═══════════════════════════════════════════════════════════════════════════

  describe("createBattle (ERC20)", async function () {
    it("transfers betToken to contract", async function () {
      const { battle, betToken } = await deployWithERC20();
      const before = await betToken.read.balanceOf([battle.address]);
      await battle.write.createBattle(
        [betToken.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      assert.equal(await betToken.read.balanceOf([battle.address]), before + BET_AMOUNT);
    });

    it("stores betTokenAddress in battle info", async function () {
      const { battle, betToken, battleId } = await createERC20OpenBattle();
      const info = await battle.read.getBattleInfo([battleId]);
      assert.equal(info.betTokenAddress.toLowerCase(), betToken.address.toLowerCase());
    });

    it("reverts if ETH sent", async function () {
      const { battle, betToken } = await deployWithERC20();
      await assert.rejects(
        battle.write.createBattle(
          [betToken.address, BET_AMOUNT, zeroAddress],
          { account: user1Client.account, value: 1n },
        ),
        /ETH not accepted for ERC20 bet/,
      );
    });

    it("reverts if token not in whitelist", async function () {
      const { battle, betToken } = await deploy();
      await battle.write.updateAvailableCreateBattle([true]);
      await assert.rejects(
        battle.write.createBattle(
          [betToken.address, BET_AMOUNT, zeroAddress],
          { account: user1Client.account },
        ),
        /Token not allowed/,
      );
    });

  });

  // ═══════════════════════════════════════════════════════════════════════════
  // joinExistBattle
  // ═══════════════════════════════════════════════════════════════════════════

  describe("joinExistBattle", async function () {
    it("transfers ETH on native battle join", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      const before = await publicClient.getBalance({ address: battle.address });
      await battle.write.joinExistBattle([battleId], { account: user2Client.account, value: BET_AMOUNT });
      assert.equal(await publicClient.getBalance({ address: battle.address }), before + BET_AMOUNT);
    });

    it("transfers ERC20 on ERC20 battle join", async function () {
      const { battle, betToken, battleId } = await createERC20OpenBattle();
      const before = await betToken.read.balanceOf([battle.address]);
      await battle.write.joinExistBattle([battleId], { account: user2Client.account });
      assert.equal(await betToken.read.balanceOf([battle.address]), before + BET_AMOUNT);
    });

    it("sets isStarted and targetAddress", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await battle.write.joinExistBattle([battleId], { account: user2Client.account, value: BET_AMOUNT });
      const info = await battle.read.getBattleInfo([battleId]);
      assert.equal(info.isStarted, true);
      assert.equal(info.targetAddress.toLowerCase(), user2.toLowerCase());
    });

    it("invited user can join private battle", async function () {
      const { battle } = await deployWithNative();
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, user2],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      await battle.write.joinExistBattle([1n], { account: user2Client.account, value: BET_AMOUNT });
      assert.equal((await battle.read.getBattleInfo([1n])).isStarted, true);
    });

    it("succeeds even if bet token is removed from whitelist after creation", async function () {
      const { battle, betToken, battleId } = await createERC20OpenBattle();
      await battle.write.updateAllowedBetToken([betToken.address, false]);
      await battle.write.joinExistBattle([battleId], { account: user2Client.account });
      assert.equal((await battle.read.getBattleInfo([battleId])).isStarted, true);
    });

    it("reverts if battle does not exist", async function () {
      const { battle } = await deployWithNative();
      await assert.rejects(
        battle.write.joinExistBattle([999n], { account: user2Client.account, value: BET_AMOUNT }),
        /Battle does not exist/,
      );
    });

    it("reverts if already started", async function () {
      const { battle, battleId } = await startNativeBattle();
      await assert.rejects(
        battle.write.joinExistBattle([battleId], { account: user3Client.account, value: BET_AMOUNT }),
        /Battle already has an opponent/,
      );
    });

    it("reverts if joining own battle", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await assert.rejects(
        battle.write.joinExistBattle([battleId], { account: user1Client.account, value: BET_AMOUNT }),
        /Cannot join own battle/,
      );
    });

    it("reverts if not invited to private battle", async function () {
      const { battle } = await deployWithNative();
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, user2],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      await assert.rejects(
        battle.write.joinExistBattle([1n], { account: user3Client.account, value: BET_AMOUNT }),
        /Not invited to this battle/,
      );
    });

    it("reverts if not registered", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await assert.rejects(
        battle.write.joinExistBattle([battleId], { account: strangerClient.account, value: BET_AMOUNT }),
        /Profile not registered/,
      );
    });

    it("reverts if forbidden", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await battle.write.updateForbiddenToPlay([user2, true]);
      await assert.rejects(
        battle.write.joinExistBattle([battleId], { account: user2Client.account, value: BET_AMOUNT }),
        /Forbidden to play/,
      );
    });

    it("reverts on wrong ETH amount", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await assert.rejects(
        battle.write.joinExistBattle([battleId], { account: user2Client.account, value: parseEther("0.5") }),
        /Incorrect ETH amount sent/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // settleBattle
  // ═══════════════════════════════════════════════════════════════════════════

  describe("settleBattle", async function () {
    it("pays 2x betAmount to native winner", async function () {
      const { battle, battleId } = await startNativeBattle();
      const before = await publicClient.getBalance({ address: user1 });
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      assert.equal(await publicClient.getBalance({ address: user1 }), before + BET_AMOUNT * 2n);
    });

    it("pays 2x betAmount to ERC20 winner", async function () {
      const { battle, betToken, battleId } = await startERC20Battle();
      const before = await betToken.read.balanceOf([user1]);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      assert.equal(await betToken.read.balanceOf([user1]), before + BET_AMOUNT * 2n);
    });

    it("pays bonus token to winner", async function () {
      const { battle, bonusToken, battleId } = await startERC20Battle();
      await bonusToken.write.mint([battle.address, BONUS_AMOUNT]);
      await battle.write.updateBonusToken([bonusToken.address, BONUS_AMOUNT]);
      const before = await bonusToken.read.balanceOf([user2]);
      await battle.write.settleBattle([battleId, user2], { account: liquidatorClient.account });
      assert.equal(await bonusToken.read.balanceOf([user2]), before + BONUS_AMOUNT);
    });

    it("sets isEnded and winner", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      const info = await battle.read.getBattleInfo([battleId]);
      assert.equal(info.isEnded, true);
      assert.equal(info.winner.toLowerCase(), user1.toLowerCase());
    });

    it("cannot settle the same battle twice", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      await assert.rejects(
        battle.write.settleBattle([battleId, user2], { account: liquidatorClient.account }),
        /Battle already ended/,
      );
    });

    it("reverts if not liquidator", async function () {
      const { battle, battleId } = await startNativeBattle();
      await assert.rejects(
        battle.write.settleBattle([battleId, user1], { account: strangerClient.account }),
        /AccessControlUnauthorizedAccount/,
      );
    });

    it("reverts if battle does not exist", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.settleBattle([999n, user1], { account: liquidatorClient.account }),
        /Battle does not exist/,
      );
    });

    it("reverts if opponent has not joined", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await assert.rejects(
        battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account }),
        /Opponent has not joined/,
      );
    });

    it("reverts if invalid winner", async function () {
      const { battle, battleId } = await startNativeBattle();
      await assert.rejects(
        battle.write.settleBattle([battleId, stranger], { account: liquidatorClient.account }),
        /Invalid winner address/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // closeBattle
  // ═══════════════════════════════════════════════════════════════════════════

  describe("closeBattle", async function () {
    it("refunds native bet to creator", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      const before = await publicClient.getBalance({ address: user1 });
      await battle.write.closeBattle([battleId], { account: liquidatorClient.account });
      assert.equal(await publicClient.getBalance({ address: user1 }), before + BET_AMOUNT);
    });

    it("refunds ERC20 bet to creator", async function () {
      const { battle, betToken, battleId } = await createERC20OpenBattle();
      const before = await betToken.read.balanceOf([user1]);
      await battle.write.closeBattle([battleId], { account: liquidatorClient.account });
      assert.equal(await betToken.read.balanceOf([user1]), before + BET_AMOUNT);
    });

    it("sets isEnded flag", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await battle.write.closeBattle([battleId], { account: liquidatorClient.account });
      assert.equal((await battle.read.getBattleInfo([battleId])).isEnded, true);
    });

    it("reverts if battle does not exist", async function () {
      const { battle } = await deployWithNative();
      await assert.rejects(
        battle.write.closeBattle([999n], { account: liquidatorClient.account }),
        /Battle does not exist/,
      );
    });

    it("reverts if battle already started", async function () {
      const { battle, battleId } = await startNativeBattle();
      await assert.rejects(
        battle.write.closeBattle([battleId], { account: liquidatorClient.account }),
        /Battle already has an opponent/,
      );
    });

    it("reverts if battle already ended", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      await assert.rejects(
        battle.write.closeBattle([battleId], { account: liquidatorClient.account }),
        /Battle already ended/,
      );
    });

    it("reverts if not liquidator", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await assert.rejects(
        battle.write.closeBattle([battleId], { account: strangerClient.account }),
        /AccessControlUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // depositToken
  // ═══════════════════════════════════════════════════════════════════════════

  describe("depositToken", async function () {
    it("transfers ERC20 to contract", async function () {
      const { battle, bonusToken } = await deploy();
      await bonusToken.write.mint([owner, parseEther("1000")]);
      await bonusToken.write.approve([battle.address, maxUint256]);
      await battle.write.depositToken([bonusToken.address, parseEther("1000")]);
      assert.equal(await bonusToken.read.balanceOf([battle.address]), parseEther("1000"));
    });

    it("emits TokenDeposited event", async function () {
      const { battle, bonusToken } = await deploy();
      await bonusToken.write.mint([owner, 100n]);
      await bonusToken.write.approve([battle.address, maxUint256]);
      const hash    = await battle.write.depositToken([bonusToken.address, 100n]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("reverts if not owner", async function () {
      const { battle, bonusToken } = await deploy();
      await assert.rejects(
        battle.write.depositToken([bonusToken.address, 1n], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // setProtocolFee / setProtocolFeeRecipient
  // ═══════════════════════════════════════════════════════════════════════════

  describe("setProtocolFee", async function () {
    it("sets the value", async function () {
      const { battle } = await deploy();
      await battle.write.setProtocolFee([300n]);
      assert.equal(await battle.read.protocolFeeBps(), 300n);
    });

    it("allows zero (kill switch)", async function () {
      const { battle } = await deploy();
      await battle.write.setProtocolFee([300n]);
      await battle.write.setProtocolFee([0n]);
      assert.equal(await battle.read.protocolFeeBps(), 0n);
    });

    it("allows up to MAX_PROTOCOL_FEE_BPS", async function () {
      const { battle } = await deploy();
      const cap = await battle.read.MAX_PROTOCOL_FEE_BPS();
      await battle.write.setProtocolFee([cap]);
      assert.equal(await battle.read.protocolFeeBps(), cap);
    });

    it("reverts if exceeds cap", async function () {
      const { battle } = await deploy();
      const cap = await battle.read.MAX_PROTOCOL_FEE_BPS();
      await assert.rejects(
        battle.write.setProtocolFee([cap + 1n]),
        /Fee exceeds cap/,
      );
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.setProtocolFee([100n], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  describe("setProtocolFeeRecipient", async function () {
    it("sets the recipient", async function () {
      const { battle } = await deploy();
      await battle.write.setProtocolFeeRecipient([stranger]);
      assert.equal(
        (await battle.read.protocolFeeRecipient()).toLowerCase(),
        stranger.toLowerCase(),
      );
    });

    it("allows zero (switch to accumulate mode)", async function () {
      const { battle } = await deploy();
      await battle.write.setProtocolFeeRecipient([stranger]);
      await battle.write.setProtocolFeeRecipient([zeroAddress]);
      assert.equal(await battle.read.protocolFeeRecipient(), zeroAddress);
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.setProtocolFeeRecipient([stranger], { account: strangerClient.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // settleBattle — protocol fee
  // ═══════════════════════════════════════════════════════════════════════════

  describe("settleBattle (protocol fee)", async function () {
    it("with fee=0 pays full reward and recipient gets nothing", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.setProtocolFeeRecipient([stranger]);

      const userBefore  = await publicClient.getBalance({ address: user1 });
      const recipBefore = await publicClient.getBalance({ address: stranger });
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      assert.equal(await publicClient.getBalance({ address: user1 }), userBefore + BET_AMOUNT * 2n);
      assert.equal(await publicClient.getBalance({ address: stranger }), recipBefore);
    });

    it("pushes fee to recipient when set (push mode)", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.setProtocolFeeRecipient([stranger]);
      await battle.write.setProtocolFee([300n]); // 3 %
      const expectedFee = (BET_AMOUNT * 2n * 300n) / 10000n;

      const userBefore  = await publicClient.getBalance({ address: user1 });
      const recipBefore = await publicClient.getBalance({ address: stranger });
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      assert.equal(await publicClient.getBalance({ address: stranger }), recipBefore + expectedFee);
      assert.equal(
        await publicClient.getBalance({ address: user1 }),
        userBefore + BET_AMOUNT * 2n - expectedFee,
      );
      assert.equal(await battle.read.accruedProtocolFees([zeroAddress]), 0n);
    });

    it("accrues fee to accumulator when recipient is zero (pull mode)", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.setProtocolFee([300n]);
      const expectedFee = (BET_AMOUNT * 2n * 300n) / 10000n;

      const userBefore = await publicClient.getBalance({ address: user1 });
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      assert.equal(await battle.read.accruedProtocolFees([zeroAddress]), expectedFee);
      assert.equal(
        await publicClient.getBalance({ address: user1 }),
        userBefore + BET_AMOUNT * 2n - expectedFee,
      );
    });

    it("accrues fee for ERC20 token", async function () {
      const { battle, betToken, battleId } = await startERC20Battle();
      await battle.write.setProtocolFee([500n]); // 5 %
      const expectedFee = (BET_AMOUNT * 2n * 500n) / 10000n;

      const userBefore = await betToken.read.balanceOf([user1]);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      assert.equal(await battle.read.accruedProtocolFees([betToken.address]), expectedFee);
      assert.equal(
        await betToken.read.balanceOf([user1]),
        userBefore + BET_AMOUNT * 2n - expectedFee,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // withdrawProtocolFees
  // ═══════════════════════════════════════════════════════════════════════════

  describe("withdrawProtocolFees", async function () {
    it("withdraws full accumulated ETH fee", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.setProtocolFee([300n]);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      const accrued = await battle.read.accruedProtocolFees([zeroAddress]);
      const before  = await publicClient.getBalance({ address: stranger });
      await battle.write.withdrawProtocolFees([zeroAddress, stranger, accrued]);

      assert.equal(await publicClient.getBalance({ address: stranger }), before + accrued);
      assert.equal(await battle.read.accruedProtocolFees([zeroAddress]), 0n);
    });

    it("supports partial ERC20 withdraw", async function () {
      const { battle, betToken, battleId } = await startERC20Battle();
      await battle.write.setProtocolFee([300n]);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      const accrued = await battle.read.accruedProtocolFees([betToken.address]);
      const half    = accrued / 2n;
      await battle.write.withdrawProtocolFees([betToken.address, stranger, half]);

      assert.equal(await betToken.read.balanceOf([stranger]), half);
      assert.equal(await battle.read.accruedProtocolFees([betToken.address]), accrued - half);
    });

    it("reverts if amount exceeds accrued", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.setProtocolFee([300n]);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      const accrued = await battle.read.accruedProtocolFees([zeroAddress]);

      await assert.rejects(
        battle.write.withdrawProtocolFees([zeroAddress, stranger, accrued + 1n]),
        /Amount exceeds accrued fees/,
      );
    });

    it("reverts if destination is zero", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.withdrawProtocolFees([zeroAddress, zeroAddress, 1n]),
        /Invalid address/,
      );
    });

    it("reverts if amount is zero", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.withdrawProtocolFees([zeroAddress, stranger, 0n]),
        /Amount must be > 0/,
      );
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.withdrawProtocolFees(
          [zeroAddress, stranger, 1n],
          { account: strangerClient.account },
        ),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // outstandingBets accounting
  // ═══════════════════════════════════════════════════════════════════════════

  describe("outstandingBets", async function () {
    it("increments on createBattle", async function () {
      const { battle } = await deployWithNative();
      assert.equal(await battle.read.outstandingBets([zeroAddress]), 0n);
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, zeroAddress],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      assert.equal(await battle.read.outstandingBets([zeroAddress]), BET_AMOUNT);
    });

    it("increments on join (total = 2 × bet)", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      await battle.write.joinExistBattle([battleId], { account: user2Client.account, value: BET_AMOUNT });
      assert.equal(await battle.read.outstandingBets([zeroAddress]), BET_AMOUNT * 2n);
    });

    it("returns to zero after settle", async function () {
      const { battle, battleId } = await startNativeBattle();
      assert.equal(await battle.read.outstandingBets([zeroAddress]), BET_AMOUNT * 2n);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      assert.equal(await battle.read.outstandingBets([zeroAddress]), 0n);
    });

    it("returns to zero after close", async function () {
      const { battle, battleId } = await createNativeOpenBattle();
      assert.equal(await battle.read.outstandingBets([zeroAddress]), BET_AMOUNT);
      await battle.write.closeBattle([battleId], { account: liquidatorClient.account });
      assert.equal(await battle.read.outstandingBets([zeroAddress]), 0n);
    });

    it("tracks ERC20 bets separately from ETH bets", async function () {
      const { battle, betToken } = await startERC20Battle();
      assert.equal(await battle.read.outstandingBets([betToken.address]), BET_AMOUNT * 2n);
      assert.equal(await battle.read.outstandingBets([zeroAddress]), 0n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // rescueExtraTokens
  // ═══════════════════════════════════════════════════════════════════════════

  describe("rescueExtraTokens", async function () {
    it("rescues unused tokens previously deposited via depositToken", async function () {
      const { battle, bonusToken } = await deploy();
      await bonusToken.write.mint([owner, parseEther("1000")]);
      await bonusToken.write.approve([battle.address, maxUint256]);
      await battle.write.depositToken([bonusToken.address, parseEther("1000")]);

      await battle.write.rescueExtraTokens([bonusToken.address, stranger, parseEther("1000")]);
      assert.equal(await bonusToken.read.balanceOf([stranger]), parseEther("1000"));
    });

    it("cannot drain locked battle bets", async function () {
      const { battle } = await startNativeBattle();
      await assert.rejects(
        battle.write.rescueExtraTokens([zeroAddress, stranger, 1n]),
        /Amount exceeds rescuable balance/,
      );
    });

    it("cannot drain accrued protocol fees", async function () {
      const { battle, battleId } = await startNativeBattle();
      await battle.write.setProtocolFee([300n]);
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      // After settle, contract balance equals accruedFees exactly — nothing rescuable
      const fees = await battle.read.accruedProtocolFees([zeroAddress]);
      assert.equal(await publicClient.getBalance({ address: battle.address }), fees);

      await assert.rejects(
        battle.write.rescueExtraTokens([zeroAddress, stranger, 1n]),
        /Amount exceeds rescuable balance/,
      );
    });

    it("rescues ERC20 sent directly to the contract", async function () {
      const { battle, bonusToken } = await deploy();
      await bonusToken.write.mint([battle.address, parseEther("100")]);
      await battle.write.rescueExtraTokens([bonusToken.address, stranger, parseEther("100")]);
      assert.equal(await bonusToken.read.balanceOf([stranger]), parseEther("100"));
    });

    it("reverts if destination is zero", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.rescueExtraTokens([zeroAddress, zeroAddress, 1n]),
        /Invalid address/,
      );
    });

    it("reverts if amount is zero", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.rescueExtraTokens([zeroAddress, stranger, 0n]),
        /Amount must be > 0/,
      );
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.rescueExtraTokens(
          [zeroAddress, stranger, 1n],
          { account: strangerClient.account },
        ),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getBattleInfo / getBattleCount
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getBattleCount", async function () {
    it("starts at zero", async function () {
      const { battle } = await deploy();
      assert.equal(await battle.read.getBattleCount(), 0n);
    });

    it("increments on each createBattle", async function () {
      const { battle } = await deployWithNative();
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, zeroAddress],
        { account: user1Client.account, value: BET_AMOUNT },
      );
      await battle.write.createBattle(
        [zeroAddress, BET_AMOUNT, zeroAddress],
        { account: user2Client.account, value: BET_AMOUNT },
      );
      assert.equal(await battle.read.getBattleCount(), 2n);
    });
  });

  describe("getBattleInfo", async function () {
    it("returns zero-value struct for non-existent battle", async function () {
      const { battle } = await deploy();
      const info = await battle.read.getBattleInfo([999n]);
      assert.equal(info.selfAddress, zeroAddress);
      assert.equal(info.isStarted, false);
      assert.equal(info.isEnded, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // M-1 — bonus failure must NOT block settlement
  // ═══════════════════════════════════════════════════════════════════════════

  describe("M-1: bonus failure handling", async function () {
    it("settle succeeds even if bonus pool is empty", async function () {
      const { battle, bonusToken, battleId } = await startNativeBattle();
      // Configure a bonus the contract cannot pay (no deposit)
      await battle.write.updateBonusToken([bonusToken.address, BONUS_AMOUNT]);

      const before = await publicClient.getBalance({ address: user1 });
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      // Winner still got the main reward
      assert.equal(await publicClient.getBalance({ address: user1 }), before + BET_AMOUNT * 2n);
      assert.equal((await battle.read.getBattleInfo([battleId])).isEnded, true);
      // Bonus was skipped
      assert.equal(await bonusToken.read.balanceOf([user1]), 0n);
    });

    it("bonus paid normally when pool is funded", async function () {
      const { battle, bonusToken, battleId } = await startNativeBattle();
      await bonusToken.write.mint([battle.address, BONUS_AMOUNT]);
      await battle.write.updateBonusToken([bonusToken.address, BONUS_AMOUNT]);

      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      assert.equal(await bonusToken.read.balanceOf([user1]), BONUS_AMOUNT);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // M-2 — fee push failure must NOT block settlement (falls back to accrual)
  // ═══════════════════════════════════════════════════════════════════════════

  describe("M-2: fee push fallback to accrual", async function () {
    it("falls back to accrual when recipient is a reverting contract", async function () {
      const { battle, battleId } = await startNativeBattle();
      const bad = await viem.deployContract("MockRevertingReceiver");
      await battle.write.setProtocolFeeRecipient([bad.address]);
      await battle.write.setProtocolFee([300n]);
      const expectedFee = (BET_AMOUNT * 2n * 300n) / 10000n;

      const userBefore = await publicClient.getBalance({ address: user1 });
      // MUST NOT revert
      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });

      // Winner got their net reward
      assert.equal(
        await publicClient.getBalance({ address: user1 }),
        userBefore + BET_AMOUNT * 2n - expectedFee,
      );
      // Bad recipient got nothing
      assert.equal(await publicClient.getBalance({ address: bad.address }), 0n);
      // Fee was accrued — protocol still gets paid, just deferred
      assert.equal(await battle.read.accruedProtocolFees([zeroAddress]), expectedFee);
    });

    it("admin can withdraw the fallback-accrued fee", async function () {
      const { battle, battleId } = await startNativeBattle();
      const bad = await viem.deployContract("MockRevertingReceiver");
      await battle.write.setProtocolFeeRecipient([bad.address]);
      await battle.write.setProtocolFee([300n]);

      await battle.write.settleBattle([battleId, user1], { account: liquidatorClient.account });
      const accrued = await battle.read.accruedProtocolFees([zeroAddress]);
      const before  = await publicClient.getBalance({ address: stranger });

      await battle.write.withdrawProtocolFees([zeroAddress, stranger, accrued]);
      assert.equal(await publicClient.getBalance({ address: stranger }), before + accrued);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // M-3 — fee-on-transfer tokens must be rejected at receive time
  // ═══════════════════════════════════════════════════════════════════════════

  describe("M-3: fee-on-transfer token rejection", async function () {
    async function deployWithFoT() {
      const d = await deploy();
      const fot = await viem.deployContract("MockFeeOnTransferERC20");
      await fot.write.mint([user1, parseEther("10000")]);
      await fot.write.approve([d.battle.address, maxUint256], { account: user1Client.account });
      await d.battle.write.updateAvailableCreateBattle([true]);
      await d.battle.write.updateAllowedBetToken([fot.address, true]);
      await d.battle.write.updateMinimumBetTokenAmount([0n, 1n]);
      return { ...d, fot };
    }

    it("rejects createBattle when bet token is fee-on-transfer", async function () {
      const { battle, fot } = await deployWithFoT();
      await assert.rejects(
        battle.write.createBattle(
          [fot.address, BET_AMOUNT, zeroAddress],
          { account: user1Client.account },
        ),
        /Token not supported \(fee-on-transfer\)/,
      );
    });

    it("failed bet leaves no state change (player keeps their tokens)", async function () {
      const { battle, fot } = await deployWithFoT();

      const userBefore     = await fot.read.balanceOf([user1]);
      const contractBefore = await fot.read.balanceOf([battle.address]);
      const outstandBefore = await battle.read.outstandingBets([fot.address]);
      const countBefore    = await battle.read.getBattleCount();

      await assert.rejects(
        battle.write.createBattle(
          [fot.address, BET_AMOUNT, zeroAddress],
          { account: user1Client.account },
        ),
      );

      assert.equal(await fot.read.balanceOf([user1]), userBefore);
      assert.equal(await fot.read.balanceOf([battle.address]), contractBefore);
      assert.equal(await battle.read.outstandingBets([fot.address]), outstandBefore);
      assert.equal(await battle.read.getBattleCount(), countBefore);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STI — bonus must not consume balance reserved for other battles
  // ═══════════════════════════════════════════════════════════════════════════

  describe("STI: bonus skip when reserved balance is insufficient", async function () {
    it("bonus is skipped when bonusToken == betToken and pool is fully reserved", async function () {
      const d = await deployWithERC20();
      // Make sure user3 has tokens + approval so they can join battle 2.
      await d.betToken.write.mint([user3, parseEther("10000")]);
      await d.betToken.write.approve(
        [d.battle.address, maxUint256],
        { account: user3Client.account },
      );

      // Two parallel battles, same bet token.
      await d.battle.write.createBattle(
        [d.betToken.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      await d.battle.write.joinExistBattle([1n], { account: user2Client.account });

      await d.battle.write.createBattle(
        [d.betToken.address, BET_AMOUNT, zeroAddress],
        { account: user2Client.account },
      );
      await d.battle.write.joinExistBattle([2n], { account: user3Client.account });

      // Bonus token == bet token. No separate deposit — the only balance on hand
      // is the locked stakes of the two battles.
      await d.battle.write.updateBonusToken([d.betToken.address, BONUS_AMOUNT]);

      const winnerBefore = await d.betToken.read.balanceOf([user1]);
      await d.battle.write.settleBattle([1n, user1], { account: liquidatorClient.account });

      // Winner got main reward only (no bonus on top, because paying the bonus
      // would have dipped into battle 2's locked stake).
      assert.equal(
        await d.betToken.read.balanceOf([user1]),
        winnerBefore + BET_AMOUNT * 2n,
      );
      // Battle 2's stake is still fully covered by contract balance.
      assert.equal(
        await d.betToken.read.balanceOf([d.battle.address]),
        await d.battle.read.outstandingBets([d.betToken.address]),
      );
      assert.equal(
        await d.battle.read.outstandingBets([d.betToken.address]),
        BET_AMOUNT * 2n,
      );
    });

    it("bonus IS paid when a separate reserve covers it (sanity)", async function () {
      const d = await deployWithERC20();
      await d.battle.write.createBattle(
        [d.betToken.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      await d.battle.write.joinExistBattle([1n], { account: user2Client.account });

      // Deposit BONUS_AMOUNT of the SAME bet token as an extra reserve.
      await d.betToken.write.mint([owner, BONUS_AMOUNT]);
      await d.betToken.write.approve([d.battle.address, maxUint256]);
      await d.battle.write.depositToken([d.betToken.address, BONUS_AMOUNT]);

      await d.battle.write.updateBonusToken([d.betToken.address, BONUS_AMOUNT]);

      const before = await d.betToken.read.balanceOf([user1]);
      await d.battle.write.settleBattle([1n, user1], { account: liquidatorClient.account });
      assert.equal(
        await d.betToken.read.balanceOf([user1]),
        before + BET_AMOUNT * 2n + BONUS_AMOUNT,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TCR — malformed token return data must not revert settlement
  // ═══════════════════════════════════════════════════════════════════════════

  describe("TCR: malformed token return data", async function () {
    it("settlement completes when bonus token returns 64 bytes of junk", async function () {
      const d = await startNativeBattle();
      const malf = await viem.deployContract("MockMalformedReturnERC20");
      await malf.write.mint([d.battle.address, BONUS_AMOUNT]);
      await d.battle.write.updateBonusToken([malf.address, BONUS_AMOUNT]);

      const winnerBefore = await publicClient.getBalance({ address: user1 });
      // MUST NOT revert — the bonus token's malformed return value must not
      // tear down the entire settlement transaction.
      await d.battle.write.settleBattle([1n, user1], { account: liquidatorClient.account });

      // Main reward delivered, battle finalized.
      assert.equal(
        await publicClient.getBalance({ address: user1 }),
        winnerBefore + BET_AMOUNT * 2n,
      );
      assert.equal((await d.battle.read.getBattleInfo([1n])).isEnded, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AME — _tryPayout must treat any non-zero 32-byte return as success
  //         (not only the canonical `1`), otherwise a successful transfer with
  //         a non-canonical return would be mis-flagged as failure.
  // ═══════════════════════════════════════════════════════════════════════════

  describe("AME: non-canonical success return is treated as success", async function () {
    it("bonus token returning 2 (instead of 1) is recognized as success", async function () {
      const d = await startNativeBattle();
      const weird = await viem.deployContract("MockWeirdSuccessERC20");
      await weird.write.mint([d.battle.address, BONUS_AMOUNT]);
      await d.battle.write.updateBonusToken([weird.address, BONUS_AMOUNT]);

      const winnerBonusBefore = await weird.read.balanceOf([user1]);
      const battleBonusBefore = await weird.read.balanceOf([d.battle.address]);

      await d.battle.write.settleBattle([1n, user1], { account: liquidatorClient.account });

      // The transfer DID happen — winner now holds the bonus.
      assert.equal(
        await weird.read.balanceOf([user1]),
        winnerBonusBefore + BONUS_AMOUNT,
      );
      assert.equal(
        await weird.read.balanceOf([d.battle.address]),
        battleBonusBefore - BONUS_AMOUNT,
      );
      // Battle finalized normally.
      assert.equal((await d.battle.read.getBattleInfo([1n])).isEnded, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ZBB — zero-bet battles must not trigger bonus payouts
  // ═══════════════════════════════════════════════════════════════════════════

  describe("ZBB: zero-bet battles", async function () {
    it("no bonus is paid when minBet is 0 and a battle is created with bet=0", async function () {
      const d = await deploy();
      await d.battle.write.updateAvailableCreateBattle([true]);
      await d.battle.write.updateAllowedBetToken([d.betToken.address, true]);
      // Allow zero ERC20 bets.
      await d.battle.write.updateMinimumBetTokenAmount([0n, 0n]);

      await d.bonusToken.write.mint([d.battle.address, BONUS_AMOUNT]);
      await d.battle.write.updateBonusToken([d.bonusToken.address, BONUS_AMOUNT]);

      await d.battle.write.createBattle(
        [d.betToken.address, 0n, zeroAddress],
        { account: user1Client.account },
      );
      await d.battle.write.joinExistBattle([1n], { account: user2Client.account });

      // Settle must succeed (no main reward to pay because bet=0).
      await d.battle.write.settleBattle([1n, user1], { account: liquidatorClient.account });

      // The bonus pool is untouched — winner did not earn the bonus.
      assert.equal(await d.bonusToken.read.balanceOf([user1]), 0n);
      assert.equal(await d.bonusToken.read.balanceOf([d.battle.address]), BONUS_AMOUNT);
    });

    it("bonus IS paid when bet > 0 (regression for the ZBB gate)", async function () {
      const d = await deployWithERC20();
      await d.bonusToken.write.mint([d.battle.address, BONUS_AMOUNT]);
      await d.battle.write.updateBonusToken([d.bonusToken.address, BONUS_AMOUNT]);

      await d.battle.write.createBattle(
        [d.betToken.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      await d.battle.write.joinExistBattle([1n], { account: user2Client.account });
      await d.battle.write.settleBattle([1n, user1], { account: liquidatorClient.account });

      assert.equal(await d.bonusToken.read.balanceOf([user1]), BONUS_AMOUNT);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RWP — pull-payment fallback + claimPayout
  // ═══════════════════════════════════════════════════════════════════════════

  describe("RWP: pull-payment fallback", async function () {
    /// Deploy a battle environment using HapToken as the bet token, so we can
    /// blacklist a player and force the push to revert from inside the token.
    async function deployWithHapBet() {
      const d = await deploy();
      const hap = await viem.deployContract("HapToken", [owner]);
      await hap.write.transfer([user1, parseEther("10000")]);
      await hap.write.transfer([user2, parseEther("10000")]);
      await hap.write.approve(
        [d.battle.address, maxUint256],
        { account: user1Client.account },
      );
      await hap.write.approve(
        [d.battle.address, maxUint256],
        { account: user2Client.account },
      );
      await d.battle.write.updateAvailableCreateBattle([true]);
      await d.battle.write.updateAllowedBetToken([hap.address, true]);
      await d.battle.write.updateMinimumBetTokenAmount([0n, 1n]);
      return { ...d, hap };
    }

    async function startedHapBattle() {
      const d = await deployWithHapBet();
      await d.battle.write.createBattle(
        [d.hap.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      await d.battle.write.joinExistBattle([1n], { account: user2Client.account });
      return { ...d, battleId: 1n };
    }

    it("settleBattle does NOT revert when winner is blacklisted on the bet token", async function () {
      const d = await startedHapBattle();
      await d.hap.write.blacklist([user1]);

      // MUST NOT revert.
      await d.battle.write.settleBattle(
        [d.battleId, user1],
        { account: liquidatorClient.account },
      );

      // Battle ended cleanly.
      assert.equal((await d.battle.read.getBattleInfo([d.battleId])).isEnded, true);
      // The push failed — user1 did not receive the payout directly.
      assert.equal(await d.hap.read.balanceOf([user1]), parseEther("10000") - BET_AMOUNT);
      // The reward is credited to pendingPayouts instead.
      assert.equal(
        await d.battle.read.pendingPayouts([d.hap.address, user1]),
        BET_AMOUNT * 2n,
      );
      // And tracked under reserved so rescue can't touch it.
      assert.equal(
        await d.battle.read.reservedPendingPayouts([d.hap.address]),
        BET_AMOUNT * 2n,
      );
    });

    it("winner can claim payout after being unblacklisted", async function () {
      const d = await startedHapBattle();
      await d.hap.write.blacklist([user1]);
      await d.battle.write.settleBattle(
        [d.battleId, user1],
        { account: liquidatorClient.account },
      );

      await d.hap.write.unblacklist([user1]);

      const before = await d.hap.read.balanceOf([user1]);
      await d.battle.write.claimPayout(
        [d.hap.address],
        { account: user1Client.account },
      );
      assert.equal(
        await d.hap.read.balanceOf([user1]) - before,
        BET_AMOUNT * 2n,
      );

      // pendingPayouts and the reservation drop back to zero.
      assert.equal(
        await d.battle.read.pendingPayouts([d.hap.address, user1]),
        0n,
      );
      assert.equal(
        await d.battle.read.reservedPendingPayouts([d.hap.address]),
        0n,
      );
    });

    it("claimPayout reverts when there is nothing to claim", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.claimPayout(
          [zeroAddress],
          { account: user1Client.account },
        ),
        /Nothing to claim/,
      );
    });

    it("rescueExtraTokens cannot drain pending-payout reserve", async function () {
      const d = await startedHapBattle();
      await d.hap.write.blacklist([user1]);
      await d.battle.write.settleBattle(
        [d.battleId, user1],
        { account: liquidatorClient.account },
      );

      // Whole contract balance is now reserved for user1's pending payout.
      await assert.rejects(
        d.battle.write.rescueExtraTokens([d.hap.address, stranger, 1n]),
        /Amount exceeds rescuable balance/,
      );
    });

    it("closeBattle falls back to pendingPayouts when the creator is blacklisted", async function () {
      const d = await deployWithHapBet();
      await d.battle.write.createBattle(
        [d.hap.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      // Creator user1 gets blacklisted before close.
      await d.hap.write.blacklist([user1]);

      // closeBattle MUST still succeed — the refund goes to pendingPayouts.
      await d.battle.write.closeBattle(
        [1n],
        { account: liquidatorClient.account },
      );

      assert.equal((await d.battle.read.getBattleInfo([1n])).isEnded, true);
      assert.equal(
        await d.battle.read.pendingPayouts([d.hap.address, user1]),
        BET_AMOUNT,
      );
    });

    it("subsequent claim succeeds for a refunded creator after unblacklist", async function () {
      const d = await deployWithHapBet();
      await d.battle.write.createBattle(
        [d.hap.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      await d.hap.write.blacklist([user1]);
      await d.battle.write.closeBattle(
        [1n],
        { account: liquidatorClient.account },
      );
      await d.hap.write.unblacklist([user1]);

      const before = await d.hap.read.balanceOf([user1]);
      await d.battle.write.claimPayout(
        [d.hap.address],
        { account: user1Client.account },
      );
      assert.equal(
        await d.hap.read.balanceOf([user1]) - before,
        BET_AMOUNT,
      );
    });
  });
});
