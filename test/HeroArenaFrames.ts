import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { zeroAddress } from "viem";

describe("HeroArenaFrames", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner = ownerClient.account.address;
  const user1 = user1Client.account.address;
  const user2 = user2Client.account.address;

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deploy() {
    const frames = await viem.deployContract("HeroArenaFrames");
    await frames.write.setFrameNameAndCreatedTimestamp([0, "frame0"]);
    await frames.write.setFrameNameAndCreatedTimestamp([1, "frame1"]);
    return { frames };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ERC721 metadata
  // ═══════════════════════════════════════════════════════════════════════════

  describe("ERC721 metadata", async function () {
    it("has correct name", async function () {
      const { frames } = await deploy();
      assert.equal(await frames.read.name(), "HA Frames");
    });

    it("has correct symbol", async function () {
      const { frames } = await deploy();
      assert.equal(await frames.read.symbol(), "HAF");
    });

    it("tokenURI returns baseURI + tokenId", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      assert.equal(await frames.read.tokenURI([1n]), "frames/1");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // constructor
  // ═══════════════════════════════════════════════════════════════════════════

  describe("constructor", async function () {
    it("sets deployer as owner", async function () {
      const { frames } = await deploy();
      assert.equal((await frames.read.owner()).toLowerCase(), owner.toLowerCase());
    });

    it("total supply starts at zero", async function () {
      const { frames } = await deploy();
      assert.equal(await frames.read.totalSupply(), 0n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // mint
  // ═══════════════════════════════════════════════════════════════════════════

  describe("mint", async function () {
    it("first token ID is 1", async function () {
      const { frames } = await deploy();
      const tokenId = await frames.write.mint([user1, 0]);
      assert.equal(await frames.read.totalSupply(), 1n);
    });

    it("mints sequential token IDs", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user1, 1]);
      assert.equal(await frames.read.totalSupply(), 2n);
    });

    it("sets token owner", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      assert.equal((await frames.read.ownerOf([1n])).toLowerCase(), user1.toLowerCase());
    });

    it("increments frameCount for the frameId", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user2, 0]);
      assert.equal(await frames.read.frameCount([0]), 2n);
    });

    it("counts different frameIds independently", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user1, 1]);
      assert.equal(await frames.read.frameCount([0]), 1n);
      assert.equal(await frames.read.frameCount([1]), 1n);
    });

    it("increments totalSupply", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user2, 1]);
      assert.equal(await frames.read.totalSupply(), 2n);
    });

    it("reverts if not owner", async function () {
      const { frames } = await deploy();
      await assert.rejects(
        frames.write.mint([user1, 0], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // setFrameNameAndCreatedTimestamp
  // ═══════════════════════════════════════════════════════════════════════════

  describe("setFrameNameAndCreatedTimestamp", async function () {
    it("sets frame name", async function () {
      const { frames } = await deploy();
      await frames.write.setFrameNameAndCreatedTimestamp([5, "frameSpecial"]);
      const [names] = await frames.read.getFrameNameAndCreatedTimestampBatch([[5]]);
      assert.equal(names[0], "frameSpecial");
    });

    it("can overwrite existing name", async function () {
      const { frames } = await deploy();
      await frames.write.setFrameNameAndCreatedTimestamp([0, "frame0_updated"]);
      const [names] = await frames.read.getFrameNameAndCreatedTimestampBatch([[0]]);
      assert.equal(names[0], "frame0_updated");
    });

    it("reverts if not owner", async function () {
      const { frames } = await deploy();
      await assert.rejects(
        frames.write.setFrameNameAndCreatedTimestamp([5, "x"], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // burn
  // ═══════════════════════════════════════════════════════════════════════════

  describe("burn", async function () {
    it("decrements frameCount", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user1, 0]);
      await frames.write.burn([2n]);
      assert.equal(await frames.read.frameCount([0]), 1n);
    });

    it("increments frameBurnCount", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.burn([1n]);
      assert.equal(await frames.read.frameBurnCount([0]), 1n);
    });

    it("decrements totalSupply", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user1, 0]);
      await frames.write.burn([2n]);
      assert.equal(await frames.read.totalSupply(), 1n);
    });

    it("token no longer exists after burn", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.burn([1n]);
      await assert.rejects(frames.read.ownerOf([1n]));
    });

    it("clears frameId mapping after burn", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 2]);
      await frames.write.burn([1n]);
      const result = await frames.read.getFrameIdBatch([[1n]]);
      assert.equal(result[0], 0);
    });

    it("reverts if not owner", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await assert.rejects(
        frames.write.burn([1n], { account: user1Client.account }),
        /OwnableUnauthorizedAccount/,
      );
    });

    it("reverts if token does not exist", async function () {
      const { frames } = await deploy();
      await assert.rejects(frames.write.burn([999n]));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getFrameIdBatch
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getFrameIdBatch", async function () {
    it("returns frameId for single token", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 2]);
      const result = await frames.read.getFrameIdBatch([[1n]]);
      assert.equal(result[0], 2);
    });

    it("returns frameIds for multiple tokens", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user2, 1]);
      const result = await frames.read.getFrameIdBatch([[1n, 2n]]);
      assert.equal(result[0], 0);
      assert.equal(result[1], 1);
    });

    it("returns empty array for empty input", async function () {
      const { frames } = await deploy();
      const result = await frames.read.getFrameIdBatch([[]]);
      assert.equal(result.length, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getFrameNameAndCreatedTimestampBatch
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getFrameNameAndCreatedTimestampBatch", async function () {
    it("returns correct names", async function () {
      const { frames } = await deploy();
      const [names] = await frames.read.getFrameNameAndCreatedTimestampBatch([[0, 1]]);
      assert.equal(names[0], "frame0");
      assert.equal(names[1], "frame1");
    });

    it("returns empty string for unset frameId", async function () {
      const { frames } = await deploy();
      const [names] = await frames.read.getFrameNameAndCreatedTimestampBatch([[99]]);
      assert.equal(names[0], "");
    });

    it("reverts if batch size exceeds 1000", async function () {
      const { frames } = await deploy();
      const ids = Array.from({ length: 1001 }, (_, i) => i % 256);
      await assert.rejects(
        frames.read.getFrameNameAndCreatedTimestampBatch([ids]),
        /Group size must be < 1001/,
      );
    });

    it("allows exactly 1000 items", async function () {
      const { frames } = await deploy();
      const ids = Array.from({ length: 1000 }, () => 0);
      await frames.read.getFrameNameAndCreatedTimestampBatch([ids]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getTokensByOwner
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getTokensByOwner", async function () {
    it("returns all token IDs for owner", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user1, 1]);
      await frames.write.mint([user2, 0]);
      const tokens = await frames.read.getTokensByOwner([user1]);
      assert.equal(tokens.length, 2);
    });

    it("returns empty array if owner has no tokens", async function () {
      const { frames } = await deploy();
      const tokens = await frames.read.getTokensByOwner([user1]);
      assert.equal(tokens.length, 0);
    });

    it("updates after burn", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.mint([user1, 1]);
      await frames.write.burn([1n]);
      const tokens = await frames.read.getTokensByOwner([user1]);
      assert.equal(tokens.length, 1);
    });

    it("updates after transfer", async function () {
      const { frames } = await deploy();
      await frames.write.mint([user1, 0]);
      await frames.write.transferFrom([user1, user2, 1n], { account: user1Client.account });
      assert.equal((await frames.read.getTokensByOwner([user1])).length, 0);
      assert.equal((await frames.read.getTokensByOwner([user2])).length, 1);
    });
  });
});
