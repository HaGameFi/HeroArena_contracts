import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { parseEther, zeroAddress } from "viem";

// 1 ETH → 5000 HAP
const INITIAL_RATE = 5000n * 10n ** 18n;
const HAP_DEPOSIT  = 100_000n * 10n ** 18n;

describe("HeroArenaSwap", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner = ownerClient.account.address;
  const user1 = user1Client.account.address;
  const user2 = user2Client.account.address;

  // ─── deploy helper ───────────────────────────────────────────────────────────

  async function deployAll() {
    const hapToken = await viem.deployContract("MockERC20");
    const swap     = await viem.deployContract("HeroArenaSwap", [
      hapToken.address,
      INITIAL_RATE,
    ]);

    // Owner mints HAP and approves swap contract
    await hapToken.write.mint([owner, HAP_DEPOSIT]);
    await hapToken.write.approve([swap.address, 2n ** 256n - 1n]);

    return { hapToken, swap };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async () => {
    it("sets HapToken", async () => {
      const { hapToken, swap } = await deployAll();
      const stored = await swap.read.HapToken();
      assert.equal(stored.toLowerCase(), hapToken.address.toLowerCase());
    });

    it("sets rate", async () => {
      const { swap } = await deployAll();
      assert.equal(await swap.read.rate(), INITIAL_RATE);
    });

    it("enables swap by default", async () => {
      const { swap } = await deployAll();
      assert.equal(await swap.read.swapEnabled(), true);
    });

    it("sets owner", async () => {
      const { swap } = await deployAll();
      const stored = await swap.read.owner();
      assert.equal(stored.toLowerCase(), owner.toLowerCase());
    });

    it("reverts on zero address", async () => {
      await assert.rejects(
        viem.deployContract("HeroArenaSwap", [zeroAddress, INITIAL_RATE]),
        /Invalid HAP token address/
      );
    });

    it("reverts on zero rate", async () => {
      const hapToken = await viem.deployContract("MockERC20");
      await assert.rejects(
        viem.deployContract("HeroArenaSwap", [hapToken.address, 0n]),
        /Rate must be > 0/
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // setRate
  // ═══════════════════════════════════════════════════════════════════════════

  describe("setRate", async () => {
    it("updates rate", async () => {
      const { swap } = await deployAll();
      const newRate  = 10_000n * 10n ** 18n;
      await swap.write.setRate([newRate]);
      assert.equal(await swap.read.rate(), newRate);
    });

    it("emits RateUpdated event", async () => {
      const { swap } = await deployAll();
      const newRate  = 10_000n * 10n ** 18n;
      const hash     = await swap.write.setRate([newRate]);
      const receipt  = await publicClient.getTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    });

    it("reverts on zero rate", async () => {
      const { swap } = await deployAll();
      await assert.rejects(swap.write.setRate([0n]), /Rate must be > 0/);
    });

    it("reverts if not owner", async () => {
      const { swap } = await deployAll();
      await assert.rejects(
        swap.write.setRate([1000n], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // setSwapEnabled
  // ═══════════════════════════════════════════════════════════════════════════

  describe("setSwapEnabled", async () => {
    it("disables swap", async () => {
      const { swap } = await deployAll();
      await swap.write.setSwapEnabled([false]);
      assert.equal(await swap.read.swapEnabled(), false);
    });

    it("re-enables swap", async () => {
      const { swap } = await deployAll();
      await swap.write.setSwapEnabled([false]);
      await swap.write.setSwapEnabled([true]);
      assert.equal(await swap.read.swapEnabled(), true);
    });

    it("reverts if not owner", async () => {
      const { swap } = await deployAll();
      await assert.rejects(
        swap.write.setSwapEnabled([false], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // depositHap
  // ═══════════════════════════════════════════════════════════════════════════

  describe("depositHap", async () => {
    it("transfers HAP to contract", async () => {
      const { hapToken, swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      const balance = await hapToken.read.balanceOf([swap.address]);
      assert.equal(balance, HAP_DEPOSIT);
    });

    it("reverts on zero amount", async () => {
      const { swap } = await deployAll();
      await assert.rejects(swap.write.depositHap([0n]), /Amount must be > 0/);
    });

    it("reverts if not owner", async () => {
      const { swap } = await deployAll();
      await assert.rejects(
        swap.write.depositHap([HAP_DEPOSIT], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // withdrawHap
  // ═══════════════════════════════════════════════════════════════════════════

  describe("withdrawHap", async () => {
    it("transfers HAP back to owner", async () => {
      const { hapToken, swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      const before = await hapToken.read.balanceOf([owner]);
      await swap.write.withdrawHap([HAP_DEPOSIT]);
      const after = await hapToken.read.balanceOf([owner]);
      assert.equal(after - before, HAP_DEPOSIT);
    });

    it("reverts on zero amount", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await assert.rejects(swap.write.withdrawHap([0n]), /Amount must be > 0/);
    });

    it("reverts on insufficient balance", async () => {
      const { swap } = await deployAll();
      await assert.rejects(swap.write.withdrawHap([1n]), /Insufficient HAP balance/);
    });

    it("reverts if not owner", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await assert.rejects(
        swap.write.withdrawHap([HAP_DEPOSIT], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // withdrawNativeToken
  // ═══════════════════════════════════════════════════════════════════════════

  describe("withdrawNativeToken", async () => {
    it("transfers ETH to owner", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await swap.write.swap({ account: user1Client.account, value: parseEther("1") });

      const before = await publicClient.getBalance({ address: owner });
      const hash   = await swap.write.withdrawNativeToken([parseEther("1")]);
      const receipt = await publicClient.getTransactionReceipt({ hash });
      const gasUsed = receipt.gasUsed * receipt.effectiveGasPrice;
      const after  = await publicClient.getBalance({ address: owner });

      assert.equal(after - before + gasUsed, parseEther("1"));
    });

    it("reverts on zero amount", async () => {
      const { swap } = await deployAll();
      await assert.rejects(swap.write.withdrawNativeToken([0n]), /Amount must be > 0/);
    });

    it("reverts on insufficient ETH balance", async () => {
      const { swap } = await deployAll();
      await assert.rejects(
        swap.write.withdrawNativeToken([parseEther("1")]),
        /Insufficient ETH balance/
      );
    });

    it("reverts if not owner", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await swap.write.swap({ account: user1Client.account, value: parseEther("1") });
      await assert.rejects(
        swap.write.withdrawNativeToken([parseEther("1")], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // swap
  // ═══════════════════════════════════════════════════════════════════════════

  describe("swap", async () => {
    it("transfers correct HAP amount to user", async () => {
      const { hapToken, swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await swap.write.swap({ account: user1Client.account, value: parseEther("1") });

      const hapOut  = (parseEther("1") * INITIAL_RATE) / parseEther("1");
      const balance = await hapToken.read.balanceOf([user1]);
      assert.equal(balance, hapOut);
    });

    it("contract retains ETH", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await swap.write.swap({ account: user1Client.account, value: parseEther("2") });

      const ethBalance = await publicClient.getBalance({ address: swap.address });
      assert.equal(ethBalance, parseEther("2"));
    });

    it("reverts when swap is disabled", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await swap.write.setSwapEnabled([false]);
      await assert.rejects(
        swap.write.swap({ account: user1Client.account, value: parseEther("1") }),
        /Swap is disabled/
      );
    });

    it("reverts when no ETH sent", async () => {
      const { swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);
      await assert.rejects(
        swap.write.swap({ account: user1Client.account, value: 0n }),
        /Must send Native token/
      );
    });

    it("reverts when insufficient HAP in contract", async () => {
      const { swap } = await deployAll();
      await assert.rejects(
        swap.write.swap({ account: user1Client.account, value: parseEther("1") }),
        /Insufficient HAP in contract/
      );
    });

    it("multiple users can swap independently", async () => {
      const { hapToken, swap } = await deployAll();
      await swap.write.depositHap([HAP_DEPOSIT]);

      await swap.write.swap({ account: user1Client.account, value: parseEther("2") });
      await swap.write.swap({ account: user2Client.account, value: parseEther("3") });

      const hap1 = await hapToken.read.balanceOf([user1]);
      const hap2 = await hapToken.read.balanceOf([user2]);
      assert.equal(hap1, (parseEther("2") * INITIAL_RATE) / parseEther("1"));
      assert.equal(hap2, (parseEther("3") * INITIAL_RATE) / parseEther("1"));

      const ethBalance = await publicClient.getBalance({ address: swap.address });
      assert.equal(ethBalance, parseEther("5"));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // previewSwap
  // ═══════════════════════════════════════════════════════════════════════════

  describe("previewSwap", async () => {
    it("returns correct HAP amount", async () => {
      const { swap } = await deployAll();
      const hapOut   = await swap.read.previewSwap([parseEther("2")]);
      assert.equal(hapOut, (parseEther("2") * INITIAL_RATE) / parseEther("1"));
    });

    it("returns zero for zero input", async () => {
      const { swap } = await deployAll();
      assert.equal(await swap.read.previewSwap([0n]), 0n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // receive (plain ETH transfer)
  // ═══════════════════════════════════════════════════════════════════════════

  describe("receive", async () => {
    it("accepts plain ETH transfer", async () => {
      const { swap } = await deployAll();
      await ownerClient.sendTransaction({ to: swap.address, value: parseEther("1") });
      const balance = await publicClient.getBalance({ address: swap.address });
      assert.equal(balance, parseEther("1"));
    });
  });
});
