// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {HeroArenaFrames} from "./HeroArenaFrames.sol";

contract HeroArenaFramesTest is Test {
    HeroArenaFrames frames;

    address ownerAddr;
    address user1;
    address user2;

    function setUp() public {
        ownerAddr = address(this);
        user1     = makeAddr("user1");
        user2     = makeAddr("user2");

        frames = new HeroArenaFrames();
        frames.setFrameNameAndCreatedTimestamp(0, "frame0");
        frames.setFrameNameAndCreatedTimestamp(1, "frame1");
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
        assertEq(frames.name(), "HA Frames");
    }

    function test_Symbol() public view {
        assertEq(frames.symbol(), "HAF");
    }

    function test_TokenURI_ReturnsBaseUriPlusTokenId() public {
        frames.mint(user1, 0);
        assertEq(frames.tokenURI(1), "frames/1");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsOwner() public view {
        assertEq(Ownable(address(frames)).owner(), ownerAddr);
    }

    function test_Constructor_TotalSupplyZero() public view {
        assertEq(frames.totalSupply(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // supportsInterface
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SupportsInterface_ERC721() public view {
        assertTrue(frames.supportsInterface(type(IERC721).interfaceId));
    }

    function test_SupportsInterface_ERC721Enumerable() public view {
        assertTrue(frames.supportsInterface(type(IERC721Enumerable).interfaceId));
    }

    function test_SupportsInterface_ERC165() public view {
        assertTrue(frames.supportsInterface(type(IERC165).interfaceId));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // mint
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Mint_TokenIdStartsAtOne() public {
        uint256 tokenId = frames.mint(user1, 0);
        assertEq(tokenId, 1);
    }

    function test_Mint_SequentialTokenIds() public {
        assertEq(frames.mint(user1, 0), 1);
        assertEq(frames.mint(user1, 1), 2);
    }

    function test_Mint_SetsOwner() public {
        uint256 tokenId = frames.mint(user1, 0);
        assertEq(frames.ownerOf(tokenId), user1);
    }

    function test_Mint_IncrementsFrameCount() public {
        frames.mint(user1, 0);
        frames.mint(user2, 0);
        assertEq(frames.frameCount(0), 2);
    }

    function test_Mint_DifferentFrameIdsCounted() public {
        frames.mint(user1, 0);
        frames.mint(user1, 1);
        assertEq(frames.frameCount(0), 1);
        assertEq(frames.frameCount(1), 1);
    }

    function test_Mint_IncrementsTotalSupply() public {
        frames.mint(user1, 0);
        frames.mint(user2, 1);
        assertEq(frames.totalSupply(), 2);
    }

    function test_Mint_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        frames.mint(user1, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setFrameNameAndCreatedTimestamp
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetFrameName_SetsName() public {
        frames.setFrameNameAndCreatedTimestamp(5, "frameSpecial");
        (string[] memory names, ) = frames.getFrameNameAndCreatedTimestampBatch(_ids1(5));
        assertEq(names[0], "frameSpecial");
    }

    function test_SetFrameName_SetsTimestamp() public {
        vm.warp(12345);
        frames.setFrameNameAndCreatedTimestamp(5, "frameSpecial");
        (, uint256[] memory timestamps) = frames.getFrameNameAndCreatedTimestampBatch(_ids1(5));
        assertEq(timestamps[0], 12345);
    }

    function test_SetFrameName_CanOverwrite() public {
        frames.setFrameNameAndCreatedTimestamp(0, "frame0_updated");
        (string[] memory names, ) = frames.getFrameNameAndCreatedTimestampBatch(_ids1(0));
        assertEq(names[0], "frame0_updated");
    }

    function test_SetFrameName_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        frames.setFrameNameAndCreatedTimestamp(5, "frameSpecial");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // burn
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Burn_DecrementsFrameCount() public {
        frames.mint(user1, 0);
        uint256 tokenId = frames.mint(user1, 0);
        frames.burn(tokenId);
        assertEq(frames.frameCount(0), 1);
    }

    function test_Burn_IncrementsFrameBurnCount() public {
        uint256 tokenId = frames.mint(user1, 0);
        frames.burn(tokenId);
        assertEq(frames.frameBurnCount(0), 1);
    }

    function test_Burn_DecrementsTotalSupply() public {
        frames.mint(user1, 0);
        uint256 tokenId = frames.mint(user1, 0);
        frames.burn(tokenId);
        assertEq(frames.totalSupply(), 1);
    }

    function test_Burn_TokenNoLongerExists() public {
        uint256 tokenId = frames.mint(user1, 0);
        frames.burn(tokenId);
        vm.expectRevert();
        frames.ownerOf(tokenId);
    }

    function test_Burn_ClearsFrameIdMapping() public {
        uint256 tokenId = frames.mint(user1, 2);
        frames.burn(tokenId);
        uint8[] memory result = frames.getFrameIdBatch(_tokenIds1(tokenId));
        assertEq(result[0], 0);
    }

    function test_Burn_MultipleBurns() public {
        uint256 id1 = frames.mint(user1, 0);
        uint256 id2 = frames.mint(user2, 0);
        frames.burn(id1);
        frames.burn(id2);
        assertEq(frames.frameCount(0), 0);
        assertEq(frames.frameBurnCount(0), 2);
        assertEq(frames.totalSupply(), 0);
    }

    function test_Burn_RevertsIfNotOwner() public {
        uint256 tokenId = frames.mint(user1, 0);
        vm.prank(user1);
        vm.expectRevert();
        frames.burn(tokenId);
    }

    function test_Burn_RevertsIfTokenNotExist() public {
        vm.expectRevert();
        frames.burn(999);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getFrameIdBatch
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetFrameIdBatch_Single() public {
        uint256 tokenId = frames.mint(user1, 2);
        uint8[] memory result = frames.getFrameIdBatch(_tokenIds1(tokenId));
        assertEq(result[0], 2);
    }

    function test_GetFrameIdBatch_Multiple() public {
        uint256 id1 = frames.mint(user1, 0);
        uint256 id2 = frames.mint(user2, 1);
        uint8[] memory result = frames.getFrameIdBatch(_tokenIds2(id1, id2));
        assertEq(result[0], 0);
        assertEq(result[1], 1);
    }

    function test_GetFrameIdBatch_EmptyInput() public view {
        uint256[] memory empty = new uint256[](0);
        assertEq(frames.getFrameIdBatch(empty).length, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getFrameNameAndCreatedTimestampBatch
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetNameBatch_ReturnsCorrectData() public view {
        (string[] memory names, uint256[] memory timestamps) =
            frames.getFrameNameAndCreatedTimestampBatch(_ids2(0, 1));
        assertEq(names[0], "frame0");
        assertEq(names[1], "frame1");
        assertEq(timestamps.length, 2);
    }

    function test_GetNameBatch_ReturnsEmptyStringForUnsetId() public view {
        (string[] memory names, ) = frames.getFrameNameAndCreatedTimestampBatch(_ids1(99));
        assertEq(names[0], "");
    }

    function test_GetNameBatch_RevertsIfLengthExceeds1000() public {
        uint8[] memory ids = new uint8[](1001);
        vm.expectRevert("Group size must be < 1001");
        frames.getFrameNameAndCreatedTimestampBatch(ids);
    }

    function test_GetNameBatch_AllowsExactly1000() public view {
        frames.getFrameNameAndCreatedTimestampBatch(new uint8[](1000));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getTokensByOwner
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetTokensByOwner_ReturnsAllTokenIds() public {
        uint256 id1 = frames.mint(user1, 0);
        uint256 id2 = frames.mint(user1, 1);
        frames.mint(user2, 0);
        uint256[] memory tokens = frames.getTokensByOwner(user1);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], id1);
        assertEq(tokens[1], id2);
    }

    function test_GetTokensByOwner_ReturnsEmptyForNoTokens() public view {
        assertEq(frames.getTokensByOwner(user1).length, 0);
    }

    function test_GetTokensByOwner_UpdatesAfterBurn() public {
        uint256 id1 = frames.mint(user1, 0);
        uint256 id2 = frames.mint(user1, 1);
        frames.burn(id1);
        uint256[] memory tokens = frames.getTokensByOwner(user1);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], id2);
    }

    function test_GetTokensByOwner_UpdatesAfterTransfer() public {
        uint256 tokenId = frames.mint(user1, 0);
        vm.prank(user1);
        frames.transferFrom(user1, user2, tokenId);
        assertEq(frames.getTokensByOwner(user1).length, 0);
        assertEq(frames.getTokensByOwner(user2).length, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC721Enumerable
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TokenByIndex_ReturnsCorrectToken() public {
        uint256 tokenId = frames.mint(user1, 0);
        assertEq(frames.tokenByIndex(0), tokenId);
    }

    function test_TokenOfOwnerByIndex_ReturnsCorrectToken() public {
        uint256 tokenId = frames.mint(user1, 0);
        assertEq(frames.tokenOfOwnerByIndex(user1, 0), tokenId);
    }

    receive() external payable {}
}
