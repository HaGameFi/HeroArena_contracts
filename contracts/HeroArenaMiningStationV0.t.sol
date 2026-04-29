// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaMiningStationV0} from "./HeroArenaMiningStationV0.sol";
import {HeroArenaFrames} from "./HeroArenaFrames.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningStationV0Test is Test {
    HeroArenaMiningStationV0 station;
    MockERC20                hapToken;
    HeroArenaFrames          framesSC;

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
        station   = new HeroArenaMiningStationV0(IERC20(address(hapToken)), NFT_PRICE);
        framesSC  = station.HeroArenaFramesSC();

        hapToken.mint(user1, 10_000 * 10 ** 18);
        hapToken.mint(user2, 10_000 * 10 ** 18);

        vm.prank(user1);
        hapToken.approve(address(station), type(uint256).max);
        vm.prank(user2);
        hapToken.approve(address(station), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsHapToken() public view {
        assertEq(address(station.HapToken()), address(hapToken));
    }

    function test_Constructor_SetsNftPrice() public view {
        assertEq(station.nftPrice(), NFT_PRICE);
    }

    function test_Constructor_DeploysFramesSC() public view {
        assertTrue(address(framesSC) != address(0));
    }

    function test_Constructor_SetsStationAsFramesOwner() public view {
        assertEq(Ownable(address(framesSC)).owner(), address(station));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(Ownable(address(station)).owner(), ownerAddr);
    }

    function test_Constructor_ClaimDisabledByDefault() public view {
        assertFalse(station.availableClaim());
    }

    function test_Constructor_SetsFrameName() public view {
        uint8[] memory ids = new uint8[](1);
        ids[0] = 0;
        (string[] memory names, ) = framesSC.getFrameNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "Default");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAvailableClaim
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAvailableClaim_TogglesFlag() public {
        station.updateAvailableClaim(true);
        assertTrue(station.availableClaim());
        station.updateAvailableClaim(false);
        assertFalse(station.availableClaim());
    }

    function test_UpdateAvailableClaim_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaMiningStationV0.AvailableClaimUpdated(ownerAddr, true);
        station.updateAvailableClaim(true);
    }

    function test_UpdateAvailableClaim_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        station.updateAvailableClaim(true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // mintNFT
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MintNFT_TransfersHapFromUser() public {
        station.updateAvailableClaim(true);
        uint256 before = hapToken.balanceOf(user1);
        vm.prank(user1);
        station.mintNFT(0);
        assertEq(hapToken.balanceOf(user1), before - NFT_PRICE);
    }

    function test_MintNFT_StationReceivesHap() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        assertEq(hapToken.balanceOf(address(station)), NFT_PRICE);
    }

    function test_MintNFT_UserReceivesNFT() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        assertEq(framesSC.balanceOf(user1), 1);
    }

    function test_MintNFT_IncrementsFrameCount() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        assertEq(framesSC.frameCount(0), 1);
    }

    function test_MintNFT_EmitsEvent() public {
        station.updateAvailableClaim(true);
        vm.expectEmit(true, true, true, false);
        emit HeroArenaMiningStationV0.FrameMinted(user1, 1, 0);
        vm.prank(user1);
        station.mintNFT(0);
    }

    function test_MintNFT_MultipleUsers() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        vm.prank(user2);
        station.mintNFT(0);
        assertEq(framesSC.balanceOf(user1), 1);
        assertEq(framesSC.balanceOf(user2), 1);
        assertEq(hapToken.balanceOf(address(station)), NFT_PRICE * 2);
    }

    function test_MintNFT_RevertsWhenClaimDisabled() public {
        vm.prank(user1);
        vm.expectRevert("Cannot claim");
        station.mintNFT(0);
    }

    function test_MintNFT_RevertsOnInvalidFrameId() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        vm.expectRevert("Input frameId unavailable");
        station.mintNFT(1);
    }

    function test_MintNFT_RevertsOnInsufficientBalance() public {
        station.updateAvailableClaim(true);
        address poorUser = makeAddr("poorUser");
        vm.prank(poorUser);
        hapToken.approve(address(station), type(uint256).max);
        vm.prank(poorUser);
        vm.expectRevert();
        station.mintNFT(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateNFTPrice
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateNFTPrice_UpdatesPrice() public {
        uint256 newPrice = 200 * 10 ** 18;
        station.updateNFTPrice(newPrice);
        assertEq(station.nftPrice(), newPrice);
    }

    function test_UpdateNFTPrice_EmitsEvent() public {
        uint256 newPrice = 200 * 10 ** 18;
        vm.expectEmit(false, false, false, true);
        emit HeroArenaMiningStationV0.FramePriceUpdated(newPrice);
        station.updateNFTPrice(newPrice);
    }

    function test_UpdateNFTPrice_NewPriceUsedOnNextMint() public {
        uint256 newPrice = 50 * 10 ** 18;
        station.updateNFTPrice(newPrice);
        station.updateAvailableClaim(true);
        uint256 before = hapToken.balanceOf(user1);
        vm.prank(user1);
        station.mintNFT(0);
        assertEq(hapToken.balanceOf(user1), before - newPrice);
    }

    function test_UpdateNFTPrice_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        station.updateNFTPrice(1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // proposeNFTContractOwnership + acceptNFTContractOwnership
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProposeOwnership_SetsPendingOwner() public {
        station.proposeNFTContractOwnership(newOwner);
        assertEq(station.pendingNFTContractOwner(), newOwner);
    }

    function test_ProposeOwnership_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit HeroArenaMiningStationV0.NFTContractOwnershipProposed(address(station), newOwner);
        station.proposeNFTContractOwnership(newOwner);
    }

    function test_ProposeOwnership_CanCancel() public {
        station.proposeNFTContractOwnership(newOwner);
        station.proposeNFTContractOwnership(address(0));
        assertEq(station.pendingNFTContractOwner(), address(0));
    }

    function test_ProposeOwnership_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        station.proposeNFTContractOwnership(newOwner);
    }

    function test_AcceptOwnership_TransfersFramesOwnership() public {
        station.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        station.acceptNFTContractOwnership();
        assertEq(Ownable(address(framesSC)).owner(), newOwner);
    }

    function test_AcceptOwnership_ClearsPendingOwner() public {
        station.proposeNFTContractOwnership(newOwner);
        vm.prank(newOwner);
        station.acceptNFTContractOwnership();
        assertEq(station.pendingNFTContractOwner(), address(0));
    }

    function test_AcceptOwnership_EmitsEvent() public {
        station.proposeNFTContractOwnership(newOwner);
        vm.expectEmit(true, true, false, false);
        emit HeroArenaMiningStationV0.NFTContractOwnershipTransferred(address(station), newOwner);
        vm.prank(newOwner);
        station.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_RevertsIfNotPendingOwner() public {
        station.proposeNFTContractOwnership(newOwner);
        vm.prank(user1);
        vm.expectRevert("Not the pending owner");
        station.acceptNFTContractOwnership();
    }

    function test_AcceptOwnership_RevertsIfNoPendingOwner() public {
        vm.prank(user1);
        vm.expectRevert("Not the pending owner");
        station.acceptNFTContractOwnership();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // claimFee
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ClaimFee_TransfersHapToOwner() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        vm.prank(user2);
        station.mintNFT(0);
        uint256 before = hapToken.balanceOf(ownerAddr);
        station.claimFee(NFT_PRICE * 2);
        assertEq(hapToken.balanceOf(ownerAddr), before + NFT_PRICE * 2);
    }

    function test_ClaimFee_PartialWithdraw() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        station.claimFee(NFT_PRICE / 2);
        assertEq(hapToken.balanceOf(address(station)), NFT_PRICE / 2);
    }

    function test_ClaimFee_RevertsOnInsufficientBalance() public {
        vm.expectRevert();
        station.claimFee(1);
    }

    function test_ClaimFee_RevertsIfNotOwner() public {
        station.updateAvailableClaim(true);
        vm.prank(user1);
        station.mintNFT(0);
        vm.prank(user1);
        vm.expectRevert();
        station.claimFee(NFT_PRICE);
    }

    receive() external payable {}
}
