// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HeroArenaMiningStationV1} from "./HeroArenaMiningStationV1.sol";
import {HeroArenaFrames} from "./HeroArenaFrames.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningStationV1Test is Test {
    uint256 constant PRICE = 100 ether;
    HeroArenaMiningStationV1 station;
    HeroArenaFrames frames;
    MockERC20 hap;
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");
    address newOwner = makeAddr("newOwner");

    function setUp() public {
        hap = new MockERC20();
        frames = new HeroArenaFrames();
        station = new HeroArenaMiningStationV1(IERC20(address(hap)), frames, PRICE);
        frames.transferOwnership(address(station));
        station.initializeFrames();
        hap.mint(user, 1_000 ether);
        vm.prank(user);
        hap.approve(address(station), type(uint256).max);
    }

    function test_InitializationConfiguresFrameOne() public view {
        assertEq(address(station.HapToken()), address(hap));
        assertEq(address(station.heroArenaFramesSC()), address(frames));
        assertEq(station.nftPrice(), PRICE);
        assertEq(frames.owner(), address(station));
        assertTrue(station.framesInitialized());
        uint8[] memory ids = new uint8[](1);
        ids[0] = 1;
        (string[] memory names, ) = frames.getFrameNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "Sapphire_v0");
    }

    function test_DeploysBeforeOwnershipTransferAndInitializesOnlyOnce() public {
        HeroArenaFrames otherFrames = new HeroArenaFrames();
        HeroArenaMiningStationV1 otherStation =
            new HeroArenaMiningStationV1(IERC20(address(hap)), otherFrames, PRICE);
        vm.expectRevert("V1 is not Frames owner");
        otherStation.initializeFrames();
        otherFrames.transferOwnership(address(otherStation));
        otherStation.initializeFrames();
        vm.expectRevert("Frames already initialized");
        otherStation.initializeFrames();
    }

    function test_MintsFrameOneAndCollectsFee() public {
        station.updateAvailableClaim(true);
        vm.expectEmit(true, true, true, true);
        emit HeroArenaMiningStationV1.FrameMinted(user, 1, 1);
        vm.prank(user);
        station.mintNFT(1);
        assertEq(frames.balanceOf(user), 1);
        assertEq(frames.frameCount(1), 1);
        assertEq(hap.balanceOf(address(station)), PRICE);
    }

    function test_RejectsDisabledAndInvalidFrameIds() public {
        vm.prank(user);
        vm.expectRevert("Cannot claim");
        station.mintNFT(1);
        station.updateAvailableClaim(true);
        vm.prank(user);
        vm.expectRevert("Input frameId too low");
        station.mintNFT(0);
        vm.prank(user);
        vm.expectRevert("Input frameId unavailable");
        station.mintNFT(2);
    }

    function test_CannotBuySameFrameWhileCurrentlyOwned() public {
        station.updateAvailableClaim(true);
        vm.startPrank(user);
        station.mintNFT(1);
        vm.expectRevert("Frame already owned");
        station.mintNFT(1);
        vm.stopPrank();
        assertEq(hap.balanceOf(address(station)), PRICE);
    }

    function test_CanBuySameFrameAgainAfterTransfer() public {
        station.updateAvailableClaim(true);
        vm.startPrank(user);
        station.mintNFT(1);
        frames.transferFrom(user, recipient, 1);
        station.mintNFT(1);
        vm.stopPrank();
        assertTrue(frames.hasFrame(user, 1));
        assertTrue(frames.hasFrame(recipient, 1));
        assertEq(hap.balanceOf(address(station)), PRICE * 2);
    }

    function test_UpdatePriceChangesNextMintFee() public {
        station.updateNFTPrice(25 ether);
        station.updateAvailableClaim(true);
        vm.prank(user);
        station.mintNFT(1);
        assertEq(hap.balanceOf(address(station)), 25 ether);
    }

    function test_AdminFunctionsAreOwnerOnly() public {
        vm.startPrank(user);
        vm.expectRevert(); station.initializeFrames();
        vm.expectRevert(); station.updateAvailableClaim(true);
        vm.expectRevert(); station.updateNFTPrice(1);
        vm.expectRevert(); station.proposeNFTContractOwnership(newOwner);
        vm.expectRevert(); station.claimFee(0);
        vm.stopPrank();
    }

    function test_ClaimFeeAndTwoStepFramesOwnershipTransfer() public {
        station.updateAvailableClaim(true);
        vm.prank(user); station.mintNFT(1);
        station.claimFee(PRICE);
        assertEq(hap.balanceOf(address(station)), 0);
        station.proposeNFTContractOwnership(newOwner);
        vm.prank(user);
        vm.expectRevert("Not the pending owner"); station.acceptNFTContractOwnership();
        vm.prank(newOwner); station.acceptNFTContractOwnership();
        assertEq(frames.owner(), newOwner);
        assertEq(station.pendingNFTContractOwner(), address(0));
    }
}
