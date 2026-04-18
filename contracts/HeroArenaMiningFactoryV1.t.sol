// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaMiningFactoryV1} from "./HeroArenaMiningFactoryV1.sol";
import {HeroArenaAvatars} from "./HeroArenaAvatars.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningFactoryV1Test is Test {
    HeroArenaMiningFactoryV1 factory;
    MockERC20                hapToken;
    HeroArenaAvatars         avatarsSC;

    address ownerAddr;
    address user1;
    address user2;
    address newOwner;

    uint256 constant NFT_PRICE = 100 * 10 ** 18;

    function setUp() public {
        ownerAddr = address(this);
        user1     = makeAddr("user1");
        user2     = makeAddr("user2");
        newOwner  = makeAddr("newOwner");

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
        assertEq(Ownable(address(avatarsSC)).owner(), address(factory));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(Ownable(address(factory)).owner(), ownerAddr);
    }

    function test_Constructor_ClaimDisabledByDefault() public view {
        assertFalse(factory.availableClaim());
    }

    function test_Constructor_SetsAllAvatarNames() public view {
        uint8[] memory ids = new uint8[](3);
        ids[0] = 0; ids[1] = 1; ids[2] = 89;
        (string[] memory names, ) = avatarsSC.getAvatarNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "Knight_v0");
        assertEq(names[1], "Knight_v1");
        assertEq(names[2], "Medic_v1");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAvailableClaim
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAvailableClaim_TogglesFlag() public {
        factory.updateAvailableClaim(true);
        assertTrue(factory.availableClaim());
        factory.updateAvailableClaim(false);
        assertFalse(factory.availableClaim());
    }

    function test_UpdateAvailableClaim_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaMiningFactoryV1.AvailableClaimUpdated(ownerAddr, true);
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

    function test_MintNFT_TransfersHapFromUser() public {
        factory.updateAvailableClaim(true);
        uint256 before = hapToken.balanceOf(user1);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(hapToken.balanceOf(user1), before - NFT_PRICE);
    }

    function test_MintNFT_FactoryReceivesHap() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(hapToken.balanceOf(address(factory)), NFT_PRICE);
    }

    function test_MintNFT_UserReceivesNFT() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(avatarsSC.balanceOf(user1), 1);
    }

    function test_MintNFT_IncrementsAvatarCount() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(5);
        assertEq(avatarsSC.avatarCount(5), 1);
    }

    function test_MintNFT_EmitsEvent() public {
        factory.updateAvailableClaim(true);
        vm.expectEmit(true, true, true, false);
        emit HeroArenaMiningFactoryV1.AvatarMinted(user1, 1, 0);
        vm.prank(user1);
        factory.mintNFT(0);
    }

    function test_MintNFT_MultipleUsers() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        vm.prank(user2);
        factory.mintNFT(1);
        assertEq(avatarsSC.balanceOf(user1), 1);
        assertEq(avatarsSC.balanceOf(user2), 1);
        assertEq(hapToken.balanceOf(address(factory)), NFT_PRICE * 2);
    }

    function test_MintNFT_RevertsWhenClaimDisabled() public {
        vm.prank(user1);
        vm.expectRevert("Cannot claim");
        factory.mintNFT(0);
    }

    function test_MintNFT_RevertsOnInvalidAvatarId() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        vm.expectRevert("Input avatarId unavailable");
        factory.mintNFT(90);
    }

    function test_MintNFT_RevertsOnInsufficientBalance() public {
        factory.updateAvailableClaim(true);
        address poorUser = makeAddr("poorUser");
        vm.prank(poorUser);
        hapToken.approve(address(factory), type(uint256).max);
        vm.prank(poorUser);
        vm.expectRevert();
        factory.mintNFT(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateNFTPrice
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateNFTPrice_UpdatesPrice() public {
        uint256 newPrice = 200 * 10 ** 18;
        factory.updateNFTPrice(newPrice);
        assertEq(factory.nftPrice(), newPrice);
    }

    function test_UpdateNFTPrice_EmitsEvent() public {
        uint256 newPrice = 200 * 10 ** 18;
        vm.expectEmit(false, false, false, true);
        emit HeroArenaMiningFactoryV1.AvatarPriceUpdated(newPrice);
        factory.updateNFTPrice(newPrice);
    }

    function test_UpdateNFTPrice_NewPriceUsedOnNextMint() public {
        uint256 newPrice = 50 * 10 ** 18;
        factory.updateNFTPrice(newPrice);
        factory.updateAvailableClaim(true);
        uint256 before = hapToken.balanceOf(user1);
        vm.prank(user1);
        factory.mintNFT(0);
        assertEq(hapToken.balanceOf(user1), before - newPrice);
    }

    function test_UpdateNFTPrice_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.updateNFTPrice(1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // proposeNFTContractOwnership + acceptNFTContractOwnership
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

    function test_ProposeOwnership_CanCancel() public {
        factory.proposeNFTContractOwnership(newOwner);
        factory.proposeNFTContractOwnership(address(0));
        assertEq(factory.pendingNFTContractOwner(), address(0));
    }

    function test_ProposeOwnership_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.proposeNFTContractOwnership(newOwner);
    }

    function test_AcceptOwnership_TransfersAvatarOwnership() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        factory.acceptNFTContractOwnership();
        assertEq(Ownable(address(avatarsSC)).owner(), newOwner);
    }

    function test_AcceptOwnership_ClearsPendingOwner() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        factory.acceptNFTContractOwnership();
        assertEq(factory.pendingNFTContractOwner(), address(0));
    }

    function test_AcceptOwnership_EmitsEvent() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.expectEmit(true, true, false, false);
        emit HeroArenaMiningFactoryV1.NFTContractOwnershipTransferred(address(factory), newOwner);
        vm.prank(newOwner);
        factory.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_RevertsIfNotPendingOwner() public {
        factory.proposeNFTContractOwnership(newOwner);
        vm.prank(user1);
        vm.expectRevert("Not the pending owner");
        factory.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_RevertsIfNoPendingOwner() public {
        vm.prank(user1);
        vm.expectRevert("Not the pending owner");
        factory.acceptNFTContractOwnership();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // claimFee
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ClaimFee_TransfersHapToOwner() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        vm.prank(user2);
        factory.mintNFT(1);
        uint256 before = hapToken.balanceOf(ownerAddr);
        factory.claimFee(NFT_PRICE * 2);
        assertEq(hapToken.balanceOf(ownerAddr), before + NFT_PRICE * 2);
    }

    function test_ClaimFee_PartialWithdraw() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        factory.claimFee(NFT_PRICE / 2);
        assertEq(hapToken.balanceOf(address(factory)), NFT_PRICE / 2);
    }

    function test_ClaimFee_RevertsOnInsufficientBalance() public {
        vm.expectRevert();
        factory.claimFee(1);
    }

    function test_ClaimFee_RevertsIfNotOwner() public {
        factory.updateAvailableClaim(true);
        vm.prank(user1);
        factory.mintNFT(0);
        vm.prank(user1);
        vm.expectRevert();
        factory.claimFee(NFT_PRICE);
    }

    receive() external payable {}
}
