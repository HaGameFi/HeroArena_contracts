// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaChallenges} from "./HeroArenaChallenges.sol";
import {HeroArenaMeetTheDarkElf} from "./HeroArenaMeetTheDarkElf.sol";
import {HeroArenaProfile} from "./HeroArenaProfile.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaMeetTheDarkElfTest is Test {
    HeroArenaChallenges challenges;
    HeroArenaMeetTheDarkElf darkElf;
    HeroArenaProfile profile;

    address operator = makeAddr("operator");
    address user = makeAddr("user");
    address stranger = makeAddr("stranger");

    bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 constant CHALLENGE_ADMIN_ROLE = keccak256("CHALLENGE_ADMIN_ROLE");

    function setUp() public {
        MockERC20 hapToken = new MockERC20();
        profile = new HeroArenaProfile(IERC20(address(hapToken)), 0, 0);
        challenges = new HeroArenaChallenges();
        darkElf = new HeroArenaMeetTheDarkElf(challenges, profile);

        challenges.grantRole(CHALLENGE_ADMIN_ROLE, address(darkElf));
        darkElf.initLevels();
        profile.grantRole(profile.POINT_ROLE(), address(darkElf));
        darkElf.grantRole(OPERATOR_ROLE, operator);
        darkElf.updateAvailableSubmit(true);

        profile.addTeam("DarkElf", "Dark Elf team");
        vm.prank(user);
        profile.createProfile(1, type(uint256).max);
    }

    function test_ConstructorAndInitialization() public view {
        assertEq(address(darkElf.HeroArenaChallengesSC()), address(challenges));
        assertEq(address(darkElf.HeroArenaProfileSC()), address(profile));
        assertEq(darkElf.owner(), address(this));
        assertTrue(darkElf.hasRole(darkElf.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(darkElf.submitMinLevelId(), 8);
        assertEq(darkElf.submitMaxLevelId(), 14);
    }

    function test_InitLevelsSetsNamesAndRewards() public view {
        uint8[] memory ids = new uint8[](7);
        for (uint8 i; i < 7; ++i) ids[i] = i + 8;
        (string[] memory names, uint256[] memory points) = challenges.getLevelNameAndPointsBatch(ids);
        assertEq(names[0], "Pull Me Around"); assertEq(points[0], 10);
        assertEq(names[1], "Nom Nom Nom"); assertEq(points[1], 10);
        assertEq(names[2], "Knight Crossing"); assertEq(points[2], 15);
        assertEq(names[3], "Hard Target"); assertEq(points[3], 20);
        assertEq(names[4], "Choices, Choices"); assertEq(points[4], 25);
        assertEq(names[5], "Three Vs. Thress"); assertEq(points[5], 15);
        assertEq(names[6], "Let's Be Bad"); assertEq(points[6], 25);
    }

    function test_InitLevelsCannotRunTwiceOrByStranger() public {
        vm.expectRevert("Already initialized");
        darkElf.initLevels();
        vm.prank(stranger);
        vm.expectRevert();
        darkElf.initLevels();
    }

    function test_SubmitUpdatesChallengeAndProfile() public {
        vm.expectEmit(true, true, true, true);
        emit HeroArenaMeetTheDarkElf.LevelSubmited(user, 1, 8, 10);
        vm.prank(operator);
        darkElf.submitLv(user, 8);

        assertEq(challenges.lvCount(8), 1);
        assertTrue(challenges.getSubmitStatus(user, 8));
        (, uint256 points,,,) = profile.getUserProfile(user);
        assertEq(points, 10);
    }

    function test_SubmitAllValidLevels() public {
        for (uint8 level = 8; level <= 14; ++level) {
            vm.prank(operator);
            darkElf.submitLv(user, level);
            assertTrue(challenges.getSubmitStatus(user, level));
        }
        (, uint256 points,,,) = profile.getUserProfile(user);
        assertEq(points, 120);
    }

    function test_SubmitRejectsDisabledInvalidDuplicateAndUnauthorized() public {
        darkElf.updateAvailableSubmit(false);
        vm.prank(operator);
        vm.expectRevert("Cannot submit");
        darkElf.submitLv(user, 8);

        darkElf.updateAvailableSubmit(true);
        vm.prank(operator);
        vm.expectRevert("Input levelId unavailable");
        darkElf.submitLv(user, 7);
        vm.prank(operator);
        vm.expectRevert("Input levelId unavailable");
        darkElf.submitLv(user, 15);

        vm.prank(operator);
        darkElf.submitLv(user, 8);
        vm.prank(operator);
        vm.expectRevert("User can only submit once");
        darkElf.submitLv(user, 8);

        vm.prank(stranger);
        vm.expectRevert("Not an operator role");
        darkElf.submitLv(user, 9);
    }

    function test_OwnershipTransferSynchronizesAdminRole() public {
        bytes32 adminRole = darkElf.DEFAULT_ADMIN_ROLE();
        darkElf.transferOwnership(stranger);
        assertTrue(darkElf.hasRole(adminRole, stranger));
        assertFalse(darkElf.hasRole(adminRole, address(this)));
        vm.prank(stranger);
        darkElf.revokeRole(OPERATOR_ROLE, operator);
        assertFalse(darkElf.hasRole(OPERATOR_ROLE, operator));
    }

    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert("Challenges cannot be zero");
        new HeroArenaMeetTheDarkElf(HeroArenaChallenges(address(0)), profile);
        vm.expectRevert("Profile cannot be zero");
        new HeroArenaMeetTheDarkElf(challenges, HeroArenaProfile(address(0)));
    }
}
