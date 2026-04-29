import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { getAddress, maxUint256, zeroAddress } from "viem";

const FEE_REGISTER = 100n * 10n ** 18n;
const FEE_UPDATE   =  50n * 10n ** 18n;

describe("HeroArenaProfile", async function () {
  const { viem } = await network.connect();
  const [ownerClient, user1Client, user2Client, pointRoleClient, specialRoleClient] =
    await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const owner       = ownerClient.account.address;
  const user1       = user1Client.account.address;
  const user2       = user2Client.account.address;
  const pointRole   = pointRoleClient.account.address;
  const specialRole = specialRoleClient.account.address;

  // ─── deploy helpers ───────────────────────────────────────────────────────

  async function deployAll() {
    const hapToken  = await viem.deployContract("MockERC20");
    const profile   = await viem.deployContract("HeroArenaProfile", [
      hapToken.address,
      FEE_REGISTER,
      FEE_UPDATE,
    ]);
    const avatarNFT = await viem.deployContract("MockERC721");
    const frameNFT  = await viem.deployContract("MockERC721");

    const POINT_ROLE   = await profile.read.POINT_ROLE();
    const SPECIAL_ROLE = await profile.read.SPECIAL_ROLE();
    const AVATAR_ROLE  = await profile.read.AVATAR_ROLE();
    const FRAME_ROLE   = await profile.read.FRAME_ROLE();

    await profile.write.grantRole([POINT_ROLE,   pointRole]);
    await profile.write.grantRole([SPECIAL_ROLE, specialRole]);

    await profile.write.addAvatarAddress([avatarNFT.address]);
    await profile.write.addFrameAddress([frameNFT.address]);

    await hapToken.write.mint([user1, 10_000n * 10n ** 18n]);
    await hapToken.write.mint([user2, 10_000n * 10n ** 18n]);
    await hapToken.write.approve([profile.address, maxUint256], { account: user1Client.account });
    await hapToken.write.approve([profile.address, maxUint256], { account: user2Client.account });

    await profile.write.addTeam(["TeamAlpha", "Alpha team"]);

    return { hapToken, profile, avatarNFT, frameNFT, POINT_ROLE, SPECIAL_ROLE, AVATAR_ROLE, FRAME_ROLE };
  }

  async function register(profile: any, userClient: any) {
    await profile.write.createProfile([1n], { account: userClient.account });
  }

  async function mintNFT(nftContract: any, profile: any, userClient: any): Promise<bigint> {
    await nftContract.write.setApprovalForAll([profile.address, true], {
      account: userClient.account,
    });
    const hash    = await nftContract.write.mint([userClient.account.address]);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const logs    = await publicClient.getContractEvents({
      address:   nftContract.address,
      abi:       nftContract.abi,
      eventName: "Transfer",
      fromBlock: receipt.blockNumber,
    });
    return logs[logs.length - 1].args.tokenId as bigint;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // addTeam
  // ═══════════════════════════════════════════════════════════════════════════

  describe("addTeam", async function () {
    it("increments numberOfTeams", async function () {
      const { profile } = await deployAll();
      assert.equal(await profile.read.numberOfTeams(), 1n);
    });

    it("emits TeamAdded", async function () {
      const { profile } = await deployAll();
      await viem.assertions.emitWithArgs(
        profile.write.addTeam(["TeamBeta", "Beta team"]),
        profile,
        "TeamAdded",
        [2n, "TeamBeta"],
      );
    });

    it("reverts if title too short", async function () {
      const { profile } = await deployAll();
      await assert.rejects(profile.write.addTeam(["Hi", "desc"]));
    });

    it("reverts if title too long (20 chars)", async function () {
      const { profile } = await deployAll();
      await assert.rejects(profile.write.addTeam(["TeamAlphaBetaGamma12", "desc"]));
    });

    it("reverts if not owner", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.write.addTeam(["TeamBeta", "desc"], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getTeam
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getTeam", async function () {
    it("returns correct team data", async function () {
      const { profile } = await deployAll();
      const [title, desc, , , joinable] = await profile.read.getTeam([1n]);
      assert.equal(title,    "TeamAlpha");
      assert.equal(desc,     "Alpha team");
      assert.equal(joinable, true);
    });

    it("reverts on zero id", async function () {
      const { profile } = await deployAll();
      await assert.rejects(profile.read.getTeam([0n]), /TeamId invalid/);
    });

    it("reverts on out-of-range id", async function () {
      const { profile } = await deployAll();
      await assert.rejects(profile.read.getTeam([99n]), /TeamId invalid/);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // renameTeam
  // ═══════════════════════════════════════════════════════════════════════════

  describe("renameTeam", async function () {
    it("updates team title and description", async function () {
      const { profile } = await deployAll();
      await profile.write.renameTeam([1n, "NewAlpha", "New desc"]);
      const [title, desc] = await profile.read.getTeam([1n]);
      assert.equal(title, "NewAlpha");
      assert.equal(desc,  "New desc");
    });

    it("emits TeamRenamed", async function () {
      const { profile } = await deployAll();
      await viem.assertions.emitWithArgs(
        profile.write.renameTeam([1n, "NewAlpha", "New desc"]),
        profile,
        "TeamRenamed",
        [1n, "NewAlpha"],
      );
    });

    it("reverts if not owner", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.write.renameTeam([1n, "NewAlpha", "desc"], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // makeTeamJoinable / makeTeamNotJoinable
  // ═══════════════════════════════════════════════════════════════════════════

  describe("joinability", async function () {
    it("makeTeamNotJoinable sets flag", async function () {
      const { profile } = await deployAll();
      await profile.write.makeTeamNotJoinable([1n]);
      const [, , , , joinable] = await profile.read.getTeam([1n]);
      assert.equal(joinable, false);
    });

    it("makeTeamJoinable restores flag", async function () {
      const { profile } = await deployAll();
      await profile.write.makeTeamNotJoinable([1n]);
      await profile.write.makeTeamJoinable([1n]);
      const [, , , , joinable] = await profile.read.getTeam([1n]);
      assert.equal(joinable, true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateFeeCost
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateFeeCost", async function () {
    it("updates both fees", async function () {
      const { profile } = await deployAll();
      await profile.write.updateFeeCost([200n * 10n ** 18n, 80n * 10n ** 18n]);
      assert.equal(await profile.read.feeToRegister(), 200n * 10n ** 18n);
      assert.equal(await profile.read.feeToUpdate(),   80n * 10n ** 18n);
    });

    it("emits UpdateFeeCost", async function () {
      const { profile } = await deployAll();
      await viem.assertions.emitWithArgs(
        profile.write.updateFeeCost([200n * 10n ** 18n, 80n * 10n ** 18n]),
        profile,
        "UpdateFeeCost",
        [getAddress(owner), 200n * 10n ** 18n, 80n * 10n ** 18n],
      );
    });

    it("reverts if not owner", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.write.updateFeeCost([1n, 1n], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // claimFee
  // ═══════════════════════════════════════════════════════════════════════════

  describe("claimFee", async function () {
    it("transfers HAP to owner", async function () {
      const { hapToken, profile } = await deployAll();
      await register(profile, user1Client);
      const balBefore = await hapToken.read.balanceOf([owner]);
      await profile.write.claimFee([FEE_REGISTER]);
      assert.equal(await hapToken.read.balanceOf([owner]), balBefore + FEE_REGISTER);
    });

    it("reverts if not owner", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.write.claimFee([1n], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // createProfile
  // ═══════════════════════════════════════════════════════════════════════════

  describe("createProfile", async function () {
    it("sets hasRegistered to true", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      assert.equal(await profile.read.hasRegistered([user1]), true);
    });

    it("emits UserNew", async function () {
      const { profile } = await deployAll();
      await viem.assertions.emitWithArgs(
        profile.write.createProfile([1n], { account: user1Client.account }),
        profile,
        "UserNew",
        [getAddress(user1), 1n],
      );
    });

    it("increments numberOfActiveProfiles", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      assert.equal(await profile.read.numberOfActiveProfiles(), 1n);
    });

    it("deducts HAP fee", async function () {
      const { hapToken, profile } = await deployAll();
      const balBefore = await hapToken.read.balanceOf([user1]);
      await register(profile, user1Client);
      assert.equal(await hapToken.read.balanceOf([user1]), balBefore - FEE_REGISTER);
    });

    it("assigns sequential user ids", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await register(profile, user2Client);
      const [id1] = await profile.read.getUserProfile([user1]);
      const [id2] = await profile.read.getUserProfile([user2]);
      assert.equal(id1, 1n);
      assert.equal(id2, 2n);
    });

    it("reverts if already registered", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await assert.rejects(
        profile.write.createProfile([1n], { account: user1Client.account }),
        /User is registered/,
      );
    });

    it("reverts on invalid team id", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.write.createProfile([99n], { account: user1Client.account }),
        /TeamId invalid/,
      );
    });

    it("reverts on non-joinable team", async function () {
      const { profile } = await deployAll();
      await profile.write.makeTeamNotJoinable([1n]);
      await assert.rejects(
        profile.write.createProfile([1n], { account: user1Client.account }),
        /not joinable/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAvatar
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateAvatar", async function () {
    it("sets avatar on first update", async function () {
      const { profile, avatarNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId = await mintNFT(avatarNFT, profile, user1Client);

      await profile.write.updateAvatar([avatarNFT.address, tokenId], {
        account: user1Client.account,
      });

      const [, , , avatar, tid] = await profile.read.getUserProfile([user1]);
      assert.equal(avatar, getAddress(avatarNFT.address));
      assert.equal(tid, tokenId);
      assert.equal(
        (await avatarNFT.read.ownerOf([tokenId])).toLowerCase(),
        profile.address.toLowerCase(),
      );
    });

    it("returns old NFT when replacing", async function () {
      const { profile, avatarNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId1 = await mintNFT(avatarNFT, profile, user1Client);
      const tokenId2 = await mintNFT(avatarNFT, profile, user1Client);

      await profile.write.updateAvatar([avatarNFT.address, tokenId1], { account: user1Client.account });
      await profile.write.updateAvatar([avatarNFT.address, tokenId2], { account: user1Client.account });

      assert.equal((await avatarNFT.read.ownerOf([tokenId1])).toLowerCase(), user1.toLowerCase());
      assert.equal(
        (await avatarNFT.read.ownerOf([tokenId2])).toLowerCase(),
        profile.address.toLowerCase(),
      );
    });

    it("emits UserAvatarUpdate", async function () {
      const { profile, avatarNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId = await mintNFT(avatarNFT, profile, user1Client);

      await viem.assertions.emitWithArgs(
        profile.write.updateAvatar([avatarNFT.address, tokenId], { account: user1Client.account }),
        profile,
        "UserAvatarUpdate",
        [getAddress(user1), getAddress(avatarNFT.address), tokenId],
      );
    });

    it("deducts HAP fee", async function () {
      const { hapToken, profile, avatarNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId  = await mintNFT(avatarNFT, profile, user1Client);
      const balBefore = await hapToken.read.balanceOf([user1]);

      await profile.write.updateAvatar([avatarNFT.address, tokenId], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), balBefore - FEE_UPDATE);
    });

    it("reverts if not registered", async function () {
      const { profile, avatarNFT } = await deployAll();
      const tokenId = await mintNFT(avatarNFT, profile, user1Client);
      await assert.rejects(
        profile.write.updateAvatar([avatarNFT.address, tokenId], { account: user1Client.account }),
        /User not registered/,
      );
    });

    it("reverts on invalid avatar address", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await assert.rejects(
        profile.write.updateAvatar(["0x000000000000000000000000000000000000dEaD", 1n], {
          account: user1Client.account,
        }),
        /Avatar address invalid/,
      );
    });

    it("reverts if not NFT owner", async function () {
      const { profile, avatarNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId = await mintNFT(avatarNFT, profile, user2Client);
      await assert.rejects(
        profile.write.updateAvatar([avatarNFT.address, tokenId], { account: user1Client.account }),
        /Only owner can transfer his\/her NFT/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateFrame
  // ═══════════════════════════════════════════════════════════════════════════

  describe("updateFrame", async function () {
    it("sets frame on first update", async function () {
      const { profile, frameNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId = await mintNFT(frameNFT, profile, user1Client);

      await profile.write.updateFrame([frameNFT.address, tokenId], { account: user1Client.account });

      assert.equal(
        (await frameNFT.read.ownerOf([tokenId])).toLowerCase(),
        profile.address.toLowerCase(),
      );
    });

    it("returns old frame NFT when replacing", async function () {
      const { profile, frameNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId1 = await mintNFT(frameNFT, profile, user1Client);
      const tokenId2 = await mintNFT(frameNFT, profile, user1Client);

      await profile.write.updateFrame([frameNFT.address, tokenId1], { account: user1Client.account });
      await profile.write.updateFrame([frameNFT.address, tokenId2], { account: user1Client.account });

      assert.equal((await frameNFT.read.ownerOf([tokenId1])).toLowerCase(), user1.toLowerCase());
      assert.equal(
        (await frameNFT.read.ownerOf([tokenId2])).toLowerCase(),
        profile.address.toLowerCase(),
      );
    });

    it("emits UserFrameUpdate", async function () {
      const { profile, frameNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId = await mintNFT(frameNFT, profile, user1Client);

      await viem.assertions.emitWithArgs(
        profile.write.updateFrame([frameNFT.address, tokenId], { account: user1Client.account }),
        profile,
        "UserFrameUpdate",
        [getAddress(user1), getAddress(frameNFT.address), tokenId],
      );
    });

    it("deducts HAP fee", async function () {
      const { hapToken, profile, frameNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId   = await mintNFT(frameNFT, profile, user1Client);
      const balBefore = await hapToken.read.balanceOf([user1]);

      await profile.write.updateFrame([frameNFT.address, tokenId], { account: user1Client.account });
      assert.equal(await hapToken.read.balanceOf([user1]), balBefore - FEE_UPDATE);
    });

    it("reverts if not registered", async function () {
      const { profile, frameNFT } = await deployAll();
      const tokenId = await mintNFT(frameNFT, profile, user1Client);
      await assert.rejects(
        profile.write.updateFrame([frameNFT.address, tokenId], { account: user1Client.account }),
        /User not registered/,
      );
    });

    it("reverts on invalid frame address", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await assert.rejects(
        profile.write.updateFrame(["0x000000000000000000000000000000000000dEaD", 1n], {
          account: user1Client.account,
        }),
        /Frame address invalid/,
      );
    });

    it("reverts if not NFT owner", async function () {
      const { profile, frameNFT } = await deployAll();
      await register(profile, user1Client);
      const tokenId = await mintNFT(frameNFT, profile, user2Client);
      await assert.rejects(
        profile.write.updateFrame([frameNFT.address, tokenId], { account: user1Client.account }),
        /Only owner can transfer his\/her NFT/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // addAvatarAddress
  // ═══════════════════════════════════════════════════════════════════════════

  describe("addAvatarAddress", async function () {
    it("grants AVATAR_ROLE", async function () {
      const { profile, AVATAR_ROLE } = await deployAll();
      const nft2 = await viem.deployContract("MockERC721");
      await profile.write.addAvatarAddress([nft2.address]);
      assert.equal(await profile.read.hasRole([AVATAR_ROLE, nft2.address]), true);
    });

    it("reverts on non-ERC721 address", async function () {
      const { profile } = await deployAll();
      const fake = await viem.deployContract("MockNonERC721");
      await assert.rejects(
        profile.write.addAvatarAddress([fake.address]),
        /Not ERC721/,
      );
    });

    it("reverts if not owner", async function () {
      const { profile } = await deployAll();
      const nft2 = await viem.deployContract("MockERC721");
      await assert.rejects(
        profile.write.addAvatarAddress([nft2.address], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // addFrameAddress
  // ═══════════════════════════════════════════════════════════════════════════

  describe("addFrameAddress", async function () {
    it("grants FRAME_ROLE", async function () {
      const { profile, FRAME_ROLE } = await deployAll();
      const nft2 = await viem.deployContract("MockERC721");
      await profile.write.addFrameAddress([nft2.address]);
      assert.equal(await profile.read.hasRole([FRAME_ROLE, nft2.address]), true);
    });

    it("reverts on non-ERC721 address", async function () {
      const { profile } = await deployAll();
      const fake = await viem.deployContract("MockNonERC721");
      await assert.rejects(
        profile.write.addFrameAddress([fake.address]),
        /Not ERC721/,
      );
    });

    it("reverts if not owner", async function () {
      const { profile } = await deployAll();
      const nft2 = await viem.deployContract("MockERC721");
      await assert.rejects(
        profile.write.addFrameAddress([nft2.address], { account: user1Client.account }),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // changeTeam
  // ═══════════════════════════════════════════════════════════════════════════

  describe("changeTeam", async function () {
    it("moves user to new team", async function () {
      const { profile } = await deployAll();
      await profile.write.addTeam(["TeamBeta", "Beta team"]);
      await register(profile, user1Client);

      await profile.write.changeTeam([user1, 2n], { account: specialRoleClient.account });

      const [, , teamId] = await profile.read.getUserProfile([user1]);
      assert.equal(teamId, 2n);
    });

    it("updates team user counts", async function () {
      const { profile } = await deployAll();
      await profile.write.addTeam(["TeamBeta", "Beta team"]);
      await register(profile, user1Client);

      await profile.write.changeTeam([user1, 2n], { account: specialRoleClient.account });

      const [, , t1Users] = await profile.read.getTeam([1n]);
      const [, , t2Users] = await profile.read.getTeam([2n]);
      assert.equal(t1Users, 0n);
      assert.equal(t2Users, 1n);
    });

    it("emits UserChangeTeam", async function () {
      const { profile } = await deployAll();
      await profile.write.addTeam(["TeamBeta", "Beta team"]);
      await register(profile, user1Client);

      await viem.assertions.emitWithArgs(
        profile.write.changeTeam([user1, 2n], { account: specialRoleClient.account }),
        profile,
        "UserChangeTeam",
        [getAddress(user1), 1n, 2n],
      );
    });

    it("reverts if user not registered", async function () {
      const { profile } = await deployAll();
      await profile.write.addTeam(["TeamBeta", "Beta team"]);
      await assert.rejects(
        profile.write.changeTeam([user1, 2n], { account: specialRoleClient.account }),
        /User not registered/,
      );
    });

    it("reverts if already in target team", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await assert.rejects(
        profile.write.changeTeam([user1, 1n], { account: specialRoleClient.account }),
        /already in the team/,
      );
    });

    it("reverts if not SPECIAL_ROLE", async function () {
      const { profile } = await deployAll();
      await profile.write.addTeam(["TeamBeta", "Beta team"]);
      await register(profile, user1Client);
      await assert.rejects(
        profile.write.changeTeam([user1, 2n], { account: user2Client.account }),
        /Not a special role/,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // points
  // ═══════════════════════════════════════════════════════════════════════════

  describe("points", async function () {
    it("increaseUserPoints adds points", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await profile.write.increaseUserPoints([user1, 500n, 1n], { account: pointRoleClient.account });
      const [, pts] = await profile.read.getUserProfile([user1]);
      assert.equal(pts, 500n);
    });

    it("increaseUserPoints reverts if not POINT_ROLE", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await assert.rejects(
        profile.write.increaseUserPoints([user1, 100n, 1n], { account: user2Client.account }),
        /Not a point role/,
      );
    });

    it("decreaseUserPoints subtracts points", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await profile.write.increaseUserPoints([user1, 500n, 1n], { account: pointRoleClient.account });
      await profile.write.decreaseUserPoints([user1, 200n], { account: pointRoleClient.account });
      const [, pts] = await profile.read.getUserProfile([user1]);
      assert.equal(pts, 300n);
    });

    it("increaseUserPointsBatch skips unregistered users", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      await profile.write.increaseUserPointsBatch([[user1, user2], 100n, 1n], {
        account: pointRoleClient.account,
      });
      const [, pts] = await profile.read.getUserProfile([user1]);
      assert.equal(pts, 100n);
    });

    it("increaseTeamPoints adds to team", async function () {
      const { profile } = await deployAll();
      await profile.write.increaseTeamPoints([1n, 1000n, 1n], { account: pointRoleClient.account });
      const [, , , teamPts] = await profile.read.getTeam([1n]);
      assert.equal(teamPts, 1000n);
    });

    it("increaseTeamPoints reverts on invalid teamId", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.write.increaseTeamPoints([99n, 100n, 1n], { account: pointRoleClient.account }),
        /TeamId invalid/,
      );
    });

    it("decreaseTeamPoints subtracts from team", async function () {
      const { profile } = await deployAll();
      await profile.write.increaseTeamPoints([1n, 1000n, 1n], { account: pointRoleClient.account });
      await profile.write.decreaseTeamPoints([1n, 400n], { account: pointRoleClient.account });
      const [, , , teamPts] = await profile.read.getTeam([1n]);
      assert.equal(teamPts, 600n);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getUserProfile
  // ═══════════════════════════════════════════════════════════════════════════

  describe("getUserProfile", async function () {
    it("returns correct initial profile data", async function () {
      const { profile } = await deployAll();
      await register(profile, user1Client);
      const [id, pts, teamId, avatar, tokenId] = await profile.read.getUserProfile([user1]);
      assert.equal(id,      1n);
      assert.equal(pts,     0n);
      assert.equal(teamId,  1n);
      assert.equal(avatar,  zeroAddress);
      assert.equal(tokenId, 0n);
    });

    it("reverts if not registered", async function () {
      const { profile } = await deployAll();
      await assert.rejects(
        profile.read.getUserProfile([user1]),
        /User not registered/,
      );
    });
  });
});
