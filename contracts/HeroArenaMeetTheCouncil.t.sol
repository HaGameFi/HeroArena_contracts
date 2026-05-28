// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaChallenges} from "./HeroArenaChallenges.sol";
import {HeroArenaMeetTheCouncil} from "./HeroArenaMeetTheCouncil.sol";
import {HeroArenaProfile} from "./HeroArenaProfile.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMeetTheCouncilTest is Test {
    HeroArenaChallenges   challenges;
    HeroArenaMeetTheCouncil council;
    HeroArenaProfile      profile;
    MockERC20             hapToken;

    address owner;
    address operator;
    address user1;
    address user2;
    address stranger;

    bytes32 constant OPERATOR_ROLE       = keccak256("OPERATOR_ROLE");
    bytes32 constant POINT_ROLE          = keccak256("POINT_ROLE");
    bytes32 constant CHALLENGE_ADMIN_ROLE = keccak256("CHALLENGE_ADMIN_ROLE");

    function setUp() public {
        owner    = address(this);
        operator = makeAddr("operator");
        user1    = makeAddr("user1");
        user2    = makeAddr("user2");
        stranger = makeAddr("stranger");

        hapToken   = new MockERC20();
        profile    = new HeroArenaProfile(IERC20(address(hapToken)), 0, 0);
        challenges = new HeroArenaChallenges();
        council    = new HeroArenaMeetTheCouncil(challenges, profile);

        // Grant council CHALLENGE_ADMIN_ROLE on Challenges, then init levels
        challenges.grantRole(CHALLENGE_ADMIN_ROLE, address(council));
        council.initLevels();

        // Grant council POINT_ROLE on Profile so it can increase points
        bytes32 pointRole = profile.POINT_ROLE();
        profile.grantRole(pointRole, address(council));

        // Grant operator role
        council.grantRole(OPERATOR_ROLE, operator);

        // Enable submit
        council.updateAvailableSubmit(true);

        // Register user1 in profile (required for increaseUserPoints)
        profile.addTeam("Council", "The Council team");
        vm.prank(user1);
        profile.createProfile(1, type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsContracts() public view {
        assertEq(address(council.HeroArenaChallengesSC()), address(challenges));
        assertEq(address(council.HeroArenaProfileSC()), address(profile));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(council.owner(), owner);
    }

    function test_Constructor_GrantsDefaultAdminRole() public view {
        assertTrue(council.hasRole(council.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_Constructor_SubmitDisabledByDefault() public {
        // Deploy a fresh council without enabling submit
        HeroArenaChallenges c2 = new HeroArenaChallenges();
        HeroArenaMeetTheCouncil council2 = new HeroArenaMeetTheCouncil(c2, profile);
        assertFalse(council2.availableSubmit());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // initLevels
    // ═══════════════════════════════════════════════════════════════════════════

    function test_InitLevels_SetsMinMaxLevelId() public view {
        assertEq(council.submitMinLevelId(), 0);
        assertEq(council.submitMaxLevelId(), 6);
    }

    function test_InitLevels_SetsLevelNamesAndPoints() public view {
        (string[] memory names, uint256[] memory points) =
            challenges.getLevelNameAndPointsBatch(_allLevelIds());
        assertEq(names[0], "Ladder Climb");  assertEq(points[0], 5);
        assertEq(names[1], "Knight Fight");  assertEq(points[1], 5);
        assertEq(names[2], "Warrior Bath");  assertEq(points[2], 10);
        assertEq(names[3], "Firestorm");     assertEq(points[3], 10);
        assertEq(names[4], "Switcheroo");    assertEq(points[4], 15);
        assertEq(names[5], "Wizard Dance");  assertEq(points[5], 15);
        assertEq(names[6], "Cluster Bomb");  assertEq(points[6], 20);
    }

    function test_InitLevels_RevertsIfCalledTwice() public {
        vm.expectRevert("Already initialized");
        council.initLevels();
    }

    function test_InitLevels_RevertsIfNotOwner() public {
        HeroArenaChallenges c2 = new HeroArenaChallenges();
        HeroArenaMeetTheCouncil council2 = new HeroArenaMeetTheCouncil(c2, profile);
        c2.grantRole(CHALLENGE_ADMIN_ROLE, address(council2));
        vm.prank(stranger);
        vm.expectRevert();
        council2.initLevels();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAvailableSubmit
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAvailableSubmit_TogglesFlag() public {
        council.updateAvailableSubmit(false);
        assertFalse(council.availableSubmit());
        council.updateAvailableSubmit(true);
        assertTrue(council.availableSubmit());
    }

    function test_UpdateAvailableSubmit_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaMeetTheCouncil.AvailableSubmitUpdated(owner, false);
        council.updateAvailableSubmit(false);
    }

    function test_UpdateAvailableSubmit_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        council.updateAvailableSubmit(false);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // submitLv
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SubmitLv_UpdatesChallengesLvCount() public {
        vm.prank(operator);
        council.submitLv(user1, 0);
        assertEq(challenges.lvCount(0), 1);
    }

    function test_SubmitLv_SetsSubmitStatus() public {
        vm.prank(operator);
        council.submitLv(user1, 0);
        assertTrue(challenges.getSubmitStatus(user1, 0));
    }

    function test_SubmitLv_EmitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit HeroArenaMeetTheCouncil.LevelSubmited(user1, 1, 0, 5);
        vm.prank(operator);
        council.submitLv(user1, 0);
    }

    function test_SubmitLv_AllLevelIds() public {
        // Register user2 as well
        vm.prank(user2);
        profile.createProfile(1, type(uint256).max);

        for (uint8 lvId = 0; lvId <= 6; lvId++) {
            vm.prank(operator);
            council.submitLv(user1, lvId);
            assertTrue(challenges.getSubmitStatus(user1, lvId));
        }
    }

    function test_SubmitLv_RevertsWhenDisabled() public {
        council.updateAvailableSubmit(false);
        vm.prank(operator);
        vm.expectRevert("Cannot submit");
        council.submitLv(user1, 0);
    }

    function test_SubmitLv_RevertsOnInvalidLevelId() public {
        vm.prank(operator);
        vm.expectRevert("Input levelId unavailable");
        council.submitLv(user1, 7);
    }

    function test_SubmitLv_RevertsOnDuplicateSubmit() public {
        vm.prank(operator);
        council.submitLv(user1, 0);
        vm.prank(operator);
        vm.expectRevert("User can only submit once");
        council.submitLv(user1, 0);
    }

    function test_SubmitLv_RevertsIfNotOperator() public {
        vm.prank(stranger);
        vm.expectRevert("Not an operator role");
        council.submitLv(user1, 0);
    }

    function test_SubmitLv_OwnerIsNotOperatorByDefault() public {
        vm.prank(owner);
        vm.expectRevert("Not an operator role");
        council.submitLv(user1, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OPERATOR_ROLE management
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GrantRole_AllowsNewOperator() public {
        address newOp = makeAddr("newOp");
        council.grantRole(OPERATOR_ROLE, newOp);
        assertTrue(council.hasRole(OPERATOR_ROLE, newOp));
    }

    function test_RevokeRole_BlocksRevokedOperator() public {
        council.revokeRole(OPERATOR_ROLE, operator);

        vm.prank(operator);
        vm.expectRevert("Not an operator role");
        council.submitLv(user1, 0);
    }

    function test_GrantRole_RevertsIfNotAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        council.grantRole(OPERATOR_ROLE, stranger);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _allLevelIds() internal pure returns (uint8[] memory ids) {
        ids = new uint8[](7);
        for (uint8 i = 0; i < 7; i++) ids[i] = i;
    }

    receive() external payable {}
}
