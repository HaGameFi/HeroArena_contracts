// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {HeroArenaAvatars} from "./HeroArenaAvatars.sol";

contract HeroArenaAvatarsTest is Test {
    HeroArenaAvatars avatars;

    address owner;
    address user1;
    address user2;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        avatars = new HeroArenaAvatars();
        avatars.setAvatarNameAndCreatedTimestamp(0, "Knight_v0");
        avatars.setAvatarNameAndCreatedTimestamp(1, "Mage_v1");
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _ids1(uint8 a) internal pure returns (uint8[] memory r) {
        r = new uint8[](1); r[0] = a;
    }

    function _ids2(uint8 a, uint8 b) internal pure returns (uint8[] memory r) {
        r = new uint8[](2); r[0] = a; r[1] = b;
    }

    function _tokenIds1(uint256 a) internal pure returns (uint256[] memory r) {
        r = new uint256[](1); r[0] = a;
    }

    function _tokenIds2(uint256 a, uint256 b) internal pure returns (uint256[] memory r) {
        r = new uint256[](2); r[0] = a; r[1] = b;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC721 metadata
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Name() public view {
        assertEq(avatars.name(), "HA Avatars");
    }

    function test_Symbol() public view {
        assertEq(avatars.symbol(), "HAA");
    }

    function test_TokenURI_ReturnsBaseUriPlusTokenId() public {
        avatars.mint(user1, 0);
        assertEq(avatars.tokenURI(1), "avatars/1");
    }

    function test_TokenURI_MultipleTokens() public {
        avatars.mint(user1, 0);
        avatars.mint(user1, 1);
        assertEq(avatars.tokenURI(1), "avatars/1");
        assertEq(avatars.tokenURI(2), "avatars/2");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // supportsInterface
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SupportsInterface_ERC721() public view {
        assertTrue(avatars.supportsInterface(type(IERC721).interfaceId));
    }

    function test_SupportsInterface_ERC721Enumerable() public view {
        assertTrue(avatars.supportsInterface(type(IERC721Enumerable).interfaceId));
    }

    function test_SupportsInterface_ERC165() public view {
        assertTrue(avatars.supportsInterface(type(IERC165).interfaceId));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // mint
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Mint_TokenIdStartsAtOne() public {
        uint256 tokenId = avatars.mint(user1, 0);
        assertEq(tokenId, 1);
    }

    function test_Mint_SequentialTokenIds() public {
        uint256 id1 = avatars.mint(user1, 0);
        uint256 id2 = avatars.mint(user1, 1);
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_Mint_SetsOwner() public {
        uint256 tokenId = avatars.mint(user1, 0);
        assertEq(avatars.ownerOf(tokenId), user1);
    }

    function test_Mint_IncrementsAvatarCount() public {
        avatars.mint(user1, 0);
        avatars.mint(user2, 0);
        assertEq(avatars.avatarCount(0), 2);
    }

    function test_Mint_DifferentAvatarIdsCounted() public {
        avatars.mint(user1, 0);
        avatars.mint(user1, 1);
        assertEq(avatars.avatarCount(0), 1);
        assertEq(avatars.avatarCount(1), 1);
    }

    function test_Mint_IncrementsTotalSupply() public {
        avatars.mint(user1, 0);
        avatars.mint(user2, 1);
        assertEq(avatars.totalSupply(), 2);
    }

    function test_Mint_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        avatars.mint(user1, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setAvatarNameAndCreatedTimestamp
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetAvatarName_SetsName() public {
        avatars.setAvatarNameAndCreatedTimestamp(5, "Wizard_v1");
        (string[] memory names, ) = avatars.getAvatarNameAndCreatedTimestampBatch(_ids1(5));
        assertEq(names[0], "Wizard_v1");
    }

    function test_SetAvatarName_SetsTimestamp() public {
        vm.warp(12345);
        avatars.setAvatarNameAndCreatedTimestamp(5, "Wizard_v1");
        (, uint256[] memory timestamps) = avatars.getAvatarNameAndCreatedTimestampBatch(_ids1(5));
        assertEq(timestamps[0], 12345);
    }

    function test_SetAvatarName_CanOverwrite() public {
        avatars.setAvatarNameAndCreatedTimestamp(0, "Knight_v0_updated");
        (string[] memory names, ) = avatars.getAvatarNameAndCreatedTimestampBatch(_ids1(0));
        assertEq(names[0], "Knight_v0_updated");
    }

    function test_SetAvatarName_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        avatars.setAvatarNameAndCreatedTimestamp(5, "Wizard_v1");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // burn
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Burn_DecrementsAvatarCount() public {
        avatars.mint(user1, 0);
        uint256 tokenId = avatars.mint(user1, 0);
        avatars.burn(tokenId);
        assertEq(avatars.avatarCount(0), 1);
    }

    function test_Burn_IncrementsAvatarBurnCount() public {
        uint256 tokenId = avatars.mint(user1, 0);
        avatars.burn(tokenId);
        assertEq(avatars.avatarBurnCount(0), 1);
    }

    function test_Burn_DecrementsTotalSupply() public {
        avatars.mint(user1, 0);
        uint256 tokenId = avatars.mint(user1, 0);
        avatars.burn(tokenId);
        assertEq(avatars.totalSupply(), 1);
    }

    function test_Burn_TokenNoLongerExists() public {
        uint256 tokenId = avatars.mint(user1, 0);
        avatars.burn(tokenId);
        vm.expectRevert();
        avatars.ownerOf(tokenId);
    }

    function test_Burn_ClearsAvatarIdMapping() public {
        uint256 tokenId = avatars.mint(user1, 3);
        avatars.burn(tokenId);
        uint8[] memory result = avatars.getAvatarIdBatch(_tokenIds1(tokenId));
        assertEq(result[0], 0);
    }

    function test_Burn_MultipleBurns() public {
        uint256 tokenId1 = avatars.mint(user1, 0);
        uint256 tokenId2 = avatars.mint(user2, 0);
        avatars.burn(tokenId1);
        avatars.burn(tokenId2);
        assertEq(avatars.avatarCount(0), 0);
        assertEq(avatars.avatarBurnCount(0), 2);
        assertEq(avatars.totalSupply(), 0);
    }

    function test_Burn_RevertsIfNotOwner() public {
        uint256 tokenId = avatars.mint(user1, 0);
        vm.prank(user1);
        vm.expectRevert();
        avatars.burn(tokenId);
    }

    function test_Burn_RevertsIfTokenNotExist() public {
        vm.expectRevert();
        avatars.burn(999);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getAvatarIdBatch
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetAvatarIdBatch_Single() public {
        uint256 tokenId = avatars.mint(user1, 3);
        uint8[] memory result = avatars.getAvatarIdBatch(_tokenIds1(tokenId));
        assertEq(result.length, 1);
        assertEq(result[0], 3);
    }

    function test_GetAvatarIdBatch_Multiple() public {
        uint256 tokenId1 = avatars.mint(user1, 1);
        uint256 tokenId2 = avatars.mint(user2, 5);
        uint8[] memory result = avatars.getAvatarIdBatch(_tokenIds2(tokenId1, tokenId2));
        assertEq(result.length, 2);
        assertEq(result[0], 1);
        assertEq(result[1], 5);
    }

    function test_GetAvatarIdBatch_EmptyInput() public view {
        uint256[] memory empty = new uint256[](0);
        uint8[] memory result = avatars.getAvatarIdBatch(empty);
        assertEq(result.length, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getAvatarNameAndCreatedTimestampBatch
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetNameBatch_ReturnsCorrectData() public view {
        (string[] memory names, uint256[] memory timestamps) =
            avatars.getAvatarNameAndCreatedTimestampBatch(_ids2(0, 1));
        assertEq(names[0], "Knight_v0");
        assertEq(names[1], "Mage_v1");
        assertEq(timestamps.length, 2);
    }

    function test_GetNameBatch_ReturnsEmptyStringForUnsetId() public view {
        (string[] memory names, ) = avatars.getAvatarNameAndCreatedTimestampBatch(_ids1(99));
        assertEq(names[0], "");
    }

    function test_GetNameBatch_RevertsIfLengthExceeds1000() public {
        uint8[] memory ids = new uint8[](1001);
        vm.expectRevert("Group size must be < 1001");
        avatars.getAvatarNameAndCreatedTimestampBatch(ids);
    }

    function test_GetNameBatch_AllowsExactly1000() public view {
        uint8[] memory ids = new uint8[](1000);
        avatars.getAvatarNameAndCreatedTimestampBatch(ids);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getTokensByOwner
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetTokensByOwner_ReturnsAllTokenIds() public {
        uint256 tokenId1 = avatars.mint(user1, 0);
        uint256 tokenId2 = avatars.mint(user1, 1);
        avatars.mint(user2, 0);

        uint256[] memory tokens = avatars.getTokensByOwner(user1);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], tokenId1);
        assertEq(tokens[1], tokenId2);
    }

    function test_GetTokensByOwner_ReturnsEmptyForNoTokens() public view {
        uint256[] memory tokens = avatars.getTokensByOwner(user1);
        assertEq(tokens.length, 0);
    }

    function test_GetTokensByOwner_UpdatesAfterBurn() public {
        uint256 tokenId1 = avatars.mint(user1, 0);
        uint256 tokenId2 = avatars.mint(user1, 1);
        avatars.burn(tokenId1);

        uint256[] memory tokens = avatars.getTokensByOwner(user1);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenId2);
    }

    function test_GetTokensByOwner_UpdatesAfterTransfer() public {
        uint256 tokenId = avatars.mint(user1, 0);
        vm.prank(user1);
        avatars.transferFrom(user1, user2, tokenId);

        assertEq(avatars.getTokensByOwner(user1).length, 0);
        assertEq(avatars.getTokensByOwner(user2).length, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC721Enumerable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TotalSupply_ZeroInitially() public view {
        assertEq(avatars.totalSupply(), 0);
    }

    function test_TokenByIndex_ReturnsCorrectToken() public {
        uint256 tokenId = avatars.mint(user1, 0);
        assertEq(avatars.tokenByIndex(0), tokenId);
    }

    function test_TokenOfOwnerByIndex_ReturnsCorrectToken() public {
        uint256 tokenId = avatars.mint(user1, 0);
        assertEq(avatars.tokenOfOwnerByIndex(user1, 0), tokenId);
    }

    receive() external payable {}
}
