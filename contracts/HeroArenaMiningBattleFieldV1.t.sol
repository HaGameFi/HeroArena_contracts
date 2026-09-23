// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HeroArenaMiningBattleFieldV1} from "./HeroArenaMiningBattleFieldV1.sol";
import {HeroArenaBattleFields} from "./HeroArenaBattleFields.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningBattleFieldV1Test is Test {
    uint256 constant PRICE = 100 ether;
    HeroArenaMiningBattleFieldV1 mining;
    HeroArenaBattleFields battleFields;
    MockERC20 hap;
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");
    address newOwner = makeAddr("newOwner");

    function setUp() public {
        hap = new MockERC20();
        battleFields = new HeroArenaBattleFields();
        mining = new HeroArenaMiningBattleFieldV1(
            IERC20(address(hap)), battleFields, PRICE
        );
        battleFields.transferOwnership(address(mining));
        mining.initializeBattleFields();
        hap.mint(user, 2_000 ether);
        vm.prank(user); hap.approve(address(mining), type(uint256).max);
    }

    function test_InitializationConfiguresIdsTwoThroughNine() public view {
        assertEq(address(mining.HapToken()), address(hap));
        assertEq(address(mining.heroArenaBattleFieldsSC()), address(battleFields));
        assertEq(mining.nftPrice(), PRICE);
        assertEq(battleFields.owner(), address(mining));
        assertTrue(mining.battleFieldsInitialized());
        uint8[] memory ids = new uint8[](8);
        for (uint8 i; i < 8; i++) ids[i] = i + 2;
        (string[] memory names, ) = battleFields.getBattleFieldNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "MapId002");
        assertEq(names[7], "MapId009");
    }

    function test_DeploysBeforeOwnershipTransferAndInitializesOnlyOnce() public {
        HeroArenaBattleFields otherBattleFields = new HeroArenaBattleFields();
        HeroArenaMiningBattleFieldV1 otherMining = new HeroArenaMiningBattleFieldV1(
            IERC20(address(hap)), otherBattleFields, PRICE
        );

        vm.expectRevert("V1 is not BattleFields owner");
        otherMining.initializeBattleFields();

        otherBattleFields.transferOwnership(address(otherMining));
        otherMining.initializeBattleFields();
        assertTrue(otherMining.battleFieldsInitialized());

        vm.expectRevert("BattleFields already initialized");
        otherMining.initializeBattleFields();
    }

    function test_InitializeBattleFieldsIsOwnerOnly() public {
        HeroArenaBattleFields otherBattleFields = new HeroArenaBattleFields();
        HeroArenaMiningBattleFieldV1 otherMining = new HeroArenaMiningBattleFieldV1(
            IERC20(address(hap)), otherBattleFields, PRICE
        );
        otherBattleFields.transferOwnership(address(otherMining));
        vm.prank(user);
        vm.expectRevert();
        otherMining.initializeBattleFields();
    }

    function test_MintEveryValidId() public {
        mining.updateAvailableClaim(true);
        vm.startPrank(user);
        for (uint8 id = 2; id < 10; id++) mining.mintNFT(id);
        vm.stopPrank();
        assertEq(battleFields.balanceOf(user), 8);
        assertEq(hap.balanceOf(address(mining)), PRICE * 8);
        for (uint8 id = 2; id < 10; id++) assertEq(battleFields.battleFieldCount(id), 1);
    }

    function test_CannotBuySameBattleFieldWhileCurrentlyOwned() public {
        mining.updateAvailableClaim(true);
        vm.startPrank(user);
        mining.mintNFT(2);
        vm.expectRevert("BattleField already owned");
        mining.mintNFT(2);
        vm.stopPrank();

        assertEq(battleFields.balanceOf(user), 1);
        assertEq(hap.balanceOf(address(mining)), PRICE);
    }

    function test_CanBuySameBattleFieldAgainAfterTransfer() public {
        mining.updateAvailableClaim(true);
        vm.startPrank(user);
        mining.mintNFT(2);
        battleFields.transferFrom(user, recipient, 1);
        mining.mintNFT(2);
        vm.stopPrank();

        assertTrue(battleFields.hasBattleField(user, 2));
        assertTrue(battleFields.hasBattleField(recipient, 2));
        assertEq(battleFields.balanceOf(user), 1);
        assertEq(hap.balanceOf(address(mining)), PRICE * 2);
    }

    function test_MintRejectsBothIdBoundaries() public {
        mining.updateAvailableClaim(true);
        vm.prank(user);
        vm.expectRevert("Input battleFieldId too low"); mining.mintNFT(1);
        vm.prank(user);
        vm.expectRevert("Input battleFieldId unavailable"); mining.mintNFT(10);
    }

    function test_MintDisabledAndEvent() public {
        vm.prank(user);
        vm.expectRevert("Cannot claim"); mining.mintNFT(2);
        mining.updateAvailableClaim(true);
        vm.expectEmit(true, true, true, true);
        emit HeroArenaMiningBattleFieldV1.BattleFieldMinted(user, 1, 9);
        vm.prank(user); mining.mintNFT(9);
    }

    function test_UpdatePriceEventAndNewPriceIsCharged() public {
        vm.expectEmit(false, false, false, true);
        emit HeroArenaMiningBattleFieldV1.BattleFieldPriceUpdated(25 ether);
        mining.updateNFTPrice(25 ether);
        mining.updateAvailableClaim(true);
        vm.prank(user); mining.mintNFT(2);
        assertEq(hap.balanceOf(address(mining)), 25 ether);
    }

    function test_AdminFunctionsAreOwnerOnly() public {
        vm.startPrank(user);
        vm.expectRevert(); mining.updateAvailableClaim(true);
        vm.expectRevert(); mining.updateNFTPrice(1);
        vm.expectRevert(); mining.proposeNFTContractOwnership(newOwner);
        vm.expectRevert(); mining.claimFee(0);
        vm.stopPrank();
    }

    function test_ClaimFeeAndTwoStepNFTContractOwnership() public {
        mining.updateAvailableClaim(true);
        vm.prank(user); mining.mintNFT(2);
        mining.claimFee(PRICE);
        assertEq(hap.balanceOf(address(this)), PRICE);
        mining.proposeNFTContractOwnership(newOwner);
        vm.prank(user);
        vm.expectRevert("Not the pending owner"); mining.acceptNFTContractOwnership();
        vm.prank(newOwner); mining.acceptNFTContractOwnership();
        assertEq(battleFields.owner(), newOwner);
        assertEq(mining.pendingNFTContractOwner(), address(0));
    }
}
