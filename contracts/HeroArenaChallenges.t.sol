// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {HeroArenaChallenges} from "./HeroArenaChallenges.sol";

contract HeroArenaChallengesTest is Test {
    HeroArenaChallenges challenges;

    address admin;
    address challengeAdmin;
    address user1;
    address user2;
    address stranger;

    bytes32 constant CHALLENGE_ADMIN_ROLE = keccak256("CHALLENGE_ADMIN_ROLE");

    function setUp() public {
        admin          = address(this);
        challengeAdmin = makeAddr("challengeAdmin");
        user1          = makeAddr("user1");
        user2          = makeAddr("user2");
        stranger       = makeAddr("stranger");

        challenges = new HeroArenaChallenges();

        // Grant CHALLENGE_ADMIN_ROLE so we can set levels and submit
        challenges.grantRole(CHALLENGE_ADMIN_ROLE, challengeAdmin);

        vm.prank(challengeAdmin);
        challenges.setLevelNameAndRewardPoints(0, "Ladder Climb", 5);
        vm.prank(challengeAdmin);
        challenges.setLevelNameAndRewardPoints(1, "Knight Fight", 10);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _ids1(uint8 a) internal pure returns (uint8[] memory r) {
        r = new uint8[](1); r[0] = a;
    }

    function _challengeIds1(uint256 a) internal pure returns (uint256[] memory r) {
        r = new uint256[](1); r[0] = a;
    }

    function _challengeIds2(uint256 a, uint256 b) internal pure returns (uint256[] memory r) {
        r = new uint256[](2); r[0] = a; r[1] = b;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_GrantsDefaultAdminRoleToDeployer() public view {
        assertTrue(challenges.hasRole(challenges.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Constructor_DeployerIsNotChallengeAdminByDefault() public view {
        assertFalse(challenges.hasRole(CHALLENGE_ADMIN_ROLE, admin));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setLevelNameAndRewardPoints
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetLevel_SetsNameAndPoints() public view {
        (string[] memory names, uint256[] memory points) =
            challenges.getLevelNameAndPointsBatch(_ids1(0));
        assertEq(names[0], "Ladder Climb");
        assertEq(points[0], 5);
    }

    function test_SetLevel_CanOverwrite() public {
        vm.prank(challengeAdmin);
        challenges.setLevelNameAndRewardPoints(0, "Ladder Climb v2", 99);
        (string[] memory names, uint256[] memory points) =
            challenges.getLevelNameAndPointsBatch(_ids1(0));
        assertEq(names[0], "Ladder Climb v2");
        assertEq(points[0], 99);
    }

    function test_SetLevel_RevertsIfNotChallengeAdmin() public {
        vm.prank(stranger);
        vm.expectRevert("Not a challenge admin role");
        challenges.setLevelNameAndRewardPoints(0, "Hack", 9999);
    }

    function test_SetLevel_AdminRoleAloneCannotSet() public {
        // DEFAULT_ADMIN_ROLE does not imply CHALLENGE_ADMIN_ROLE
        vm.expectRevert("Not a challenge admin role");
        challenges.setLevelNameAndRewardPoints(2, "New Level", 20);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // submit
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Submit_ReturnsSequentialChallengeId() public {
        vm.prank(challengeAdmin);
        uint256 id1 = challenges.submit(user1, 0);
        vm.prank(challengeAdmin);
        uint256 id2 = challenges.submit(user2, 0);
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_Submit_IncrementsLvCount() public {
        vm.prank(challengeAdmin);
        challenges.submit(user1, 0);
        vm.prank(challengeAdmin);
        challenges.submit(user2, 0);
        assertEq(challenges.lvCount(0), 2);
    }

    function test_Submit_SetsSubmitStatus() public {
        vm.prank(challengeAdmin);
        challenges.submit(user1, 0);
        assertTrue(challenges.getSubmitStatus(user1, 0));
    }

    function test_Submit_DifferentUsersCanSubmitSameLevel() public {
        vm.prank(challengeAdmin);
        challenges.submit(user1, 0);
        vm.prank(challengeAdmin);
        challenges.submit(user2, 0);
        assertTrue(challenges.getSubmitStatus(user1, 0));
        assertTrue(challenges.getSubmitStatus(user2, 0));
    }

    function test_Submit_SameUserCanSubmitDifferentLevels() public {
        vm.prank(challengeAdmin);
        challenges.submit(user1, 0);
        vm.prank(challengeAdmin);
        challenges.submit(user1, 1);
        assertTrue(challenges.getSubmitStatus(user1, 0));
        assertTrue(challenges.getSubmitStatus(user1, 1));
    }

    function test_Submit_RevertsOnDuplicateSubmit() public {
        vm.prank(challengeAdmin);
        challenges.submit(user1, 0);
        vm.prank(challengeAdmin);
        vm.expectRevert("User can only submit once");
        challenges.submit(user1, 0);
    }

    function test_Submit_RevertsIfNotChallengeAdmin() public {
        vm.prank(stranger);
        vm.expectRevert("Not a challenge admin role");
        challenges.submit(user1, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHALLENGE_ADMIN_ROLE management
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GrantRole_AllowsNewChallengeAdmin() public {
        address newAdmin = makeAddr("newAdmin");
        challenges.grantRole(CHALLENGE_ADMIN_ROLE, newAdmin);
        assertTrue(challenges.hasRole(CHALLENGE_ADMIN_ROLE, newAdmin));
    }

    function test_RevokeRole_BlocksRevokedAdmin() public {
        challenges.revokeRole(CHALLENGE_ADMIN_ROLE, challengeAdmin);
        vm.prank(challengeAdmin);
        vm.expectRevert("Not a challenge admin role");
        challenges.submit(user1, 0);
    }

    function test_GrantRole_RevertsIfNotDefaultAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        challenges.grantRole(CHALLENGE_ADMIN_ROLE, stranger);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getLevelRewardPoints
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetLevelRewardPoints_ReturnsCorrectValue() public view {
        assertEq(challenges.getLevelRewardPoints(0), 5);
        assertEq(challenges.getLevelRewardPoints(1), 10);
    }

    function test_GetLevelRewardPoints_ReturnsZeroForUnsetLevel() public view {
        assertEq(challenges.getLevelRewardPoints(99), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getSubmitStatus
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetSubmitStatus_FalseBeforeSubmit() public view {
        assertFalse(challenges.getSubmitStatus(user1, 0));
    }

    function test_GetSubmitStatus_TrueAfterSubmit() public {
        vm.prank(challengeAdmin);
        challenges.submit(user1, 0);
        assertTrue(challenges.getSubmitStatus(user1, 0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getLevelIdBatch
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetLevelIdBatch_Single() public {
        vm.prank(challengeAdmin);
        uint256 id = challenges.submit(user1, 1);
        uint8[] memory result = challenges.getLevelIdBatch(_challengeIds1(id));
        assertEq(result[0], 1);
    }

    function test_GetLevelIdBatch_Multiple() public {
        vm.prank(challengeAdmin);
        uint256 id1 = challenges.submit(user1, 0);
        vm.prank(challengeAdmin);
        uint256 id2 = challenges.submit(user2, 1);
        uint8[] memory result = challenges.getLevelIdBatch(_challengeIds2(id1, id2));
        assertEq(result[0], 0);
        assertEq(result[1], 1);
    }

    function test_GetLevelIdBatch_EmptyInput() public view {
        uint256[] memory empty = new uint256[](0);
        uint8[] memory result = challenges.getLevelIdBatch(empty);
        assertEq(result.length, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getLevelNameAndPointsBatch
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetNameBatch_ReturnsCorrectData() public view {
        uint8[] memory ids = new uint8[](2);
        ids[0] = 0; ids[1] = 1;
        (string[] memory names, uint256[] memory points) =
            challenges.getLevelNameAndPointsBatch(ids);
        assertEq(names[0], "Ladder Climb");
        assertEq(names[1], "Knight Fight");
        assertEq(points[0], 5);
        assertEq(points[1], 10);
    }

    function test_GetNameBatch_ReturnsEmptyForUnsetId() public view {
        (string[] memory names, uint256[] memory points) =
            challenges.getLevelNameAndPointsBatch(_ids1(99));
        assertEq(names[0], "");
        assertEq(points[0], 0);
    }

    function test_GetNameBatch_RevertsIfExceeds1000() public {
        uint8[] memory ids = new uint8[](1001);
        vm.expectRevert("Group size must be < 1001");
        challenges.getLevelNameAndPointsBatch(ids);
    }

    function test_GetNameBatch_AllowsExactly1000() public view {
        uint8[] memory ids = new uint8[](1000);
        challenges.getLevelNameAndPointsBatch(ids);
    }

    receive() external payable {}
}
