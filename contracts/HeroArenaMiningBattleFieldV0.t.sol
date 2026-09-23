// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {HeroArenaMiningBattleFieldV0} from "./HeroArenaMiningBattleFieldV0.sol";
import {HeroArenaBattleFields} from "./HeroArenaBattleFields.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningBattleFieldV0Test is Test {
    uint256 constant PRICE = 100 ether;
    HeroArenaMiningBattleFieldV0 mining;
    HeroArenaBattleFields battleFields;
    MockERC20 hap;
    address user = makeAddr("user");
    address newOwner = makeAddr("newOwner");

    function setUp() public {
        hap = new MockERC20();
        mining = new HeroArenaMiningBattleFieldV0(IERC20(address(hap)), PRICE);
        battleFields = mining.HeroArenaBattleFieldsSC();
        hap.mint(user, 1_000 ether);
        vm.prank(user);
        hap.approve(address(mining), type(uint256).max);
    }

    function test_ConstructorInitializesStateAndMetadata() public view {
        assertEq(address(mining.HapToken()), address(hap));
        assertEq(mining.nftPrice(), PRICE);
        assertFalse(mining.availableClaim());
        assertEq(mining.owner(), address(this));
        assertEq(battleFields.owner(), address(mining));
        uint8[] memory ids = new uint8[](2);
        ids[0] = 0; ids[1] = 1;
        (string[] memory names, uint256[] memory timestamps) =
            battleFields.getBattleFieldNameAndCreatedTimestampBatch(ids);
        assertEq(names[0], "Blank");
        assertEq(names[1], "Default");
        assertGt(timestamps[0], 0);
        assertGt(timestamps[1], 0);
    }

    function test_MintAllValidIdsAndCollectFees() public {
        mining.updateAvailableClaim(true);
        vm.startPrank(user);
        mining.mintNFT(0);
        mining.mintNFT(1);
        vm.stopPrank();
        assertEq(battleFields.balanceOf(user), 2);
        assertEq(battleFields.battleFieldCount(0), 1);
        assertEq(battleFields.battleFieldCount(1), 1);
        assertEq(hap.balanceOf(address(mining)), PRICE * 2);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1; tokenIds[1] = 2;
        uint8[] memory ids = battleFields.getBattleFieldIdBatch(tokenIds);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
    }

    function test_MintEmitsEvent() public {
        mining.updateAvailableClaim(true);
        vm.expectEmit(true, true, true, true);
        emit HeroArenaMiningBattleFieldV0.BattleFieldMinted(user, 1, 1);
        vm.prank(user);
        mining.mintNFT(1);
    }

    function test_MintRejectsDisabledInvalidIdAndMissingAllowance() public {
        vm.prank(user);
        vm.expectRevert("Cannot claim");
        mining.mintNFT(0);
        mining.updateAvailableClaim(true);
        vm.prank(user);
        vm.expectRevert("Input battleFieldId unavailable");
        mining.mintNFT(2);
        address noAllowance = makeAddr("noAllowance");
        hap.mint(noAllowance, PRICE);
        vm.prank(noAllowance);
        vm.expectRevert();
        mining.mintNFT(0);
    }

    function test_OwnerControlsAvailabilityAndPrice() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaMiningBattleFieldV0.AvailableClaimUpdated(address(this), true);
        mining.updateAvailableClaim(true);
        vm.expectEmit(false, false, false, true);
        emit HeroArenaMiningBattleFieldV0.BattleFieldPriceUpdated(5 ether);
        mining.updateNFTPrice(5 ether);
        assertTrue(mining.availableClaim());
        assertEq(mining.nftPrice(), 5 ether);
        vm.startPrank(user);
        vm.expectRevert(); mining.updateAvailableClaim(false);
        vm.expectRevert(); mining.updateNFTPrice(1);
        vm.stopPrank();
    }

    function test_ClaimFeeOwnerOnlyAndSupportsPartialClaim() public {
        mining.updateAvailableClaim(true);
        vm.prank(user); mining.mintNFT(0);
        vm.prank(user);
        vm.expectRevert(); mining.claimFee(PRICE);
        mining.claimFee(40 ether);
        assertEq(hap.balanceOf(address(this)), 40 ether);
        assertEq(hap.balanceOf(address(mining)), 60 ether);
        vm.expectRevert(); mining.claimFee(61 ether);
    }

    function test_TwoStepNFTContractOwnershipTransferAndCancel() public {
        mining.proposeNFTContractOwnership(newOwner);
        assertEq(mining.pendingNFTContractOwner(), newOwner);
        vm.prank(user);
        vm.expectRevert("Not the pending owner"); mining.acceptNFTContractOwnership();
        vm.prank(newOwner); mining.acceptNFTContractOwnership();
        assertEq(battleFields.owner(), newOwner);
        assertEq(mining.pendingNFTContractOwner(), address(0));
    }

    function test_OnlyOwnerCanProposeAndProposalCanBeCancelled() public {
        vm.prank(user);
        vm.expectRevert(); mining.proposeNFTContractOwnership(newOwner);
        mining.proposeNFTContractOwnership(newOwner);
        mining.proposeNFTContractOwnership(address(0));
        assertEq(mining.pendingNFTContractOwner(), address(0));
    }
}
