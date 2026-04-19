import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes, zeroAddress, parseEther, maxUint256 } from "viem";

const LIQUIDATOR_ROLE = keccak256(toBytes("LIQUIDATOR_ROLE"));

const BET_AMOUNT   = parseEther("1");
const FEE_AMOUNT   = parseEther("0.1");
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

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deploy() {
    const hapToken   = await viem.deployContract("MockERC20");
    const profile    = await viem.deployContract("HeroArenaProfile", [hapToken.address, 0n, 0n]);
    const betToken   = await viem.deployContract("MockERC20");
    const feeToken   = await viem.deployContract("MockERC20");
    const bonusToken = await viem.deployContract("MockERC20");

    // Register users
    await profile.write.addTeam(["Warriors", "Warriors team"]);
    await profile.write.createProfile([1n], { account: user1Client.account });
    await profile.write.createProfile([1n], { account: user2Client.account });
    await profile.write.createProfile([1n], { account: user3Client.account });

    // Deploy battle contract
    const battle = await viem.deployContract("HeroArenaBattle", [profile.address]);
    await battle.write.grantRole([LIQUIDATOR_ROLE, liquidator]);

    // Fund users
    await betToken.write.mint([user1, parseEther("10000")]);
    await betToken.write.mint([user2, parseEther("10000")]);
    await feeToken.write.mint([user1, parseEther("10000")]);
    await feeToken.write.mint([user2, parseEther("10000")]);

    await betToken.write.approve([battle.address, maxUint256], { account: user1Client.account });
    await betToken.write.approve([battle.address, maxUint256], { account: user2Client.account });
    await feeToken.write.approve([battle.address, maxUint256], { account: user1Client.account });
    await feeToken.write.approve([battle.address, maxUint256], { account: user2Client.account });

    return { profile, battle, betToken, feeToken, bonusToken };
  }

  async function deployWithNative() {
    const d = await deploy();
    await d.battle.write.updateAvailableCreateBattle([true]);
    await d.battle.write.updateAllowedBetToken([zeroAddress, true]);
    await d.battle.write.updateMinimunBetTokenAmount([parseEther("0.01"), 0n]);
    return d;
  }

  async function deployWithERC20() {
    const d = await deploy();
    await d.battle.write.updateAvailableCreateBattle([true]);
    await d.battle.write.updateAllowedBetToken([d.betToken.address, true]);
    await d.battle.write.updateMinimunBetTokenAmount([0n, 1n]);
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
  // updateFeeAndBounsTokenAddressWithAmount
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateFeeAndBounsTokenAddressWithAmount", async function () {
    it("sets token addresses and amounts", async function () {
      const { battle, feeToken, bonusToken } = await deploy();
      await battle.write.updateFeeAndBounsTokenAddressWithAmount([
        feeToken.address, FEE_AMOUNT, bonusToken.address, BONUS_AMOUNT,
      ]);
      assert.equal((await battle.read.tokenAddresses([0n])).toLowerCase(), feeToken.address.toLowerCase());
      assert.equal((await battle.read.tokenAddresses([1n])).toLowerCase(), bonusToken.address.toLowerCase());
      assert.equal(await battle.read.tokenAmounts([0n]), FEE_AMOUNT);
      assert.equal(await battle.read.tokenAmounts([1n]), BONUS_AMOUNT);
    });

    it("reverts if not owner", async function () {
      const { battle, feeToken } = await deploy();
      await assert.rejects(
        battle.write.updateFeeAndBounsTokenAddressWithAmount(
          [feeToken.address, 1n, zeroAddress, 0n],
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
  // updateMinimunBetTokenAmount
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateMinimunBetTokenAmount", async function () {
    it("sets min amounts", async function () {
      const { battle } = await deploy();
      await battle.write.updateMinimunBetTokenAmount([parseEther("0.5"), parseEther("10")]);
      assert.equal(await battle.read.minBetAmount([0n]), parseEther("0.5"));
      assert.equal(await battle.read.minBetAmount([1n]), parseEther("10"));
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.updateMinimunBetTokenAmount([1n, 1n], { account: strangerClient.account }),
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
      await battle.write.updateMinimunBetTokenAmount([parseEther("2"), 0n]);
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
        /BetToken not allowed/,
      );
    });

    it("collects feeToken on creation", async function () {
      const { battle, betToken, feeToken } = await deployWithERC20();
      await battle.write.updateFeeAndBounsTokenAddressWithAmount([
        feeToken.address, FEE_AMOUNT, zeroAddress, 0n,
      ]);
      await battle.write.createBattle(
        [betToken.address, BET_AMOUNT, zeroAddress],
        { account: user1Client.account },
      );
      assert.equal(await feeToken.read.balanceOf([battle.address]), FEE_AMOUNT);
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

    it("collects feeToken from both players", async function () {
      const { battle, betToken, feeToken } = await deployWithERC20();
      await battle.write.updateFeeAndBounsTokenAddressWithAmount([
        feeToken.address, FEE_AMOUNT, zeroAddress, 0n,
      ]);
      await battle.write.createBattle([betToken.address, BET_AMOUNT, zeroAddress], { account: user1Client.account });
      await battle.write.joinExistBattle([1n], { account: user2Client.account });
      assert.equal(await feeToken.read.balanceOf([battle.address]), FEE_AMOUNT * 2n);
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
      // user3 is registered but not the invited opponent (user2)
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
      const { battle, betToken, bonusToken, battleId } = await startERC20Battle();
      await bonusToken.write.mint([battle.address, BONUS_AMOUNT]);
      await battle.write.updateFeeAndBounsTokenAddressWithAmount([
        zeroAddress, 0n, bonusToken.address, BONUS_AMOUNT,
      ]);
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
        /Not an liquidator role/,
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
  // claimTokens
  // ═══════════════════════════════════════════════════════════════════════════

  describe("claimTokens", async function () {
    it("transfers ETH to destination", async function () {
      const { battle, battleId } = await startNativeBattle();
      const dest = stranger;
      const before = await publicClient.getBalance({ address: dest });
      await battle.write.claimTokens([dest, []]);
      assert.equal(await publicClient.getBalance({ address: dest }), before + BET_AMOUNT * 2n);
    });

    it("transfers ERC20 to destination", async function () {
      const { battle, betToken, battleId } = await startERC20Battle();
      const dest = stranger;
      await battle.write.claimTokens([dest, [betToken.address]]);
      assert.equal(await betToken.read.balanceOf([dest]), BET_AMOUNT * 2n);
    });

    it("reverts if destination is zero address", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.claimTokens([zeroAddress, []]),
        /Invalid destination/,
      );
    });

    it("reverts if not owner", async function () {
      const { battle } = await deploy();
      await assert.rejects(
        battle.write.claimTokens([stranger, []], { account: strangerClient.account }),
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
});
