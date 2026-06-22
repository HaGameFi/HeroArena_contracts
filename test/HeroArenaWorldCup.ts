import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes, zeroAddress, parseEther, maxUint256 } from "viem";

const LIQUIDATOR_ROLE = keccak256(toBytes("LIQUIDATOR_ROLE"));
const REG_FEE = parseEther("100");

describe("HeroArenaWorldCup (Deployer + Initializable)", async function () {
  const { viem } = await network.connect();
  const testClient = await viem.getTestClient();
  const publicClient = await viem.getPublicClient();

  const [ownerClient, aliceClient, bobClient, carolClient, strangerClient] =
    await viem.getWalletClients();

  const owner = ownerClient.account.address;
  const alice = aliceClient.account.address;
  const bob = bobClient.account.address;
  const carol = carolClient.account.address;
  const stranger = strangerClient.account.address;

  // ─── helpers ──────────────────────────────────────────────────────────────

  async function advanceTimeTo(ts: bigint) {
    await testClient.setNextBlockTimestamp({ timestamp: ts });
    await testClient.mine({ blocks: 1 });
  }

  async function futureTs(deltaSeconds: bigint) {
    const block = await publicClient.getBlock();
    return block.timestamp + deltaSeconds;
  }

  /**
   * Deploy the full stack and produce a WorldCup via the Deployer's create2 flow.
   * `admin` defaults to `owner` so onlyOwner calls can be made by the default client.
   */
  async function deploy(opts?: { bonusToken?: `0x${string}`; bonusAmount?: bigint }) {
    const hap = await viem.deployContract("MockERC20");
    const bonusTok = await viem.deployContract("MockERC20");
    const profile = await viem.deployContract("MockHeroArenaProfile");

    const deployer = await viem.deployContract("HeroArenaWorldCupDeployer", [
      hap.address,
      REG_FEE,
      profile.address,
    ]);

    const bonusToken = opts?.bonusToken ?? zeroAddress;
    const bonusAmount = opts?.bonusAmount ?? 0n;

    await deployer.write.createWC([owner, bonusToken, bonusAmount]);
    const wcAddr = await deployer.read.currentWCAddress();
    const wc = await viem.getContractAt("HeroArenaWorldCupInitializable", wcAddr);

    return { hap, bonusTok, profile, deployer, wc };
  }

  async function openRegistration(wc: any) {
    await wc.write.setRegisterDeadline([await futureTs(7n * 24n * 60n * 60n)]);
  }

  async function register(wc: any, hap: any, profile: any, playerClient: any) {
    const player = playerClient.account.address;
    await profile.write.setRegistered([player, true]);
    await hap.write.mint([player, REG_FEE]);
    await hap.write.approve([wc.address, REG_FEE], { account: playerClient.account });
    await wc.write.registerBattle([REG_FEE], { account: playerClient.account });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Deployer
  // ═══════════════════════════════════════════════════════════════════════════

  describe("Deployer.createWC", async function () {
    it("forwards deps into the deployed WorldCup (C-1)", async function () {
      const { wc, hap, profile } = await deploy();
      assert.equal((await wc.read.HapToken()).toLowerCase(), hap.address.toLowerCase());
      assert.equal(await wc.read.registrationFee(), REG_FEE);
      assert.equal(
        (await wc.read.HeroArenaProfileSC()).toLowerCase(),
        profile.address.toLowerCase(),
      );
      assert.equal((await wc.read.owner()).toLowerCase(), owner.toLowerCase());
    });

    it("seeds the admin with LIQUIDATOR_ROLE (H-3)", async function () {
      const { wc } = await deploy();
      assert.equal(await wc.read.hasRole([LIQUIDATOR_ROLE, owner]), true);
    });

    it("rejects a zero admin (H-2)", async function () {
      const { deployer } = await deploy();
      await assert.rejects(
        deployer.write.createWC([zeroAddress, zeroAddress, 0n]),
        /admin cannot be zero/,
      );
    });

    it("rejects an EOA bonus token (M-3)", async function () {
      const { deployer } = await deploy();
      await assert.rejects(
        deployer.write.createWC([owner, stranger, parseEther("1")]),
        /Bonus token must be a contract/,
      );
    });

    it("deploys distinct contracts for identical params (H-1)", async function () {
      const { deployer } = await deploy();
      const first = await deployer.read.currentWCAddress();
      await deployer.write.createWC([owner, zeroAddress, 0n]);
      const second = await deployer.read.currentWCAddress();
      assert.notEqual(first.toLowerCase(), second.toLowerCase());
      assert.equal(await deployer.read.deployNonce(), 2n);
    });

    it("is owner-only", async function () {
      const { deployer } = await deploy();
      await assert.rejects(
        deployer.write.createWC([owner, zeroAddress, 0n], {
          account: strangerClient.account,
        }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Registration
  // ═══════════════════════════════════════════════════════════════════════════

  describe("registration", async function () {
    it("registers a profile owner and reserves the fee", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);

      assert.equal(await wc.read.registeredPlayerAddresses([alice]), true);
      assert.equal(await wc.read.paidFee([alice]), REG_FEE);
      assert.equal(await wc.read.totalRefundable(), REG_FEE);
    });

    it("reverts when registration is closed", async function () {
      const { wc, profile } = await deploy();
      await profile.write.setRegistered([alice, true]);
      await assert.rejects(
        wc.write.registerBattle([REG_FEE], { account: aliceClient.account }),
        /Registration is closed/,
      );
    });

    it("reverts without a profile", async function () {
      const { wc } = await deploy();
      await openRegistration(wc);
      await assert.rejects(
        wc.write.registerBattle([REG_FEE], { account: aliceClient.account }),
        /Profile not registered/,
      );
    });

    it("enforces the maxFee slippage guard", async function () {
      const { wc, profile } = await deploy();
      await openRegistration(wc);
      await profile.write.setRegistered([alice, true]);
      await assert.rejects(
        wc.write.registerBattle([REG_FEE - 1n], { account: aliceClient.account }),
        /Fee exceeds maximum/,
      );
    });

    it("owner batch-add: skips zero/dup and charges no fee", async function () {
      const { wc } = await deploy();
      await openRegistration(wc);
      await wc.write.addRegisterPlayerAddresses([[bob, zeroAddress, bob]]);
      assert.equal(await wc.read.registeredPlayerAddresses([bob]), true);
      assert.equal(await wc.read.paidFee([bob]), 0n);
      assert.equal(await wc.read.totalRefundable(), 0n);
    });

    it("self-cancel refunds the fee", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await wc.write.cancelRegistration({ account: aliceClient.account });
      assert.equal(await wc.read.totalRefundable(), 0n);
      assert.equal(await hap.read.balanceOf([alice]), REG_FEE);
    });

    it("cannot self-cancel once seated", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await register(wc, hap, profile, bobClient);
      await wc.write.createBattle([alice, bob]);
      await assert.rejects(
        wc.write.cancelRegistration({ account: aliceClient.account }),
        /Already in a battle/,
      );
    });

    it("owner refunds unselected players after the deadline", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await advanceTimeTo(await futureTs(8n * 24n * 60n * 60n));
      await wc.write.refundUnselectedPlayers([[alice]]);
      assert.equal(await hap.read.balanceOf([alice]), REG_FEE);
      assert.equal(await wc.read.totalRefundable(), 0n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Battle lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  describe("battle lifecycle", async function () {
    it("creates a battle seating both players", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await register(wc, hap, profile, bobClient);
      await wc.write.createBattle([alice, bob]);

      assert.equal(await wc.read.getBattleCount(), 1n);
      assert.equal(await wc.read.playerBattleId([alice]), 1n);
      const b = await wc.read.getBattleInfo([1n]);
      assert.equal(b.player0Address.toLowerCase(), alice.toLowerCase());
      assert.equal(b.isEnded, false);
    });

    it("rejects unregistered / duplicate seats", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await assert.rejects(wc.write.createBattle([alice, bob]), /player1 not registered/);
      await assert.rejects(wc.write.createBattle([alice, alice]), /Players must differ/);
    });

    it("settles and releases both fees from the refund pool", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await register(wc, hap, profile, bobClient);
      await wc.write.createBattle([alice, bob]);
      assert.equal(await wc.read.totalRefundable(), 2n * REG_FEE);

      await wc.write.settleBattle([1n, alice]);
      const b = await wc.read.getBattleInfo([1n]);
      assert.equal(b.isEnded, true);
      assert.equal(b.winner.toLowerCase(), alice.toLowerCase());
      assert.equal(await wc.read.totalRefundable(), 0n);
      assert.equal(await wc.read.claimableFee(), 2n * REG_FEE);
    });

    it("settlement is liquidator-gated", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await register(wc, hap, profile, bobClient);
      await wc.write.createBattle([alice, bob]);
      await assert.rejects(
        wc.write.settleBattle([1n, alice], { account: strangerClient.account }),
      );
    });

    it("rejects an invalid winner", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await register(wc, hap, profile, bobClient);
      await wc.write.createBattle([alice, bob]);
      await assert.rejects(wc.write.settleBattle([1n, carol]), /Invalid winner address/);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Bonus
  // ═══════════════════════════════════════════════════════════════════════════

  describe("bonus payouts", async function () {
    it("pays an ERC20 bonus to the winner", async function () {
      const bonus = parseEther("50");
      const { wc, hap, bonusTok, profile, deployer } = await deploy();
      // redeploy WC configured with the bonus token
      await deployer.write.createWC([owner, bonusTok.address, bonus]);
      const wc2 = await viem.getContractAt(
        "HeroArenaWorldCupInitializable",
        await deployer.read.currentWCAddress(),
      );

      await bonusTok.write.mint([owner, bonus]);
      await bonusTok.write.approve([wc2.address, bonus]);
      await wc2.write.depositToken([bonusTok.address, bonus]);

      await openRegistration(wc2);
      await register(wc2, hap, profile, aliceClient);
      await register(wc2, hap, profile, bobClient);
      await wc2.write.createBattle([alice, bob]);
      await wc2.write.settleBattle([1n, alice]);

      assert.equal(await bonusTok.read.balanceOf([alice]), bonus);
    });

    it("skips the bonus when the pool is empty but still settles", async function () {
      const bonus = parseEther("50");
      const { hap, bonusTok, profile, deployer } = await deploy();
      await deployer.write.createWC([owner, bonusTok.address, bonus]);
      const wc = await viem.getContractAt(
        "HeroArenaWorldCupInitializable",
        await deployer.read.currentWCAddress(),
      );

      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await register(wc, hap, profile, bobClient);
      await wc.write.createBattle([alice, bob]);
      await wc.write.settleBattle([1n, alice]); // must not revert

      const b = await wc.read.getBattleInfo([1n]);
      assert.equal(b.isEnded, true);
      assert.equal(await bonusTok.read.balanceOf([alice]), 0n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Fees & rescue
  // ═══════════════════════════════════════════════════════════════════════════

  describe("fees & rescue", async function () {
    it("claimable fee is capped by the refund pool", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      assert.equal(await wc.read.claimableFee(), 0n);
      await assert.rejects(wc.write.claimFee([1n]), /Exceeds claimable fees/);
    });

    it("rescue cannot drain the reserved HAP refund pool", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await register(wc, hap, profile, aliceClient);
      await assert.rejects(
        wc.write.rescueExtraTokens([hap.address, owner, 1n]),
        /Amount exceeds rescuable balance/,
      );
    });

    it("rescue recovers a foreign token", async function () {
      const { wc, bonusTok } = await deploy();
      await bonusTok.write.mint([wc.address, parseEther("5")]);
      await wc.write.rescueExtraTokens([bonusTok.address, stranger, parseEther("5")]);
      assert.equal(await bonusTok.read.balanceOf([stranger]), parseEther("5"));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Ownership / role sync (M-1)
  // ═══════════════════════════════════════════════════════════════════════════

  describe("ownership/role sync (M-1)", async function () {
    it("transferOwnership moves DEFAULT_ADMIN_ROLE with the owner", async function () {
      const { wc } = await deploy();
      const adminRole = await wc.read.DEFAULT_ADMIN_ROLE();
      await wc.write.transferOwnership([bob]);
      assert.equal((await wc.read.owner()).toLowerCase(), bob.toLowerCase());
      assert.equal(await wc.read.hasRole([adminRole, bob]), true);
      assert.equal(await wc.read.hasRole([adminRole, owner]), false);
    });

    it("opting out of slippage with maxUint256 still registers", async function () {
      const { wc, hap, profile } = await deploy();
      await openRegistration(wc);
      await profile.write.setRegistered([alice, true]);
      await hap.write.mint([alice, REG_FEE]);
      await hap.write.approve([wc.address, REG_FEE], { account: aliceClient.account });
      await wc.write.registerBattle([maxUint256], { account: aliceClient.account });
      assert.equal(await wc.read.registeredPlayerAddresses([alice]), true);
    });
  });
});
