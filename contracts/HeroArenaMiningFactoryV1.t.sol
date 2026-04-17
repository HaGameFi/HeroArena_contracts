// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaMiningFactoryV1} from "./HeroArenaMiningFactoryV1.sol";
import {HeroArenaAvatars} from "./HeroArenaAvatars.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningFactoryV1Test is Test {
    HeroArenaMiningFactoryV1 factory;
    MockERC20 hapToken;
    HeroArenaAvatars avatarsSC;

    address owner;
    address user1;
    address user2;
    address newOwner;

    uint256 constant NFT_PRICE = 100 * 10 ** 18;

    function setUp() public {
        owner    = address(this);
        user1    = makeAddr("user1");
        user2    = makeAddr("user2");
        newOwner = makeAddr("newOwner");

        hapToken  = new MockERC20();
        factory   = new HeroArenaMiningFactoryV1(IERC20(address(hapToken)), NFT_PRICE);
        avatarsSC = factory.HeroArenaAvatarsSC();

        hapToken.mint(user1, 10_000 * 10 ** 18);
        hapToken.mint(user2, 10_000 * 10 ** 18);

        vm.prank(user1);
        hapToken.approve(address(factory), type(uint256).max);
        vm.prank(user2);
        hapToken.approve(address(factory), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsHapToken() public view {
        assertEq(address(factory.HapToken()), address(hapToken));
    }

    function test_Constructor_SetsNftPrice() public view {
        assertEq(factory.nftPrice(), NFT_PRICE);
    }

    function test_Constructor_DeploysAvatarsSC() public view {
        assertTrue(address(avatarsSC) != address(0));
    }

    function test_Constructor_SetsFactoryAsAvatarOwner() public view {
        assertEq(avatarsSC.owner(), address(factory));
    }

    function test_Constructor_InitializesFirstAvatarName() public view {
        uint8[] memory ids = new uint8[](1);
        ids[0] = 0;
        (string[] memory names,) = avatarsSC.getAvatarNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "Knight_v0");
    }

    function test_Constructor_InitializesLastAvatarName() public view {
        uint8[] memory ids = new uint8[](1);
        ids[0] = 18;
        (string[] memory names,) = avatarsSC.getAvatarNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "Ninja_v2");
    }

    function test_Constructor_AvailableClaimFalseByDefault() public view {
        assertFalse(factory.availableClaim());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAvailableClaim
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAvailableClaim_SetsTrue() public {
        factory.updateAvailableClaim(true);
        assertTrue(factory.availableClaim());
    }

    function test_UpdateAvailableClaim_SetsFalse() public {
        factory.updateAvailableClaim(true);
        factory.updateAvailableClaim(false);
        assertFalse(factory.availableClaim());
    }

    function test_UpdateAvailableClaim_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaMiningFactoryV1.AvailableClaimUpdated(owner, true);
        factory.updateAvailableClaim(true);
    }

    function test_UpdateAvailableClaim_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.updateAvailableClaim(true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // mintNFT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MintNFT_TransfersHAPFromUser() public {
        factory.updateAvailableClaim(true);
        uint256 balBefore = hapToken.balanceOf(user1);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(hapToken.balanceOf(user1), balBefore - NFT_PRICE);
    }

    function test_MintNFT_AccumulatesHAPInContract() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(hapToken.balanceOf(address(factory)), NFT_PRICE);
    }

    function test_MintNFT_MintsNFTToUser() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(avatarsSC.balanceOf(user1), 1);
    }

    function test_MintNFT_IncrementsAvatarCount() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(3);
        assertEq(avatarsSC.avatarCount(3), 1);
    }

    function test_MintNFT_EmitsAvatarMinted() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        vm.expectEmit(true, true, true, false);
        emit HeroArenaMiningFactoryV1.AvatarMinted(user1, 1, 0);
        factory.mintNFT(0);
    }

    function test_MintNFT_MultipleUsersCanMint() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        vm.prank(user2);
        factory.mintNFT(1);
        assertEq(avatarsSC.balanceOf(user1), 1);
        assertEq(avatarsSC.balanceOf(user2), 1);
        assertEq(avatarsSC.totalSupply(), 2);
    }

    function test_MintNFT_RevertsIfClaimDisabled() public {
        vm.prank(user1);
        vm.expectRevert("Cannot claim");
        factory.mintNFT(0);
    }

    function test_MintNFT_RevertsIfAvatarIdOutOfRange() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        vm.expectRevert("Input avatarId unavailable");
        factory.mintNFT(19);
    }

    function test_MintNFT_AllowsMaxValidAvatarId() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(18);
        assertEq(avatarsSC.balanceOf(user1), 1);
    }

    function test_MintNFT_RevertsIfInsufficientAllowance() public {
        factory.updateAvailableClaim(true);
        vm.prank(user2);
        hapToken.approve(address(factory), 0);
        vm.prank(user2);
        vm.expectRevert();
        factory.mintNFT(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateNFTPrice
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateNFTPrice_SetsNewPrice() public {
        factory.updateNFTPrice(200 * 10 ** 18);
        assertEq(factory.nftPrice(), 200 * 10 ** 18);
    }

    function test_UpdateNFTPrice_NewPriceAppliedOnMint() public {
        factory.updateNFTPrice(50 * 10 ** 18);
        factory.updateAvailableClaim(true);
        uint256 balBefore = hapToken.balanceOf(user1);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(hapToken.balanceOf(user1), balBefore - 50 * 10 ** 18);
    }

    function test_UpdateNFTPrice_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit HeroArenaMiningFactoryV1.AvatarPriceUpdated(200 * 10 ** 18);
        factory.updateNFTPrice(200 * 10 ** 18);
    }

    function test_UpdateNFTPrice_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.updateNFTPrice(200 * 10 ** 18);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // proposeNFTContractOwnership
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProposeOwnership_SetsPendingOwner() public {
        factory.proposeNFTContractOwnership(newOwner);
        assertEq(factory.pendingNFTContractOwner(), newOwner);
    }

    function test_ProposeOwnership_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit HeroArenaMiningFactoryV1.NFTContractOwnershipProposed(address(factory), newOwner);
        factory.proposeNFTContractOwnership(newOwner);
    }

    function test_ProposeOwnership_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.proposeNFTContractOwnership(newOwner);
    }

    function test_ProposeOwnership_CanCancelWithZeroAddress() public {
        factory.proposeNFTContractOwnership(newOwner);
        factory.proposeNFTContractOwnership(address(0));
        assertEq(factory.pendingNFTContractOwner(), address(0));
    }

    function test_ProposeOwnership_CanOverwritePendingOwner() public {
        factory.proposeNFTContractOwnership(newOwner);
        factory.proposeNFTContractOwnership(user2);
        assertEq(factory.pendingNFTContractOwner(), user2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // acceptNFTContractOwnership
    // ═══════════════════════════════════════════════════════════════════════════

    function test_AcceptOwnership_TransfersNFTContractOwnership() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        factory.acceptNFTContractOwnership();
        assertEq(avatarsSC.owner(), newOwner);
    }

    function test_AcceptOwnership_ClearsPendingOwner() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        factory.acceptNFTContractOwnership();
        assertEq(factory.pendingNFTContractOwner(), address(0));
    }

    function test_AcceptOwnership_EmitsEvent() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit HeroArenaMiningFactoryV1.NFTContractOwnershipTransferred(address(factory), newOwner);
        factory.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_RevertsIfNotPendingOwner() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(user1);
        vm.expectRevert("Not the pending owner");
        factory.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_RevertsIfNoPendingProposal() public {
        vm.prank(user1);
        vm.expectRevert("Not the pending owner");
        factory.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_MintNFTRevertsAfterTransfer() public {
        factory.updateAvailableClaim(true);
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        factory.acceptNFTContractOwnership();

        vm.prank(user1);
        vm.expectRevert();
        factory.mintNFT(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // claimFee
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ClaimFee_TransfersHAPToOwner() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);

        uint256 balBefore = hapToken.balanceOf(owner);
        factory.claimFee(NFT_PRICE);
        assertEq(hapToken.balanceOf(owner), balBefore + NFT_PRICE);
    }

    function test_ClaimFee_PartialWithdrawal() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        vm.prank(user2);
        factory.mintNFT(0);

        factory.claimFee(NFT_PRICE);
        assertEq(hapToken.balanceOf(address(factory)), NFT_PRICE);
    }

    function test_ClaimFee_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.claimFee(1);
    }
}
