import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress } from "viem";

describe("HeroArenaAvatars", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client] = await viem.getWalletClients();

  const user1 = user1Client.account.address;
  const user2 = user2Client.account.address;

  // ─── deploy helper ────────────────────────────────────────────────────────

  async function deploy() {
    const avatars = await viem.deployContract("HeroArenaAvatars");
    await avatars.write.setAvatarNameAndCreatedTimestamp([0, "Knight_v0"]);
    await avatars.write.setAvatarNameAndCreatedTimestamp([1, "Knight_v1"]);
    return { avatars };
  }

  async function getMintedTokenId(
    avatars: Awaited<ReturnType<typeof deploy>>["avatars"],
    hash: `0x${string}`,
  ): Promise<bigint> {
    const publicClient = await viem.getPublicClient();
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const logs = await publicClient.getContractEvents({
      address: avatars.address,
      abi: avatars.abi,
      eventName: "Transfer",
      fromBlock: receipt.blockNumber,
      toBlock: receipt.blockNumber,
    });
    return logs[logs.length - 1].args.tokenId as bigint;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // metadata
  // ═══════════════════════════════════════════════════════════════════════════

  describe("metadata", async function () {
    it("name is HA Avatars", async function () {
      const { avatars } = await deploy();
      assert.equal(await avatars.read.name(), "HA Avatars");
    });

    it("symbol is HAA", async function () {
      const { avatars } = await deploy();
      assert.equal(await avatars.read.symbol(), "HAA");
    });

    it("tokenURI returns avatars/{tokenId}", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      assert.equal(await avatars.read.tokenURI([tokenId]), `avatars/${tokenId}`);
    });

    it("tokenURI increments with each mint", async function () {
      const { avatars } = await deploy();
      const hash1 = await avatars.write.mint([user1, 0]);
      const hash2 = await avatars.write.mint([user1, 1]);
      const tokenId1 = await getMintedTokenId(avatars, hash1);
      const tokenId2 = await getMintedTokenId(avatars, hash2);
      assert.equal(await avatars.read.tokenURI([tokenId1]), "avatars/1");
      assert.equal(await avatars.read.tokenURI([tokenId2]), "avatars/2");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // supportsInterface
  // ═══════════════════════════════════════════════════════════════════════════

  describe("supportsInterface", async function () {
    it("supports ERC721 interface (0x80ac58cd)", async function () {
      const { avatars } = await deploy();
      assert.equal(await avatars.read.supportsInterface(["0x80ac58cd"]), true);
    });

    it("supports ERC721Enumerable interface (0x780e9d63)", async function () {
      const { avatars } = await deploy();
      assert.equal(await avatars.read.supportsInterface(["0x780e9d63"]), true);
    });

    it("supports ERC165 interface (0x01ffc9a7)", async function () {
      const { avatars } = await deploy();
      assert.equal(await avatars.read.supportsInterface(["0x01ffc9a7"]), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // mint
  // ═══════════════════════════════════════════════════════════════════════════

  describe("mint", async function () {
    it("tokenId starts at 1", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      assert.equal(tokenId, 1n);
    });

    it("tokenIds are sequential", async function () {
      const { avatars } = await deploy();
      const hash1 = await avatars.write.mint([user1, 0]);
      const hash2 = await avatars.write.mint([user1, 1]);
      const tokenId1 = await getMintedTokenId(avatars, hash1);
      const tokenId2 = await getMintedTokenId(avatars, hash2);
      assert.equal(tokenId1, 1n);
      assert.equal(tokenId2, 2n);
    });

    it("sets NFT owner to recipient", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      assert.equal(await avatars.read.ownerOf([tokenId]), getAddress(user1));
    });

    it("increments avatarCount", async function () {
      const { avatars } = await deploy();
      await avatars.write.mint([user1, 0]);
      await avatars.write.mint([user2, 0]);
      assert.equal(await avatars.read.avatarCount([0]), 2n);
    });

    it("increments totalSupply", async function () {
      const { avatars } = await deploy();
      await avatars.write.mint([user1, 0]);
      await avatars.write.mint([user2, 1]);
      assert.equal(await avatars.read.totalSupply(), 2n);
    });

    it("reverts if not owner", async function () {
      const { avatars } = await deploy();
      await assert.rejects(
        avatars.write.mint([user1, 0], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // setAvatarNameAndCreatedTimestamp
  // ═══════════════════════════════════════════════════════════════════════════

  describe("setAvatarNameAndCreatedTimestamp", async function () {
    it("sets avatar name", async function () {
      const { avatars } = await deploy();
      await avatars.write.setAvatarNameAndCreatedTimestamp([5, "Wizard_v1"]);
      const [names] = await avatars.read.getAvatarNameAndCreatedTimestampsBatch([[5]]);
      assert.equal(names[0], "Wizard_v1");
    });

    it("sets timestamp to block.timestamp", async function () {
      const { avatars } = await deploy();
      const publicClient = await viem.getPublicClient();
      const hash = await avatars.write.setAvatarNameAndCreatedTimestamp([5, "Wizard_v1"]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const block = await publicClient.getBlock({ blockNumber: receipt.blockNumber });
      const [, timestamps] = await avatars.read.getAvatarNameAndCreatedTimestampsBatch([[5]]);
      assert.equal(timestamps[0], block.timestamp);
    });

    it("can overwrite an existing name", async function () {
      const { avatars } = await deploy();
      await avatars.write.setAvatarNameAndCreatedTimestamp([0, "Knight_v0_updated"]);
      const [names] = await avatars.read.getAvatarNameAndCreatedTimestampsBatch([[0]]);
      assert.equal(names[0], "Knight_v0_updated");
    });

    it("reverts if not owner", async function () {
      const { avatars } = await deploy();
      await assert.rejects(
        avatars.write.setAvatarNameAndCreatedTimestamp([5, "Wizard_v1"], {
          account: user1Client.account,
        }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // burn
  // ═══════════════════════════════════════════════════════════════════════════

  describe("burn", async function () {
    it("decrements avatarCount", async function () {
      const { avatars } = await deploy();
      await avatars.write.mint([user1, 0]);
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      await avatars.write.burn([tokenId]);
      assert.equal(await avatars.read.avatarCount([0]), 1n);
    });

    it("increments avatarBurnCount", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      await avatars.write.burn([tokenId]);
      assert.equal(await avatars.read.avatarBurnCount([0]), 1n);
    });

    it("decrements totalSupply", async function () {
      const { avatars } = await deploy();
      await avatars.write.mint([user1, 0]);
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      await avatars.write.burn([tokenId]);
      assert.equal(await avatars.read.totalSupply(), 1n);
    });

    it("token no longer exists after burn", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      await avatars.write.burn([tokenId]);
      await assert.rejects(avatars.read.ownerOf([tokenId]));
    });

    it("reverts if not owner", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      await assert.rejects(
        avatars.write.burn([tokenId], { account: user1Client.account }),
      );
    });

    it("reverts if token does not exist", async function () {
      const { avatars } = await deploy();
      await assert.rejects(avatars.write.burn([999n]));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getAvatarNameAndCreatedTimestampsBatch
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getAvatarNameAndCreatedTimestampsBatch", async function () {
    it("returns correct names", async function () {
      const { avatars } = await deploy();
      const [names] = await avatars.read.getAvatarNameAndCreatedTimestampsBatch([[0, 1]]);
      assert.equal(names[0], "Knight_v0");
      assert.equal(names[1], "Knight_v1");
    });

    it("returns empty string for unset avatarId", async function () {
      const { avatars } = await deploy();
      const [names] = await avatars.read.getAvatarNameAndCreatedTimestampsBatch([[99]]);
      assert.equal(names[0], "");
    });

    it("reverts if array length exceeds 1000", async function () {
      const { avatars } = await deploy();
      const ids = Array.from({ length: 1001 }, (_, i) => i % 256);
      await assert.rejects(
        avatars.read.getAvatarNameAndCreatedTimestampsBatch([ids as number[]]),
        /Group size must be < 1001/,
      );
    });

    it("allows exactly 1000 elements", async function () {
      const { avatars } = await deploy();
      const ids = Array.from({ length: 1000 }, () => 0);
      const [names] = await avatars.read.getAvatarNameAndCreatedTimestampsBatch([ids as number[]]);
      assert.equal(names.length, 1000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getTokensByOwner
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getTokensByOwner", async function () {
    it("returns all tokenIds for owner", async function () {
      const { avatars } = await deploy();
      await avatars.write.mint([user1, 0]);
      await avatars.write.mint([user1, 1]);
      await avatars.write.mint([user2, 0]);

      const tokens = await avatars.read.getTokensByOwner([user1]);
      assert.equal(tokens.length, 2);
      assert.equal(tokens[0], 1n);
      assert.equal(tokens[1], 2n);
    });

    it("returns empty array for address with no tokens", async function () {
      const { avatars } = await deploy();
      const tokens = await avatars.read.getTokensByOwner([user1]);
      assert.equal(tokens.length, 0);
    });

    it("updates after burn", async function () {
      const { avatars } = await deploy();
      const hash1 = await avatars.write.mint([user1, 0]);
      await avatars.write.mint([user1, 1]);
      const tokenId1 = await getMintedTokenId(avatars, hash1);
      await avatars.write.burn([tokenId1]);

      const tokens = await avatars.read.getTokensByOwner([user1]);
      assert.equal(tokens.length, 1);
      assert.equal(tokens[0], 2n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ERC721Enumerable
  // ═══════════════════════════════════════════════════════════════════════════

  describe("ERC721Enumerable", async function () {
    it("totalSupply is 0 initially", async function () {
      const { avatars } = await deploy();
      assert.equal(await avatars.read.totalSupply(), 0n);
    });

    it("tokenByIndex returns correct token", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      assert.equal(await avatars.read.tokenByIndex([0n]), tokenId);
    });

    it("tokenOfOwnerByIndex returns correct token", async function () {
      const { avatars } = await deploy();
      const hash = await avatars.write.mint([user1, 0]);
      const tokenId = await getMintedTokenId(avatars, hash);
      assert.equal(await avatars.read.tokenOfOwnerByIndex([user1, 0n]), tokenId);
    });
  });
});
