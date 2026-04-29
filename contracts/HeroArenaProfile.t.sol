// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaProfile} from "./HeroArenaProfile.sol";
import {MockERC20}         from "./mocks/MockERC20.sol";
import {MockERC721}        from "./mocks/MockERC721.sol";
import {MockNonERC721}     from "./mocks/MockNonERC721.sol";

contract HeroArenaProfileTest is Test {
    HeroArenaProfile profile;
    MockERC20        hapToken;
    MockERC721       avatarNFT;
    MockERC721       frameNFT;

    address owner;
    address pointRole;
    address specialRole;
    address user1;
    address user2;

    uint256 constant FEE_REGISTER = 100 * 10 ** 18;
    uint256 constant FEE_UPDATE   =  50 * 10 ** 18;

    // ─── setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        owner       = address(this);
        pointRole   = makeAddr("pointRole");
        specialRole = makeAddr("specialRole");
        user1       = makeAddr("user1");
        user2       = makeAddr("user2");

        hapToken  = new MockERC20();
        profile   = new HeroArenaProfile(IERC20(address(hapToken)), FEE_REGISTER, FEE_UPDATE);
        avatarNFT = new MockERC721();
        frameNFT  = new MockERC721();

        // Grant roles
        profile.grantRole(profile.POINT_ROLE(),   pointRole);
        profile.grantRole(profile.SPECIAL_ROLE(), specialRole);

        // Register NFT contracts
        profile.addAvatarAddress(address(avatarNFT));
        profile.addFrameAddress(address(frameNFT));

        // Fund users with HAP and max-approve profile
        hapToken.mint(user1, 10_000 * 10 ** 18);
        hapToken.mint(user2, 10_000 * 10 ** 18);
        vm.prank(user1); hapToken.approve(address(profile), type(uint256).max);
        vm.prank(user2); hapToken.approve(address(profile), type(uint256).max);

        // Create default team (teamId = 1)
        profile.addTeam("TeamAlpha", "Alpha team");
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _register(address user) internal {
        vm.prank(user);
        profile.createProfile(1);
    }

    function _mintAvatar(address user) internal returns (uint256 tokenId) {
        tokenId = avatarNFT.mint(user);
        vm.prank(user);
        avatarNFT.setApprovalForAll(address(profile), true);
    }

    function _mintFrame(address user) internal returns (uint256 tokenId) {
        tokenId = frameNFT.mint(user);
        vm.prank(user);
        frameNFT.setApprovalForAll(address(profile), true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // addTeam
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddTeam_IncrementsNumberOfTeams() public view {
        assertEq(profile.numberOfTeams(), 1);
    }

    function test_AddTeam_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.TeamAdded(2, "TeamBeta");
        profile.addTeam("TeamBeta", "Beta team");
    }

    function test_AddTeam_ReturnsCorrectData() public {
        profile.addTeam("TeamBeta", "Beta team");
        (string memory title, string memory desc,,,) = profile.getTeam(2);
        assertEq(title, "TeamBeta");
        assertEq(desc,  "Beta team");
    }

    function test_AddTeam_RevertsIfTitleTooShort() public {
        vm.expectRevert();
        profile.addTeam("Hi", "desc");
    }

    function test_AddTeam_RevertsIfTitleTooLong() public {
        vm.expectRevert();
        profile.addTeam("TeamAlphaBetaGamma12", "desc");
    }

    function test_AddTeam_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        profile.addTeam("TeamBeta", "desc");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getTeam
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetTeam_ReturnsIsJoinableTrue() public view {
        (,,,, bool joinable) = profile.getTeam(1);
        assertTrue(joinable);
    }

    function test_GetTeam_RevertsOnZeroId() public {
        vm.expectRevert("TeamId invalid");
        profile.getTeam(0);
    }

    function test_GetTeam_RevertsOnOutOfRangeId() public {
        vm.expectRevert("TeamId invalid");
        profile.getTeam(99);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // renameTeam
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RenameTeam_UpdatesTitle() public {
        profile.renameTeam(1, "NewAlpha", "New desc");
        (string memory title,,,,) = profile.getTeam(1);
        assertEq(title, "NewAlpha");
    }

    function test_RenameTeam_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.TeamRenamed(1, "NewAlpha");
        profile.renameTeam(1, "NewAlpha", "New desc");
    }

    function test_RenameTeam_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        profile.renameTeam(1, "NewAlpha", "desc");
    }

    function test_RenameTeam_RevertsOnInvalidId() public {
        vm.expectRevert("TeamId invalid");
        profile.renameTeam(99, "NewAlpha", "desc");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // makeTeamJoinable / makeTeamNotJoinable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MakeTeamNotJoinable_SetsFlag() public {
        profile.makeTeamNotJoinable(1);
        (,,,, bool joinable) = profile.getTeam(1);
        assertFalse(joinable);
    }

    function test_MakeTeamJoinable_SetsFlag() public {
        profile.makeTeamNotJoinable(1);
        profile.makeTeamJoinable(1);
        (,,,, bool joinable) = profile.getTeam(1);
        assertTrue(joinable);
    }

    function test_MakeTeamNotJoinable_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        profile.makeTeamNotJoinable(1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateFeeCost
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateFeeCost_UpdatesValues() public {
        profile.updateFeeCost(200 * 10 ** 18, 80 * 10 ** 18);
        assertEq(profile.feeToRegister(), 200 * 10 ** 18);
        assertEq(profile.feeToUpdate(),   80 * 10 ** 18);
    }

    function test_UpdateFeeCost_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.UpdateFeeCost(owner, 200 * 10 ** 18, 80 * 10 ** 18);
        profile.updateFeeCost(200 * 10 ** 18, 80 * 10 ** 18);
    }

    function test_UpdateFeeCost_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        profile.updateFeeCost(1, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // claimFee
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ClaimFee_TransfersHAP() public {
        _register(user1);
        uint256 balBefore = hapToken.balanceOf(owner);
        profile.claimFee(FEE_REGISTER);
        assertEq(hapToken.balanceOf(owner), balBefore + FEE_REGISTER);
    }

    function test_ClaimFee_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        profile.claimFee(1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // createProfile
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CreateProfile_SetsRegistered() public {
        _register(user1);
        assertTrue(profile.hasRegistered(user1));
    }

    function test_CreateProfile_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.UserNew(user1, 1);
        vm.prank(user1);
        profile.createProfile(1);
    }

    function test_CreateProfile_IncrementsActiveProfiles() public {
        _register(user1);
        assertEq(profile.numberOfActiveProfiles(), 1);
    }

    function test_CreateProfile_IncrementsTeamUserCount() public {
        _register(user1);
        (,, uint256 numUsers,,) = profile.getTeam(1);
        assertEq(numUsers, 1);
    }

    function test_CreateProfile_DeductsHAPFee() public {
        uint256 balBefore = hapToken.balanceOf(user1);
        _register(user1);
        assertEq(hapToken.balanceOf(user1), balBefore - FEE_REGISTER);
    }

    function test_CreateProfile_AssignsUserId() public {
        _register(user1);
        _register(user2);
        (uint256 id1,,,,) = profile.getUserProfile(user1);
        (uint256 id2,,,,) = profile.getUserProfile(user2);
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_CreateProfile_RevertsIfAlreadyRegistered() public {
        _register(user1);
        vm.prank(user1);
        vm.expectRevert("User is registered");
        profile.createProfile(1);
    }

    function test_CreateProfile_RevertsOnInvalidTeamId() public {
        vm.prank(user1);
        vm.expectRevert("TeamId invalid");
        profile.createProfile(99);
    }

    function test_CreateProfile_RevertsOnNonJoinableTeam() public {
        profile.makeTeamNotJoinable(1);
        vm.prank(user1);
        vm.expectRevert("The team currently is not joinable");
        profile.createProfile(1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAvatar
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAvatar_FirstTime_SetsAvatar() public {
        _register(user1);
        uint256 tokenId = _mintAvatar(user1);

        vm.prank(user1);
        profile.updateAvatar(address(avatarNFT), tokenId);

        (,,, address avatar, uint256 tid) = profile.getUserProfile(user1);
        assertEq(avatar,  address(avatarNFT));
        assertEq(tid,     tokenId);
        assertEq(avatarNFT.ownerOf(tokenId), address(profile));
    }

    function test_UpdateAvatar_ReplacesNFT_ReturnsOld() public {
        _register(user1);
        uint256 tokenId1 = _mintAvatar(user1);
        uint256 tokenId2 = _mintAvatar(user1);

        vm.prank(user1);
        profile.updateAvatar(address(avatarNFT), tokenId1);
        vm.prank(user1);
        profile.updateAvatar(address(avatarNFT), tokenId2);

        assertEq(avatarNFT.ownerOf(tokenId1), user1);
        assertEq(avatarNFT.ownerOf(tokenId2), address(profile));
    }

    function test_UpdateAvatar_EmitsEvent() public {
        _register(user1);
        uint256 tokenId = _mintAvatar(user1);

        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.UserAvatarUpdate(user1, address(avatarNFT), tokenId);
        vm.prank(user1);
        profile.updateAvatar(address(avatarNFT), tokenId);
    }

    function test_UpdateAvatar_DeductsHAPFee() public {
        _register(user1);
        uint256 tokenId = _mintAvatar(user1);

        uint256 balBefore = hapToken.balanceOf(user1);
        vm.prank(user1);
        profile.updateAvatar(address(avatarNFT), tokenId);
        assertEq(hapToken.balanceOf(user1), balBefore - FEE_UPDATE);
    }

    function test_UpdateAvatar_RevertsIfNotRegistered() public {
        uint256 tokenId = _mintAvatar(user1);
        vm.prank(user1);
        vm.expectRevert("User not registered");
        profile.updateAvatar(address(avatarNFT), tokenId);
    }

    function test_UpdateAvatar_RevertsOnInvalidAvatarAddress() public {
        _register(user1);
        vm.prank(user1);
        vm.expectRevert("Avatar address invalid");
        profile.updateAvatar(address(0xdead), 1);
    }

    function test_UpdateAvatar_RevertsIfNotNFTOwner() public {
        _register(user1);
        uint256 tokenId = avatarNFT.mint(user2);
        vm.prank(user1);
        vm.expectRevert("Only owner can transfer his/her NFT");
        profile.updateAvatar(address(avatarNFT), tokenId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // addAvatarAddress
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddAvatarAddress_GrantsRole() public {
        MockERC721 nft2 = new MockERC721();
        profile.addAvatarAddress(address(nft2));
        assertTrue(profile.hasRole(profile.AVATAR_ROLE(), address(nft2)));
    }

    function test_AddAvatarAddress_RevertsOnNonERC721() public {
        MockNonERC721 fake = new MockNonERC721();
        vm.expectRevert("Not ERC721");
        profile.addAvatarAddress(address(fake));
    }

    function test_AddAvatarAddress_RevertsIfNotOwner() public {
        MockERC721 nft2 = new MockERC721();
        vm.prank(user1);
        vm.expectRevert();
        profile.addAvatarAddress(address(nft2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateFrame
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateFrame_FirstTime_SetsFrame() public {
        _register(user1);
        uint256 tokenId = _mintFrame(user1);

        vm.prank(user1);
        profile.updateFrame(address(frameNFT), tokenId);

        assertEq(frameNFT.ownerOf(tokenId), address(profile));
    }

    function test_UpdateFrame_ReplacesNFT_ReturnsOld() public {
        _register(user1);
        uint256 tokenId1 = _mintFrame(user1);
        uint256 tokenId2 = _mintFrame(user1);

        vm.prank(user1);
        profile.updateFrame(address(frameNFT), tokenId1);
        vm.prank(user1);
        profile.updateFrame(address(frameNFT), tokenId2);

        assertEq(frameNFT.ownerOf(tokenId1), user1);
        assertEq(frameNFT.ownerOf(tokenId2), address(profile));
    }

    function test_UpdateFrame_EmitsEvent() public {
        _register(user1);
        uint256 tokenId = _mintFrame(user1);

        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.UserFrameUpdate(user1, address(frameNFT), tokenId);
        vm.prank(user1);
        profile.updateFrame(address(frameNFT), tokenId);
    }

    function test_UpdateFrame_DeductsHAPFee() public {
        _register(user1);
        uint256 tokenId = _mintFrame(user1);

        uint256 balBefore = hapToken.balanceOf(user1);
        vm.prank(user1);
        profile.updateFrame(address(frameNFT), tokenId);
        assertEq(hapToken.balanceOf(user1), balBefore - FEE_UPDATE);
    }

    function test_UpdateFrame_RevertsIfNotRegistered() public {
        uint256 tokenId = _mintFrame(user1);
        vm.prank(user1);
        vm.expectRevert("User not registered");
        profile.updateFrame(address(frameNFT), tokenId);
    }

    function test_UpdateFrame_RevertsOnInvalidFrameAddress() public {
        _register(user1);
        vm.prank(user1);
        vm.expectRevert("Frame address invalid");
        profile.updateFrame(address(0xdead), 1);
    }

    function test_UpdateFrame_RevertsIfNotNFTOwner() public {
        _register(user1);
        uint256 tokenId = frameNFT.mint(user2);
        vm.prank(user1);
        vm.expectRevert("Only owner can transfer his/her NFT");
        profile.updateFrame(address(frameNFT), tokenId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // addFrameAddress
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AddFrameAddress_GrantsRole() public {
        MockERC721 nft2 = new MockERC721();
        profile.addFrameAddress(address(nft2));
        assertTrue(profile.hasRole(profile.FRAME_ROLE(), address(nft2)));
    }

    function test_AddFrameAddress_RevertsOnNonERC721() public {
        MockNonERC721 fake = new MockNonERC721();
        vm.expectRevert("Not ERC721");
        profile.addFrameAddress(address(fake));
    }

    function test_AddFrameAddress_RevertsIfNotOwner() public {
        MockERC721 nft2 = new MockERC721();
        vm.prank(user1);
        vm.expectRevert();
        profile.addFrameAddress(address(nft2));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // changeTeam
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ChangeTeam_UpdatesUserTeam() public {
        profile.addTeam("TeamBeta", "Beta team");
        _register(user1);

        vm.prank(specialRole);
        profile.changeTeam(user1, 2);

        (,, uint256 teamId,,) = profile.getUserProfile(user1);
        assertEq(teamId, 2);
    }

    function test_ChangeTeam_UpdatesTeamCounters() public {
        profile.addTeam("TeamBeta", "Beta team");
        _register(user1);

        vm.prank(specialRole);
        profile.changeTeam(user1, 2);

        (,, uint256 team1Users,,) = profile.getTeam(1);
        (,, uint256 team2Users,,) = profile.getTeam(2);
        assertEq(team1Users, 0);
        assertEq(team2Users, 1);
    }

    function test_ChangeTeam_EmitsEvent() public {
        profile.addTeam("TeamBeta", "Beta team");
        _register(user1);

        vm.expectEmit(true, false, false, true);
        emit HeroArenaProfile.UserChangeTeam(user1, 1, 2);
        vm.prank(specialRole);
        profile.changeTeam(user1, 2);
    }

    function test_ChangeTeam_RevertsIfNotRegistered() public {
        profile.addTeam("TeamBeta", "Beta team");
        vm.prank(specialRole);
        vm.expectRevert("User not registered");
        profile.changeTeam(user1, 2);
    }

    function test_ChangeTeam_RevertsIfAlreadyInTeam() public {
        _register(user1);
        vm.prank(specialRole);
        vm.expectRevert("User is already in the team");
        profile.changeTeam(user1, 1);
    }

    function test_ChangeTeam_RevertsOnNonJoinableTeam() public {
        profile.addTeam("TeamBeta", "Beta team");
        profile.makeTeamNotJoinable(2);
        _register(user1);

        vm.prank(specialRole);
        vm.expectRevert("The team currently is not joinable");
        profile.changeTeam(user1, 2);
    }

    function test_ChangeTeam_RevertsIfNotSpecialRole() public {
        profile.addTeam("TeamBeta", "Beta team");
        _register(user1);

        vm.prank(user2);
        vm.expectRevert("Not a special role");
        profile.changeTeam(user1, 2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // points
    // ═══════════════════════════════════════════════════════════════════════════

    function test_IncreaseUserPoints_AddsPoints() public {
        _register(user1);
        vm.prank(pointRole);
        profile.increaseUserPoints(user1, 500, 1);

        (, uint256 pts,,,) = profile.getUserProfile(user1);
        assertEq(pts, 500);
    }

    function test_IncreaseUserPoints_EmitsEvent() public {
        _register(user1);
        vm.expectEmit(true, false, true, true);
        emit HeroArenaProfile.UserPointIncrease(user1, 500, 1);
        vm.prank(pointRole);
        profile.increaseUserPoints(user1, 500, 1);
    }

    function test_IncreaseUserPoints_RevertsIfNotRegistered() public {
        vm.prank(pointRole);
        vm.expectRevert("User not registered");
        profile.increaseUserPoints(user1, 100, 1);
    }

    function test_IncreaseUserPoints_RevertsIfNotPointRole() public {
        _register(user1);
        vm.prank(user2);
        vm.expectRevert("Not a point role");
        profile.increaseUserPoints(user1, 100, 1);
    }

    function test_DecreaseUserPoints_SubtractsPoints() public {
        _register(user1);
        vm.prank(pointRole);
        profile.increaseUserPoints(user1, 500, 1);
        vm.prank(pointRole);
        profile.decreaseUserPoints(user1, 200);

        (, uint256 pts,,,) = profile.getUserProfile(user1);
        assertEq(pts, 300);
    }

    function test_IncreaseUserPointsBatch_SkipsUnregistered() public {
        _register(user1);
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(pointRole);
        profile.increaseUserPointsBatch(users, 100, 1);

        (, uint256 pts,,,) = profile.getUserProfile(user1);
        assertEq(pts, 100);
    }

    function test_IncreaseTeamPoints_AddsPoints() public {
        vm.prank(pointRole);
        profile.increaseTeamPoints(1, 1000, 1);

        (,,, uint256 pts,) = profile.getTeam(1);
        assertEq(pts, 1000);
    }

    function test_DecreaseTeamPoints_SubtractsPoints() public {
        vm.prank(pointRole);
        profile.increaseTeamPoints(1, 1000, 1);
        vm.prank(pointRole);
        profile.decreaseTeamPoints(1, 400);

        (,,, uint256 pts,) = profile.getTeam(1);
        assertEq(pts, 600);
    }

    function test_IncreaseTeamPoints_RevertsOnInvalidId() public {
        vm.prank(pointRole);
        vm.expectRevert("TeamId invalid");
        profile.increaseTeamPoints(99, 100, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getUserProfile
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetUserProfile_ReturnsCorrectData() public {
        _register(user1);
        (uint256 id, uint256 pts, uint256 teamId, address avatar, uint256 tokenId)
            = profile.getUserProfile(user1);

        assertEq(id,      1);
        assertEq(pts,     0);
        assertEq(teamId,  1);
        assertEq(avatar,  address(0));
        assertEq(tokenId, 0);
    }

    function test_GetUserProfile_RevertsIfNotRegistered() public {
        vm.expectRevert("User not registered");
        profile.getUserProfile(user1);
    }
}
