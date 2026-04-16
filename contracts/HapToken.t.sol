// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {HapToken} from "./HapToken.sol";

contract HapTokenTest is Test {
    HapToken token;

    address owner;
    address pool;
    address user;

    uint256 constant YEAR = 365 days;

    function setUp() public {
        owner = address(this);
        pool  = makeAddr("pool");
        user  = makeAddr("user");

        token = new HapToken();
        token.setMainPool(pool);

        // Foundry starts at timestamp 1; warp past the initial 365-day window
        vm.warp(YEAR + 1);
    }

    // ─────────────────────────────────────────────
    // maxMintOfYears
    // ─────────────────────────────────────────────

    function test_MaxMintOfYears_Values() public view {
        assertEq(token.maxMintOfYears(0), 400_000_000 * 10 ** 18);
        assertEq(token.maxMintOfYears(1), 225_000_000 * 10 ** 18);
        assertEq(token.maxMintOfYears(2), 175_000_000 * 10 ** 18);
        assertEq(token.maxMintOfYears(3), 125_000_000 * 10 ** 18);
        assertEq(token.maxMintOfYears(4),  75_000_000 * 10 ** 18);
        assertEq(token.maxMintOfYears(5),           0);
    }

    // ─────────────────────────────────────────────
    // setMainPool
    // ─────────────────────────────────────────────

    function test_SetMainPool_SetsAddress() public {
        address newPool = makeAddr("newPool");
        token.setMainPool(newPool);
        assertEq(token.mainPool(), newPool);
    }

    function test_SetMainPool_EmitsEvent() public {
        address newPool = makeAddr("newPool");
        vm.expectEmit(true, true, false, false);
        emit HapToken.MainPoolUpdated(pool, newPool);
        token.setMainPool(newPool);
    }

    function test_SetMainPool_RevertsOnZeroAddress() public {
        vm.expectRevert();
        token.setMainPool(address(0));
    }

    function test_SetMainPool_RevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        token.setMainPool(makeAddr("newPool"));
    }

    // ─────────────────────────────────────────────
    // nextMintingTime
    // ─────────────────────────────────────────────

    function test_NextMintingTime_IsYearAfterLatestMint() public view {
        // latestMintingTime == 0 initially
        assertEq(token.nextMintingTime(), YEAR);
    }

    function test_NextMintingTime_UpdatesAfterMint() public {
        vm.prank(pool);
        token.mint(user);
        assertEq(token.nextMintingTime(), block.timestamp + YEAR);
    }

    // ─────────────────────────────────────────────
    // mint — access control
    // ─────────────────────────────────────────────

    function test_Mint_RevertsIfNotMainPool() public {
        vm.prank(user);
        vm.expectRevert("Invalid minter");
        token.mint(user);
    }

    function test_Mint_RevertsOnZeroDest() public {
        vm.prank(pool);
        vm.expectRevert("Invalid dest");
        token.mint(address(0));
    }

    function test_Mint_RevertsIfTooEarly() public {
        // First successful mint, then try again immediately
        vm.prank(pool);
        token.mint(user);

        vm.prank(pool);
        vm.expectRevert("Mining not allowed yet");
        token.mint(user);
    }

    // ─────────────────────────────────────────────
    // mint — year 0
    // ─────────────────────────────────────────────

    function test_Mint_Year0_MintsCorrectAmount() public {
        vm.prank(pool);
        token.mint(user);
        assertEq(token.balanceOf(user), 400_000_000 * 10 ** 18);
    }

    function test_Mint_Year0_EmitsYearlyMint() public {
        vm.expectEmit(true, true, false, true);
        emit HapToken.YearlyMint(0, user, 400_000_000 * 10 ** 18);
        vm.prank(pool);
        token.mint(user);
    }

    function test_Mint_Year0_IncrementsYearMint() public {
        vm.prank(pool);
        token.mint(user);
        assertEq(token.yearMint(), 1);
    }

    function test_Mint_Year0_UpdatesLatestMintingTime() public {
        uint256 ts = block.timestamp;
        vm.prank(pool);
        token.mint(user);
        assertEq(token.latestMintingTime(), ts);
    }

    // ─────────────────────────────────────────────
    // mint — burn logic (year 1+)
    // ─────────────────────────────────────────────

    function test_Mint_BurnsRemainingPoolBalance_BeforeNextYearMint() public {
        // Year 0: mint to pool, then pool distributes half
        vm.prank(pool);
        token.mint(pool);

        vm.prank(pool);
        token.transfer(user, 200_000_000 * 10 ** 18);

        uint256 remaining = token.balanceOf(pool); // 200M remaining

        // Advance to year 1
        vm.warp(block.timestamp + YEAR + 1);

        vm.expectEmit(true, true, false, true);
        emit HapToken.YearlyBurn(0, pool, remaining);

        vm.prank(pool);
        token.mint(user);

        assertEq(token.balanceOf(pool), 0);
    }

    function test_Mint_NoBurn_IfPoolBalanceIsZero() public {
        // Year 0: mint directly to user so pool balance stays at 0
        vm.prank(pool);
        token.mint(user);

        vm.warp(block.timestamp + YEAR + 1);

        uint256 supplyBefore = token.totalSupply();

        // Year 1 mint — no pool remainder to burn
        vm.prank(pool);
        token.mint(user);

        uint256 supplyAfter = token.totalSupply();

        // If burn had occurred, supplyAfter < supplyBefore + year1Amount.
        // Without burn, the increase must equal exactly the year 1 allocation.
        assertEq(supplyAfter - supplyBefore, token.maxMintOfYears(1));
    }

    // ─────────────────────────────────────────────
    // mint — multi-year schedule
    // ─────────────────────────────────────────────

    function test_Mint_Year1_MintsCorrectAmount() public {
        vm.prank(pool);
        token.mint(pool);

        vm.warp(block.timestamp + YEAR + 1);
        vm.prank(pool);
        token.mint(user);

        assertEq(token.balanceOf(user), 225_000_000 * 10 ** 18);
    }

    function test_Mint_FullSchedule_TotalSupplyCorrect() public {
        uint256[5] memory expected = [
            uint256(400_000_000 * 10 ** 18),
            225_000_000 * 10 ** 18,
            175_000_000 * 10 ** 18,
            125_000_000 * 10 ** 18,
             75_000_000 * 10 ** 18
        ];

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(pool);
            token.mint(user);
            assertEq(token.yearMint(), i + 1);
            vm.warp(block.timestamp + YEAR + 1);
        }

        uint256 total = 0;
        for (uint256 i = 0; i < 5; i++) {
            total += expected[i];
        }
        // All 5 years minted to user (no pool remainder to burn)
        assertEq(token.balanceOf(user), total);
    }

    function test_Mint_AfterYear5_MintsZeroTokens() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(pool);
            token.mint(user);
            vm.warp(block.timestamp + YEAR + 1);
        }

        uint256 balanceBefore = token.balanceOf(user);
        vm.prank(pool);
        token.mint(user);
        assertEq(token.balanceOf(user), balanceBefore);
    }

    // ─────────────────────────────────────────────
    // ERC20 basics
    // ─────────────────────────────────────────────

    function test_TokenName() public view {
        assertEq(token.name(), "HeroArenaPlay Token");
    }

    function test_TokenSymbol() public view {
        assertEq(token.symbol(), "HAP");
    }

    function test_InitialTotalSupply_IsZero() public view {
        assertEq(token.totalSupply(), 0);
    }
}
