// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {HeroArenaWorldCupInitializable} from "./HeroArenaWorldCupInitializable.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockHeroArenaProfile} from "./mocks/MockHeroArenaProfile.sol";
import {MockRevertingReceiver} from "./mocks/MockRevertingReceiver.sol";

contract HeroArenaWorldCupInitializableTest is Test {
    HeroArenaWorldCupInitializable wc;
    MockERC20 hap;
    MockERC20 bonusTok;
    MockHeroArenaProfile profile;

    address admin;          // owner + DEFAULT_ADMIN_ROLE + LIQUIDATOR_ROLE
    address alice;
    address bob;
    address carol;
    address stranger;

    bytes32 constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");
    uint256 constant REG_FEE = 100e18;

    function setUp() public {
        admin    = address(this);
        alice    = makeAddr("alice");
        bob      = makeAddr("bob");
        carol    = makeAddr("carol");
        stranger = makeAddr("stranger");

        hap      = new MockERC20();
        bonusTok = new MockERC20();
        profile  = new MockHeroArenaProfile();

        wc = new HeroArenaWorldCupInitializable();
        // admin == address(this) so the test contract is owner and holds all roles.
        wc.initialize(admin, address(hap), REG_FEE, address(profile), address(0), 0);
    }

    // ─── helpers ────────────────────────────────────────────────────────────

    function _openRegistration() internal {
        wc.setRegisterDeadline(block.timestamp + 7 days);
    }

    /// @dev Make `player` a profile owner, fund + approve, and self-register.
    function _register(address player) internal {
        profile.setRegistered(player, true);
        hap.mint(player, REG_FEE);
        vm.startPrank(player);
        hap.approve(address(wc), REG_FEE);
        wc.registerBattle(REG_FEE);
        vm.stopPrank();
    }

    // ═════════════════════════════════════════════════════════════════════════
    // initialize
    // ═════════════════════════════════════════════════════════════════════════

    function test_Initialize_SetsStateAndRoles() public view {
        assertEq(wc.owner(), admin);
        assertTrue(wc.hasRole(wc.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(wc.hasRole(LIQUIDATOR_ROLE, admin), "H-3: admin seeded as liquidator");
        assertEq(address(wc.HapToken()), address(hap));
        assertEq(wc.registrationFee(), REG_FEE);
        assertEq(address(wc.HeroArenaProfileSC()), address(profile));
    }

    function test_Initialize_RevertsOnSecondCall() public {
        vm.expectRevert(HeroArenaWorldCupInitializable.AlreadyInitialized.selector);
        wc.initialize(admin, address(hap), REG_FEE, address(profile), address(0), 0);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // M-1: ownership / role synchronization
    // ═════════════════════════════════════════════════════════════════════════

    function test_TransferOwnership_SyncsAdminRole() public {
        wc.transferOwnership(bob);
        assertEq(wc.owner(), bob);
        assertTrue(wc.hasRole(wc.DEFAULT_ADMIN_ROLE(), bob), "new owner gets admin role");
        assertFalse(wc.hasRole(wc.DEFAULT_ADMIN_ROLE(), admin), "old owner loses admin role");
    }

    function test_RenounceOwnership_DropsAdminRole() public {
        wc.renounceOwnership();
        assertEq(wc.owner(), address(0));
        assertFalse(wc.hasRole(wc.DEFAULT_ADMIN_ROLE(), admin));
    }

    // ═════════════════════════════════════════════════════════════════════════
    // registration
    // ═════════════════════════════════════════════════════════════════════════

    function test_Register_HappyPath() public {
        _openRegistration();
        _register(alice);

        assertTrue(wc.registeredPlayerAddresses(alice));
        assertEq(wc.paidFee(alice), REG_FEE);
        assertEq(wc.totalRefundable(), REG_FEE);
        assertEq(hap.balanceOf(address(wc)), REG_FEE);
    }

    function test_Register_RevertsWhenClosed() public {
        profile.setRegistered(alice, true);
        vm.prank(alice);
        vm.expectRevert("Registration is closed");
        wc.registerBattle(REG_FEE);
    }

    function test_Register_RevertsWithoutProfile() public {
        _openRegistration();
        vm.prank(alice);
        vm.expectRevert("Profile not registered");
        wc.registerBattle(REG_FEE);
    }

    function test_Register_RevertsOnDuplicate() public {
        _openRegistration();
        _register(alice);
        profile.setRegistered(alice, true);
        vm.prank(alice);
        vm.expectRevert("Already registered");
        wc.registerBattle(REG_FEE);
    }

    function test_Register_RevertsWhenFeeExceedsMax() public {
        _openRegistration();
        profile.setRegistered(alice, true);
        vm.prank(alice);
        vm.expectRevert("Fee exceeds maximum");
        wc.registerBattle(REG_FEE - 1);
    }

    function test_AddRegisterPlayers_SkipsZeroAndDup_NoFee() public {
        _openRegistration();
        _register(alice);

        address[] memory players = new address[](3);
        players[0] = alice;          // already registered → skipped
        players[1] = address(0);     // zero → skipped
        players[2] = bob;            // new
        wc.addRegisterPlayerAddresses(players);

        assertTrue(wc.registeredPlayerAddresses(bob));
        assertEq(wc.paidFee(bob), 0, "owner-added players pay no fee");
        // alice's fee untouched, totalRefundable unchanged by the batch
        assertEq(wc.totalRefundable(), REG_FEE);
    }

    function test_AddRegisterPlayers_OnlyOwner() public {
        address[] memory players = new address[](1);
        players[0] = bob;
        vm.prank(stranger);
        vm.expectRevert();
        wc.addRegisterPlayerAddresses(players);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // cancel / refund
    // ═════════════════════════════════════════════════════════════════════════

    function test_CancelRegistration_Refunds() public {
        _openRegistration();
        _register(alice);

        vm.prank(alice);
        wc.cancelRegistration();

        assertFalse(wc.registeredPlayerAddresses(alice));
        assertEq(wc.paidFee(alice), 0);
        assertEq(wc.totalRefundable(), 0);
        assertEq(hap.balanceOf(alice), REG_FEE, "fee returned");
    }

    function test_CancelRegistration_RevertsOnceSeated() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);

        vm.prank(alice);
        vm.expectRevert("Already in a battle");
        wc.cancelRegistration();
    }

    function test_RefundUnselected_RevertsBeforeDeadline() public {
        _openRegistration();
        _register(alice);
        address[] memory players = new address[](1);
        players[0] = alice;
        vm.expectRevert("Deadline not reached");
        wc.refundUnselectedPlayers(players);
    }

    function test_RefundUnselected_RefundsAfterDeadline() public {
        _openRegistration();
        _register(alice);
        _register(bob);

        // close window
        vm.warp(block.timestamp + 8 days);

        address[] memory players = new address[](2);
        players[0] = alice;
        players[1] = bob;
        wc.refundUnselectedPlayers(players);

        assertEq(hap.balanceOf(alice), REG_FEE);
        assertEq(hap.balanceOf(bob), REG_FEE);
        assertEq(wc.totalRefundable(), 0);
    }

    function test_RefundUnselected_SkipsRevertingReceiver() public {
        // A reverting receiver can't take a HAP refund... but HAP is ERC20, so the
        // transfer succeeds regardless of receiver code. Instead verify a non-
        // registered address is silently skipped without bricking the batch.
        _openRegistration();
        _register(alice);
        vm.warp(block.timestamp + 8 days);

        address[] memory players = new address[](2);
        players[0] = stranger; // not registered → skipped
        players[1] = alice;    // refunded
        wc.refundUnselectedPlayers(players);

        assertEq(hap.balanceOf(alice), REG_FEE);
    }

    function test_RefundSeat_OnlySelf() public {
        vm.prank(stranger);
        vm.expectRevert("Only self");
        wc.refundSeat(alice);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // battle lifecycle
    // ═════════════════════════════════════════════════════════════════════════

    function test_CreateBattle_SeatsBothPlayers() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);

        assertEq(wc.getBattleCount(), 1);
        assertEq(wc.playerBattleId(alice), 1);
        assertEq(wc.playerBattleId(bob), 1);

        HeroArenaWorldCupInitializable.BattleInfo memory b = wc.getBattleInfo(1);
        assertEq(b.player0Address, alice);
        assertEq(b.player1Address, bob);
        assertFalse(b.isEnded);
    }

    function test_CreateBattle_RevertsOnUnregistered() public {
        _openRegistration();
        _register(alice);
        vm.expectRevert("player1 not registered");
        wc.createBattle(alice, bob);
    }

    function test_CreateBattle_RevertsOnSamePlayer() public {
        _openRegistration();
        _register(alice);
        vm.expectRevert("Players must differ");
        wc.createBattle(alice, alice);
    }

    function test_CreateBattle_RevertsOnDoubleSeat() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        _register(carol);
        wc.createBattle(alice, bob);
        vm.expectRevert("player0 already in a battle");
        wc.createBattle(alice, carol);
    }

    function test_CreateBattle_OnlyOwner() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        vm.prank(stranger);
        vm.expectRevert();
        wc.createBattle(alice, bob);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // settlement
    // ═════════════════════════════════════════════════════════════════════════

    function test_Settle_ReleasesFeesFromRefundPool() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        assertEq(wc.totalRefundable(), 2 * REG_FEE);

        wc.settleBattle(1, alice);

        HeroArenaWorldCupInitializable.BattleInfo memory b = wc.getBattleInfo(1);
        assertTrue(b.isEnded);
        assertEq(b.winner, alice);
        assertEq(wc.totalRefundable(), 0, "both seat fees earned");
        // earned fees now claimable by owner
        assertEq(wc.claimableFee(), 2 * REG_FEE);
    }

    function test_Settle_OnlyLiquidator() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        vm.prank(stranger);
        vm.expectRevert();
        wc.settleBattle(1, alice);
    }

    function test_Settle_RevertsOnInvalidWinner() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        vm.expectRevert("Invalid winner address");
        wc.settleBattle(1, carol);
    }

    function test_Settle_RevertsOnDoubleSettle() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        wc.settleBattle(1, alice);
        vm.expectRevert("Battle already ended");
        wc.settleBattle(1, alice);
    }

    function test_Settle_RevertsOnNonexistentBattle() public {
        vm.expectRevert("Battle does not exist");
        wc.settleBattle(999, alice);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // bonus payouts
    // ═════════════════════════════════════════════════════════════════════════

    function _initWithBonus(address _bonusToken, uint256 _bonusAmount) internal {
        wc = new HeroArenaWorldCupInitializable();
        wc.initialize(admin, address(hap), REG_FEE, address(profile), _bonusToken, _bonusAmount);
    }

    function test_Bonus_ERC20PaidToWinner() public {
        uint256 bonus = 50e18;
        _initWithBonus(address(bonusTok), bonus);

        // fund the bonus pool
        bonusTok.mint(admin, bonus);
        bonusTok.approve(address(wc), bonus);
        wc.depositToken(address(bonusTok), bonus);

        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        wc.settleBattle(1, alice);

        assertEq(bonusTok.balanceOf(alice), bonus, "winner paid ERC20 bonus");
    }

    function test_Bonus_NativePaidToWinner() public {
        uint256 bonus = 1 ether;
        _initWithBonus(address(0), bonus);
        wc.depositNative{value: bonus}();

        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);

        uint256 before = alice.balance;
        wc.settleBattle(1, alice);
        assertEq(alice.balance - before, bonus, "winner paid native bonus");
    }

    function test_Bonus_SkippedWhenPoolEmpty_SettlementStillSucceeds() public {
        _initWithBonus(address(bonusTok), 50e18); // pool never funded

        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        wc.settleBattle(1, alice); // must not revert

        HeroArenaWorldCupInitializable.BattleInfo memory b = wc.getBattleInfo(1);
        assertTrue(b.isEnded, "settles even though bonus skipped");
        assertEq(bonusTok.balanceOf(alice), 0);
    }

    function test_Bonus_NativeFailureDoesNotBlockSettlement() public {
        uint256 bonus = 1 ether;
        _initWithBonus(address(0), bonus);
        wc.depositNative{value: bonus}();

        // winner is a contract that rejects ETH
        MockRevertingReceiver rr = new MockRevertingReceiver();
        _openRegistration();
        _register(alice);
        address[] memory owned = new address[](1);
        owned[0] = address(rr);
        wc.addRegisterPlayerAddresses(owned);
        wc.createBattle(alice, address(rr));

        wc.settleBattle(1, address(rr)); // bonus fails silently, settle succeeds
        HeroArenaWorldCupInitializable.BattleInfo memory b = wc.getBattleInfo(1);
        assertTrue(b.isEnded);
        assertEq(address(wc).balance, bonus, "failed bonus stays in contract");
    }

    function test_Bonus_HapNeverEatsRefundPool() public {
        // bonus token == HAP; pool only funded by registration fees.
        uint256 bonus = REG_FEE; // try to pay a full fee as bonus
        _initWithBonus(address(hap), bonus);

        _openRegistration();
        _register(alice);
        _register(bob);
        _register(carol);
        // alice & bob seated; carol still reserved in the refund pool.
        wc.createBattle(alice, bob);
        assertEq(wc.totalRefundable(), 3 * REG_FEE);

        wc.settleBattle(1, alice);
        // After release, free balance = 3*FEE - 1*FEE(carol reserved) = 2*FEE.
        // bonus = FEE <= free, so it pays and carol's reserved FEE is untouched.
        assertEq(wc.totalRefundable(), REG_FEE, "carol's refund still reserved");
        assertGe(hap.balanceOf(address(wc)), wc.totalRefundable(), "pool solvency held");
    }

    // ═════════════════════════════════════════════════════════════════════════
    // claimFee / rescue
    // ═════════════════════════════════════════════════════════════════════════

    function test_ClaimFee_CappedByRefundPool() public {
        _openRegistration();
        _register(alice); // 1 fee reserved, none earned yet
        assertEq(wc.claimableFee(), 0, "nothing claimable while fully reserved");

        vm.expectRevert("Exceeds claimable fees");
        wc.claimFee(1);
    }

    function test_ClaimFee_WithdrawsEarnedFees() public {
        _openRegistration();
        _register(alice);
        _register(bob);
        wc.createBattle(alice, bob);
        wc.settleBattle(1, alice);

        uint256 before = hap.balanceOf(admin);
        wc.claimFee(2 * REG_FEE);
        assertEq(hap.balanceOf(admin) - before, 2 * REG_FEE);
    }

    function test_Rescue_CannotDrainRefundPool() public {
        _openRegistration();
        _register(alice); // REG_FEE reserved
        // contract holds exactly REG_FEE, all reserved → 0 rescuable
        vm.expectRevert("Amount exceeds rescuable balance");
        wc.rescueExtraTokens(address(hap), admin, 1);
    }

    function test_Rescue_RecoversForeignToken() public {
        bonusTok.mint(address(wc), 5e18); // stray tokens
        wc.rescueExtraTokens(address(bonusTok), stranger, 5e18);
        assertEq(bonusTok.balanceOf(stranger), 5e18);
    }

    function test_SetRegisterDeadline_RejectsPast() public {
        vm.warp(1000);
        vm.expectRevert("Deadline must be in the future");
        wc.setRegisterDeadline(500);
    }

    // allow the test contract to receive native bonus refunds in some flows
    receive() external payable {}
}
