// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaMiningFactoryV1} from "./HeroArenaMiningFactoryV1.sol";
import {
    HeroArenaMiningFactoryV2,
    IHeroArenaMiningFactoryMigration
} from "./HeroArenaMiningFactoryV2.sol";
import {HeroArenaAvatars} from "./HeroArenaAvatars.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMiningFactoryV2Test is Test {
    uint256 private constant NFT_PRICE = 100 ether;

    MockERC20 private hapToken;
    HeroArenaMiningFactoryV1 private factoryV1;
    HeroArenaMiningFactoryV2 private factoryV2;
    HeroArenaAvatars private avatars;

    address private user = makeAddr("user");
    address private nextAvatarOwner = makeAddr("nextAvatarOwner");
    address private nextFactoryOwner = makeAddr("nextFactoryOwner");

    function setUp() public {
        hapToken = new MockERC20();
        factoryV1 = new HeroArenaMiningFactoryV1(IERC20(address(hapToken)), NFT_PRICE);
        avatars = factoryV1.HeroArenaAvatarsSC();
        factoryV2 = new HeroArenaMiningFactoryV2(
            IERC20(address(hapToken)), avatars, NFT_PRICE
        );

        hapToken.mint(user, 1_000 ether);
        vm.prank(user);
        hapToken.approve(address(factoryV2), type(uint256).max);
    }

    function _migrateAndInitialize() private {
        factoryV1.proposeNFTContractOwnership(address(factoryV2));
        factoryV2.acceptAvatarOwnershipFromV1(
            IHeroArenaMiningFactoryMigration(address(factoryV1))
        );
        factoryV2.setAvatarJson();
    }

    function test_ConstructorSetsConfigurationAndStartsDisabled() public view {
        assertEq(address(factoryV2.HapToken()), address(hapToken));
        assertEq(address(factoryV2.heroArenaAvatarsSC()), address(avatars));
        assertEq(address(factoryV2.HeroArenaAvatarsSC()), address(avatars));
        assertEq(factoryV2.nftPrice(), NFT_PRICE);
        assertFalse(factoryV2.availableClaim());
        assertFalse(factoryV2.avatarMetadataInitialized());
    }

    function test_ConstructorRejectsEoaHapToken() public {
        vm.expectRevert("HapToken must be a contract");
        new HeroArenaMiningFactoryV2(IERC20(user), avatars, NFT_PRICE);
    }

    function test_ConstructorRejectsEoaAvatarContract() public {
        vm.expectRevert("Avatars must be a contract");
        new HeroArenaMiningFactoryV2(
            IERC20(address(hapToken)), HeroArenaAvatars(user), NFT_PRICE
        );
    }

    function test_EnableClaimRevertsBeforeMigration() public {
        vm.expectRevert("V2 does not own Avatars");
        factoryV2.updateAvailableClaim(true);
    }

    function test_EnableClaimRevertsBeforeMetadataInitialization() public {
        factoryV1.proposeNFTContractOwnership(address(factoryV2));
        factoryV2.acceptAvatarOwnershipFromV1(
            IHeroArenaMiningFactoryMigration(address(factoryV1))
        );

        vm.expectRevert("Avatar metadata not initialized");
        factoryV2.updateAvailableClaim(true);
    }

    function test_MigrationTransfersAvatarOwnershipAndEmitsEvent() public {
        factoryV1.proposeNFTContractOwnership(address(factoryV2));

        vm.expectEmit(true, true, false, false);
        emit HeroArenaMiningFactoryV2.AvatarOwnershipAccepted(
            address(factoryV1), address(factoryV2)
        );
        factoryV2.acceptAvatarOwnershipFromV1(
            IHeroArenaMiningFactoryMigration(address(factoryV1))
        );

        assertEq(Ownable(address(avatars)).owner(), address(factoryV2));
        assertEq(factoryV1.pendingNFTContractOwner(), address(0));
    }

    function test_MigrationRejectsFactoryWithDifferentAvatarContract() public {
        HeroArenaMiningFactoryV1 otherV1 =
            new HeroArenaMiningFactoryV1(IERC20(address(hapToken)), NFT_PRICE);

        vm.expectRevert("Avatars mismatch");
        factoryV2.acceptAvatarOwnershipFromV1(
            IHeroArenaMiningFactoryMigration(address(otherV1))
        );
    }

    function test_MigrationRequiresV2ToBePendingOwner() public {
        vm.expectRevert("Factory is not the pending Avatar owner");
        factoryV2.acceptAvatarOwnershipFromV1(
            IHeroArenaMiningFactoryMigration(address(factoryV1))
        );
    }

    function test_GenericMigrationSupportsV2ToSuccessorFactory() public {
        _migrateAndInitialize();
        HeroArenaMiningFactoryV2 successor = new HeroArenaMiningFactoryV2(
            IERC20(address(hapToken)), avatars, NFT_PRICE
        );

        factoryV2.proposeNFTContractOwnership(address(successor));
        successor.acceptAvatarOwnershipFromFactory(
            IHeroArenaMiningFactoryMigration(address(factoryV2))
        );

        assertEq(Ownable(address(avatars)).owner(), address(successor));
        assertEq(factoryV2.pendingNFTContractOwner(), address(0));
    }

    function test_SetAvatarJsonInitializesAllV2MetadataOnlyOnce() public {
        _migrateAndInitialize();

        uint8[] memory ids = new uint8[](4);
        ids[0] = 30;
        ids[1] = 41;
        ids[2] = 48;
        ids[3] = 59;
        (string[] memory names, uint256[] memory timestamps) =
            avatars.getAvatarNameAndCreatedTimestampBatch(ids);

        assertEq(names[0], "VoidMonk_v0");
        assertEq(names[1], "Impaler_v5");
        assertEq(names[2], "Necro_v0");
        assertEq(names[3], "Wraith_v5");
        assertGt(timestamps[0], 0);
        assertTrue(factoryV2.avatarMetadataInitialized());

        vm.expectRevert("Avatar metadata already initialized");
        factoryV2.setAvatarJson();
    }

    function test_MintAcceptsBoundaryIdsAndCollectsExactPrice() public {
        _migrateAndInitialize();
        factoryV2.updateAvailableClaim(true);

        vm.startPrank(user);
        factoryV2.mintNFT(0, NFT_PRICE);
        factoryV2.mintNFT(59, NFT_PRICE);
        vm.stopPrank();

        assertEq(avatars.balanceOf(user), 2);
        assertEq(avatars.avatarCount(0), 1);
        assertEq(avatars.avatarCount(59), 1);
        assertEq(hapToken.balanceOf(address(factoryV2)), NFT_PRICE * 2);
    }

    function test_MintRejectsIdAtUpperBoundary() public {
        _migrateAndInitialize();
        factoryV2.updateAvailableClaim(true);

        vm.expectRevert("Input avatarId unavailable");
        vm.prank(user);
        factoryV2.mintNFT(60, NFT_PRICE);
    }

    function test_MintHonorsCallerMaximumPrice() public {
        _migrateAndInitialize();
        factoryV2.updateAvailableClaim(true);
        factoryV2.updateNFTPrice(NFT_PRICE + 1);

        vm.prank(user);
        vm.expectRevert("Price exceeds maximum");
        factoryV2.mintNFT(30, NFT_PRICE);
    }

    function test_OnlyOwnerCanInitializeOrEnableClaim() public {
        vm.startPrank(user);
        vm.expectRevert();
        factoryV2.setAvatarJson();
        vm.expectRevert();
        factoryV2.updateAvailableClaim(true);
        vm.stopPrank();
    }

    function test_AvatarOwnershipCanBeTransferredAgain() public {
        _migrateAndInitialize();
        factoryV2.proposeNFTContractOwnership(nextAvatarOwner);

        vm.prank(nextAvatarOwner);
        factoryV2.acceptNFTContractOwnership();

        assertEq(Ownable(address(avatars)).owner(), nextAvatarOwner);
        assertEq(factoryV2.pendingNFTContractOwner(), address(0));

        vm.prank(user);
        vm.expectRevert("V2 does not own Avatars");
        factoryV2.mintNFT(30, NFT_PRICE);
    }

    function test_FactoryOwnershipTransferClearsPendingAvatarOwner() public {
        _migrateAndInitialize();
        factoryV2.proposeNFTContractOwnership(nextAvatarOwner);
        factoryV2.transferOwnership(nextFactoryOwner);

        assertEq(factoryV2.pendingNFTContractOwner(), address(0));
        assertEq(factoryV2.owner(), nextFactoryOwner);
    }

    function test_ClaimFeeTransfersHapToFactoryOwner() public {
        _migrateAndInitialize();
        factoryV2.updateAvailableClaim(true);
        vm.prank(user);
        factoryV2.mintNFT(30, NFT_PRICE);

        uint256 beforeBalance = hapToken.balanceOf(address(this));
        factoryV2.claimFee(NFT_PRICE);
        assertEq(hapToken.balanceOf(address(this)), beforeBalance + NFT_PRICE);
        assertEq(hapToken.balanceOf(address(factoryV2)), 0);
    }
}
