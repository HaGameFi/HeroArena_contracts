import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, parseUnits, zeroAddress } from "viem";

const YEAR = 365n * 24n * 60n * 60n; // 365 days in seconds
const toHAP = (amount: bigint) => parseUnits(amount.toString(), 18);

describe("HapToken", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();
  const testClient = await viem.getTestClient();
  const [, poolClient, userClient] = await viem.getWalletClients();

  const pool = poolClient.account.address;
  const user = userClient.account.address;

  /**
   * Deploy HapToken, set mainPool, then advance time past the first 365-day
   * window so that the very first mint() call is always allowed.
   */
  async function deploy() {
    const token = await viem.deployContract("HapToken");
    await token.write.setMainPool([pool]);

    // Hardhat's initial timestamp is real-world time (~2026), which is already
    // well past 365 days since Unix epoch, so the first mint works immediately.
    // We still return a helper to advance one full year for subsequent mints.
    return token;
  }

  async function advanceOneYear() {
    const block = await publicClient.getBlock();
    await testClient.setNextBlockTimestamp({
      timestamp: block.timestamp + YEAR + 1n,
    });
    await testClient.mine({ blocks: 1 });
  }

  // ─────────────────────────────────────────────
  // maxMintOfYears
  // ─────────────────────────────────────────────

  describe("maxMintOfYears", async function () {
    it("should have correct yearly allocations", async function () {
      const token = await deploy();
      assert.equal(await token.read.maxMintOfYears([0n]), toHAP(400_000_000n));
      assert.equal(await token.read.maxMintOfYears([1n]), toHAP(225_000_000n));
      assert.equal(await token.read.maxMintOfYears([2n]), toHAP(175_000_000n));
      assert.equal(await token.read.maxMintOfYears([3n]), toHAP(125_000_000n));
      assert.equal(await token.read.maxMintOfYears([4n]), toHAP( 75_000_000n));
      assert.equal(await token.read.maxMintOfYears([5n]), 0n);
    });
  });

  // ─────────────────────────────────────────────
  // setMainPool
  // ─────────────────────────────────────────────

  describe("setMainPool", async function () {
    it("should set mainPool address correctly", async function () {
      const token = await viem.deployContract("HapToken");
      await token.write.setMainPool([pool]);
      assert.equal(await token.read.mainPool(), getAddress(pool));
    });

    it("should emit MainPoolUpdated event", async function () {
      const token = await viem.deployContract("HapToken");
      await viem.assertions.emitWithArgs(
        token.write.setMainPool([pool]),
        token,
        "MainPoolUpdated",
        [zeroAddress, getAddress(pool)],
      );
    });

    it("should revert when setting zero address", async function () {
      const token = await viem.deployContract("HapToken");
      await assert.rejects(token.write.setMainPool([zeroAddress]));
    });

    it("should revert when called by non-owner", async function () {
      const token = await viem.deployContract("HapToken");
      await assert.rejects(
        token.write.setMainPool([pool], { account: userClient.account }),
      );
    });
  });

  // ─────────────────────────────────────────────
  // nextMintingTime
  // ─────────────────────────────────────────────

  describe("nextMintingTime", async function () {
    it("should equal latestMintingTime + 365 days", async function () {
      const token = await deploy();
      const latest = await token.read.latestMintingTime();
      assert.equal(await token.read.nextMintingTime(), latest + YEAR);
    });

    it("should update after a successful mint", async function () {
      const token = await deploy();
      await token.write.mint([user], { account: poolClient.account });
      const latest = await token.read.latestMintingTime();
      assert.equal(await token.read.nextMintingTime(), latest + YEAR);
    });
  });

  // ─────────────────────────────────────────────
  // mint — access control & guards
  // ─────────────────────────────────────────────

  describe("mint — guards", async function () {
    it("should revert when caller is not mainPool", async function () {
      const token = await deploy();
      await assert.rejects(
        token.write.mint([user], { account: userClient.account }),
        /Invalid minter/,
      );
    });

    it("should revert when dest is zero address", async function () {
      const token = await deploy();
      await assert.rejects(
        token.write.mint([zeroAddress], { account: poolClient.account }),
        /Invalid dest/,
      );
    });

    it("should revert when called too early (within same year)", async function () {
      const token = await deploy();
      await token.write.mint([user], { account: poolClient.account });
      await assert.rejects(
        token.write.mint([user], { account: poolClient.account }),
        /Mining not allowed yet/,
      );
    });
  });

  // ─────────────────────────────────────────────
  // mint — year 0
  // ─────────────────────────────────────────────

  describe("mint — year 0", async function () {
    it("should mint 400M HAP on first call", async function () {
      const token = await deploy();
      await token.write.mint([user], { account: poolClient.account });
      assert.equal(await token.read.balanceOf([user]), toHAP(400_000_000n));
    });

    it("should emit YearlyMint with year=0", async function () {
      const token = await deploy();
      await viem.assertions.emitWithArgs(
        token.write.mint([user], { account: poolClient.account }),
        token,
        "YearlyMint",
        [0n, getAddress(user), toHAP(400_000_000n)],
      );
    });

    it("should increment yearMint to 1", async function () {
      const token = await deploy();
      await token.write.mint([user], { account: poolClient.account });
      assert.equal(await token.read.yearMint(), 1n);
    });

    it("should update latestMintingTime to current block timestamp", async function () {
      const token = await deploy();
      await token.write.mint([user], { account: poolClient.account });
      const block = await publicClient.getBlock();
      assert.equal(await token.read.latestMintingTime(), block.timestamp);
    });
  });

  // ─────────────────────────────────────────────
  // mint — burn logic
  // ─────────────────────────────────────────────

  describe("mint — burn unused tokens", async function () {
    it("should burn remaining pool balance before year 1 mint", async function () {
      const token = await deploy();

      // Year 0: mint to pool, then pool distributes half to user
      await token.write.mint([pool], { account: poolClient.account });
      await token.write.transfer([user, toHAP(200_000_000n)], {
        account: poolClient.account,
      });

      const remaining = await token.read.balanceOf([pool]); // 200M

      await advanceOneYear();

      await viem.assertions.emitWithArgs(
        token.write.mint([user], { account: poolClient.account }),
        token,
        "YearlyBurn",
        [0n, getAddress(pool), remaining],
      );

      assert.equal(await token.read.balanceOf([pool]), 0n);
    });

    it("should NOT emit YearlyBurn when pool balance is zero", async function () {
      const token = await deploy();

      // Year 0: mint directly to user (pool balance stays 0)
      await token.write.mint([user], { account: poolClient.account });
      await advanceOneYear();

      const deployBlock = await publicClient.getBlockNumber();

      await token.write.mint([user], { account: poolClient.account });

      const burnEvents = await publicClient.getContractEvents({
        address: token.address,
        abi: token.abi,
        eventName: "YearlyBurn",
        fromBlock: deployBlock,
      });

      assert.equal(burnEvents.length, 0);
    });
  });

  // ─────────────────────────────────────────────
  // mint — multi-year schedule
  // ─────────────────────────────────────────────

  describe("mint — yearly schedule", async function () {
    it("should mint correct amounts for years 0–4", async function () {
      const token = await deploy();
      const expected = [
        toHAP(400_000_000n),
        toHAP(225_000_000n),
        toHAP(175_000_000n),
        toHAP(125_000_000n),
        toHAP( 75_000_000n),
      ];

      for (let i = 0; i < 5; i++) {
        const balBefore = await token.read.balanceOf([user]);
        await token.write.mint([user], { account: poolClient.account });
        const balAfter = await token.read.balanceOf([user]);
        assert.equal(balAfter - balBefore, expected[i], `Year ${i} amount mismatch`);
        await advanceOneYear();
      }
    });

    it("should mint 0 tokens after year 5", async function () {
      const token = await deploy();
      for (let i = 0; i < 5; i++) {
        await token.write.mint([user], { account: poolClient.account });
        await advanceOneYear();
      }

      const balBefore = await token.read.balanceOf([user]);
      await token.write.mint([user], { account: poolClient.account });
      assert.equal(await token.read.balanceOf([user]), balBefore);
    });
  });

  // ─────────────────────────────────────────────
  // ERC20 basics
  // ─────────────────────────────────────────────

  describe("ERC20 metadata", async function () {
    it("should have name 'HeroArenaPlay Token'", async function () {
      const token = await deploy();
      assert.equal(await token.read.name(), "HeroArenaPlay Token");
    });

    it("should have symbol 'HAP'", async function () {
      const token = await deploy();
      assert.equal(await token.read.symbol(), "HAP");
    });

    it("should start with zero total supply", async function () {
      const token = await deploy();
      assert.equal(await token.read.totalSupply(), 0n);
    });
  });
});
