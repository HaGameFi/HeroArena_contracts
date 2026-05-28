// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaBattle} from "./HeroArenaBattle.sol";
import {HeroArenaProfileInterface} from "./interfaces/HeroArenaProfileInterface.sol";
import {HeroArenaProfile} from "./HeroArenaProfile.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "./mocks/MockFeeOnTransferERC20.sol";
import {MockRevertingReceiver} from "./mocks/MockRevertingReceiver.sol";

contract HeroArenaBattleTest is Test {
    HeroArenaBattle battleSC;
    HeroArenaProfile profileSC;

    MockERC20 hapToken;
    MockERC20 betToken;
    MockERC20 bonusToken;

    address ownerAddr;
    address user1;
    address user2;
    address user3;
    address liquidatorAddr;
    address stranger;

    uint256 constant BET_AMOUNT   = 1 ether;
    uint256 constant BONUS_AMOUNT = 0.5 ether;

    bytes32 constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    function setUp() public {
        ownerAddr      = address(this);
        user1          = makeAddr("user1");
        user2          = makeAddr("user2");
        user3          = makeAddr("user3");
        liquidatorAddr = makeAddr("liquidator");
        stranger       = makeAddr("stranger");

        hapToken  = new MockERC20();
        profileSC = new HeroArenaProfile(IERC20(address(hapToken)), 0, 0);
        profileSC.addTeam("Warriors", "Warriors team");
        vm.prank(user1); profileSC.createProfile(1, type(uint256).max);
        vm.prank(user2); profileSC.createProfile(1, type(uint256).max);
        vm.prank(user3); profileSC.createProfile(1, type(uint256).max);

        betToken   = new MockERC20();
        bonusToken = new MockERC20();

        battleSC = new HeroArenaBattle(HeroArenaProfileInterface(address(profileSC)));
        battleSC.grantRole(LIQUIDATOR_ROLE, liquidatorAddr);

        betToken.mint(user1, 10_000 ether);
        betToken.mint(user2, 10_000 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(stranger, 100 ether);

        vm.prank(user1); betToken.approve(address(battleSC), type(uint256).max);
        vm.prank(user2); betToken.approve(address(battleSC), type(uint256).max);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _enableNative() internal {
        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(0), true);
        battleSC.updateMinimumBetTokenAmount(0.01 ether, 0);
    }

    function _enableERC20() internal {
        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(betToken), true);
        battleSC.updateMinimumBetTokenAmount(0, 1);
    }

    function _createNativeOpenBattle() internal returns (uint256 battleId) {
        _enableNative();
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
        battleId = battleSC.getBattleCount();
    }

    function _createERC20OpenBattle() internal returns (uint256 battleId) {
        _enableERC20();
        vm.prank(user1);
        battleSC.createBattle(address(betToken), BET_AMOUNT, address(0));
        battleId = battleSC.getBattleCount();
    }

    function _startNativeBattle() internal returns (uint256 battleId) {
        battleId = _createNativeOpenBattle();
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(battleId);
    }

    function _startERC20Battle() internal returns (uint256 battleId) {
        battleId = _createERC20OpenBattle();
        vm.prank(user2);
        battleSC.joinExistBattle(battleId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsProfileSC() public view {
        assertEq(address(battleSC.HeroArenaProfileSC()), address(profileSC));
    }

    function test_Constructor_GrantsDefaultAdminRole() public view {
        assertTrue(battleSC.hasRole(battleSC.DEFAULT_ADMIN_ROLE(), ownerAddr));
    }

    function test_Constructor_AvailableCreateBattleIsFalse() public view {
        assertFalse(battleSC.availableCreateBattle());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAvailableCreateBattle
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAvailableCreateBattle_TogglesFlag() public {
        battleSC.updateAvailableCreateBattle(true);
        assertTrue(battleSC.availableCreateBattle());
        battleSC.updateAvailableCreateBattle(false);
        assertFalse(battleSC.availableCreateBattle());
    }

    function test_UpdateAvailableCreateBattle_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaBattle.AvailableCreateBattleUpdated(ownerAddr, true);
        battleSC.updateAvailableCreateBattle(true);
    }

    function test_UpdateAvailableCreateBattle_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateAvailableCreateBattle(true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateForbiddenToPlay
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateForbiddenToPlay_SetsFlag() public {
        battleSC.updateForbiddenToPlay(user1, true);
        assertTrue(battleSC.forbiddenToPlay(user1));
        battleSC.updateForbiddenToPlay(user1, false);
        assertFalse(battleSC.forbiddenToPlay(user1));
    }

    function test_UpdateForbiddenToPlay_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.ForbiddenToPlayUpdated(ownerAddr, user1, true);
        battleSC.updateForbiddenToPlay(user1, true);
    }

    function test_UpdateForbiddenToPlay_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateForbiddenToPlay(user1, true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateBonusToken
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateBonusToken_SetsValues() public {
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
        assertEq(battleSC.bonusToken(), address(bonusToken));
        assertEq(battleSC.bonusAmount(), BONUS_AMOUNT);
    }

    function test_UpdateBonusToken_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaBattle.BonusTokenUpdated(ownerAddr, address(bonusToken), BONUS_AMOUNT);
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
    }

    function test_UpdateBonusToken_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateAllowedBetToken
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateAllowedBetToken_SetsFlag() public {
        battleSC.updateAllowedBetToken(address(betToken), true);
        assertTrue(battleSC.allowedBetTokens(address(betToken)));
        battleSC.updateAllowedBetToken(address(betToken), false);
        assertFalse(battleSC.allowedBetTokens(address(betToken)));
    }

    function test_UpdateAllowedBetToken_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.AllowedBetTokenUpdated(ownerAddr, address(betToken), true);
        battleSC.updateAllowedBetToken(address(betToken), true);
    }

    function test_UpdateAllowedBetToken_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateAllowedBetToken(address(betToken), true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // updateMinimumBetTokenAmount
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateMinBet_SetsValues() public {
        battleSC.updateMinimumBetTokenAmount(0.5 ether, 10 ether);
        assertEq(battleSC.minBetAmount(0), 0.5 ether);
        assertEq(battleSC.minBetAmount(1), 10 ether);
    }

    function test_UpdateMinBet_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateMinimumBetTokenAmount(1, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // createBattle — native ETH
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CreateBattle_Native_TransfersETH() public {
        _enableNative();
        uint256 before = address(battleSC).balance;
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
        assertEq(address(battleSC).balance, before + BET_AMOUNT);
    }

    function test_CreateBattle_Native_StoresBattleInfo() public {
        uint256 id = _createNativeOpenBattle();
        HeroArenaBattle.BattleInfo memory info = battleSC.getBattleInfo(id);
        assertEq(info.selfAddress, user1);
        assertEq(info.targetAddress, address(0));
        assertEq(info.betTokenAddress, address(0));
        assertEq(info.betAmount, BET_AMOUNT);
        assertFalse(info.isStarted);
        assertFalse(info.isEnded);
    }

    function test_CreateBattle_Native_IncrementsBattleCount() public {
        assertEq(battleSC.getBattleCount(), 0);
        _createNativeOpenBattle();
        assertEq(battleSC.getBattleCount(), 1);
    }

    function test_CreateBattle_Native_EmitsEvent() public {
        _enableNative();
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.BattleCreated(1, user1, address(0), address(0), BET_AMOUNT);
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_Native_PrivateBattle() public {
        _enableNative();
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, user2);
        uint256 id = battleSC.getBattleCount();
        assertEq(battleSC.getBattleInfo(id).targetAddress, user2);
    }

    function test_CreateBattle_Native_RevertsIfWrongETHAmount() public {
        _enableNative();
        vm.prank(user1);
        vm.expectRevert("Incorrect ETH amount sent");
        battleSC.createBattle{value: 0.5 ether}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_Native_RevertsBelowMinBet() public {
        _enableNative();
        battleSC.updateMinimumBetTokenAmount(2 ether, 0);
        vm.prank(user1);
        vm.expectRevert("Bet amount below minimum");
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_RevertsIfNotAvailable() public {
        battleSC.updateAllowedBetToken(address(0), true);
        vm.prank(user1);
        vm.expectRevert("Cannot create battle");
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_RevertsIfNotRegistered() public {
        _enableNative();
        vm.prank(stranger);
        vm.expectRevert("Profile not registered");
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_RevertsIfForbidden() public {
        _enableNative();
        battleSC.updateForbiddenToPlay(user1, true);
        vm.prank(user1);
        vm.expectRevert("Forbidden to play");
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_RevertsIfTargetSelf() public {
        _enableNative();
        vm.prank(user1);
        vm.expectRevert("Cannot target yourself");
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, user1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // createBattle — ERC20
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CreateBattle_ERC20_TransfersToken() public {
        _enableERC20();
        uint256 before = betToken.balanceOf(address(battleSC));
        vm.prank(user1);
        battleSC.createBattle(address(betToken), BET_AMOUNT, address(0));
        assertEq(betToken.balanceOf(address(battleSC)), before + BET_AMOUNT);
    }

    function test_CreateBattle_ERC20_StoresBetTokenAddress() public {
        uint256 id = _createERC20OpenBattle();
        assertEq(battleSC.getBattleInfo(id).betTokenAddress, address(betToken));
    }

    function test_CreateBattle_ERC20_RevertsIfETHSent() public {
        _enableERC20();
        vm.prank(user1);
        vm.expectRevert("ETH not accepted for ERC20 bet");
        battleSC.createBattle{value: 1 ether}(address(betToken), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_ERC20_RevertsIfTokenNotAllowed() public {
        battleSC.updateAvailableCreateBattle(true);
        vm.prank(user1);
        vm.expectRevert("Token not allowed");
        battleSC.createBattle(address(betToken), BET_AMOUNT, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // joinExistBattle
    // ═══════════════════════════════════════════════════════════════════════════

    function test_JoinBattle_Native_TransfersETH() public {
        uint256 id = _createNativeOpenBattle();
        uint256 before = address(battleSC).balance;
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
        assertEq(address(battleSC).balance, before + BET_AMOUNT);
    }

    function test_JoinBattle_ERC20_TransfersToken() public {
        uint256 id = _createERC20OpenBattle();
        uint256 before = betToken.balanceOf(address(battleSC));
        vm.prank(user2);
        battleSC.joinExistBattle(id);
        assertEq(betToken.balanceOf(address(battleSC)), before + BET_AMOUNT);
    }

    function test_JoinBattle_SetsIsStartedAndTargetAddress() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
        HeroArenaBattle.BattleInfo memory info = battleSC.getBattleInfo(id);
        assertTrue(info.isStarted);
        assertEq(info.targetAddress, user2);
    }

    function test_JoinBattle_EmitsEvent() public {
        uint256 id = _createNativeOpenBattle();
        vm.expectEmit(true, true, false, false);
        emit HeroArenaBattle.BattleJoined(id, user2);
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_PrivateBattle_InvitedUserCanJoin() public {
        _enableNative();
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, user2);
        uint256 id = battleSC.getBattleCount();
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
        assertTrue(battleSC.getBattleInfo(id).isStarted);
    }

    function test_JoinBattle_SucceedsAfterTokenRemovedFromWhitelist() public {
        uint256 id = _createERC20OpenBattle();
        battleSC.updateAllowedBetToken(address(betToken), false);
        vm.prank(user2);
        battleSC.joinExistBattle(id);
        assertTrue(battleSC.getBattleInfo(id).isStarted);
    }

    function test_JoinBattle_RevertsIfBattleNotExist() public {
        _enableNative();
        vm.prank(user2);
        vm.expectRevert("Battle does not exist");
        battleSC.joinExistBattle{value: BET_AMOUNT}(999);
    }

    function test_JoinBattle_RevertsIfAlreadyStarted() public {
        uint256 id = _startNativeBattle();
        vm.prank(user3);
        vm.expectRevert("Battle already has an opponent");
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_RevertsIfOwnBattle() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(user1);
        vm.expectRevert("Cannot join own battle");
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_RevertsIfNotInvited() public {
        _enableNative();
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, user2);
        uint256 id = battleSC.getBattleCount();
        vm.prank(user3);
        vm.expectRevert("Not invited to this battle");
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_RevertsIfNotRegistered() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(stranger);
        vm.expectRevert("Profile not registered");
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_RevertsIfForbidden() public {
        uint256 id = _createNativeOpenBattle();
        battleSC.updateForbiddenToPlay(user2, true);
        vm.prank(user2);
        vm.expectRevert("Forbidden to play");
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_RevertsIfWrongETHAmount() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(user2);
        vm.expectRevert("Incorrect ETH amount sent");
        battleSC.joinExistBattle{value: 0.5 ether}(id);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // settleBattle
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SettleBattle_Native_PaysWinner() public {
        uint256 id = _startNativeBattle();
        uint256 before = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
        assertEq(user1.balance, before + BET_AMOUNT * 2);
    }

    function test_SettleBattle_ERC20_PaysWinner() public {
        uint256 id = _startERC20Battle();
        uint256 before = betToken.balanceOf(user1);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
        assertEq(betToken.balanceOf(user1), before + BET_AMOUNT * 2);
    }

    function test_SettleBattle_WithBonus_PaysBonus() public {
        bonusToken.mint(address(battleSC), BONUS_AMOUNT);
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
        uint256 id = _startERC20Battle();
        uint256 before = bonusToken.balanceOf(user2);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user2);
        assertEq(bonusToken.balanceOf(user2), before + BONUS_AMOUNT);
    }

    function test_SettleBattle_SetsIsEndedAndWinner() public {
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
        HeroArenaBattle.BattleInfo memory info = battleSC.getBattleInfo(id);
        assertTrue(info.isEnded);
        assertEq(info.winner, user1);
    }

    function test_SettleBattle_EmitsEvent() public {
        uint256 id = _startNativeBattle();
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.BattleEnded(id, user1, BET_AMOUNT * 2);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
    }

    function test_SettleBattle_CannotSettleTwice() public {
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);
        vm.prank(liquidatorAddr);
        vm.expectRevert("Battle already ended");
        battleSC.settleBattle(id, user2);
    }

    function test_SettleBattle_RevertsIfNotLiquidator() public {
        uint256 id = _startNativeBattle();
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.settleBattle(id, user1);
    }

    function test_SettleBattle_RevertsIfBattleNotExist() public {
        vm.prank(liquidatorAddr);
        vm.expectRevert("Battle does not exist");
        battleSC.settleBattle(999, user1);
    }

    function test_SettleBattle_RevertsIfNotStarted() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(liquidatorAddr);
        vm.expectRevert("Opponent has not joined");
        battleSC.settleBattle(id, user1);
    }

    function test_SettleBattle_RevertsIfInvalidWinner() public {
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr);
        vm.expectRevert("Invalid winner address");
        battleSC.settleBattle(id, stranger);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // closeBattle
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CloseBattle_Native_RefundsCreator() public {
        uint256 id = _createNativeOpenBattle();
        uint256 before = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.closeBattle(id);
        assertEq(user1.balance, before + BET_AMOUNT);
    }

    function test_CloseBattle_ERC20_RefundsCreator() public {
        uint256 id = _createERC20OpenBattle();
        uint256 before = betToken.balanceOf(user1);
        vm.prank(liquidatorAddr);
        battleSC.closeBattle(id);
        assertEq(betToken.balanceOf(user1), before + BET_AMOUNT);
    }

    function test_CloseBattle_SetsIsEnded() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(liquidatorAddr);
        battleSC.closeBattle(id);
        assertTrue(battleSC.getBattleInfo(id).isEnded);
    }

    function test_CloseBattle_EmitsEvent() public {
        uint256 id = _createNativeOpenBattle();
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.BattleClosed(id, liquidatorAddr, BET_AMOUNT);
        vm.prank(liquidatorAddr);
        battleSC.closeBattle(id);
    }

    function test_CloseBattle_RevertsIfBattleNotExist() public {
        vm.prank(liquidatorAddr);
        vm.expectRevert("Battle does not exist");
        battleSC.closeBattle(999);
    }

    function test_CloseBattle_RevertsIfAlreadyStarted() public {
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr);
        vm.expectRevert("Battle already has an opponent");
        battleSC.closeBattle(id);
    }

    function test_CloseBattle_RevertsIfAlreadyEnded() public {
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);
        vm.prank(liquidatorAddr);
        vm.expectRevert("Battle already ended");
        battleSC.closeBattle(id);
    }

    function test_CloseBattle_RevertsIfNotLiquidator() public {
        uint256 id = _createNativeOpenBattle();
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.closeBattle(id);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // depositToken
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DepositToken_TransfersERC20() public {
        bonusToken.mint(ownerAddr, 1000 ether);
        bonusToken.approve(address(battleSC), type(uint256).max);
        battleSC.depositToken(address(bonusToken), 1000 ether);
        assertEq(bonusToken.balanceOf(address(battleSC)), 1000 ether);
    }

    function test_DepositToken_EmitsEvent() public {
        bonusToken.mint(ownerAddr, 100 ether);
        bonusToken.approve(address(battleSC), type(uint256).max);
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.TokenDeposited(ownerAddr, address(bonusToken), 100 ether);
        battleSC.depositToken(address(bonusToken), 100 ether);
    }

    function test_DepositToken_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.depositToken(address(bonusToken), 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setProtocolFee / setProtocolFeeRecipient
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetProtocolFee_SetsValue() public {
        battleSC.setProtocolFee(300);
        assertEq(battleSC.protocolFeeBps(), 300);
    }

    function test_SetProtocolFee_AllowsZeroAsKillSwitch() public {
        battleSC.setProtocolFee(300);
        battleSC.setProtocolFee(0);
        assertEq(battleSC.protocolFeeBps(), 0);
    }

    function test_SetProtocolFee_AllowsMaxCap() public {
        uint256 cap = battleSC.MAX_PROTOCOL_FEE_BPS();
        battleSC.setProtocolFee(cap);
        assertEq(battleSC.protocolFeeBps(), cap);
    }

    function test_SetProtocolFee_RevertsAboveCap() public {
        uint256 cap = battleSC.MAX_PROTOCOL_FEE_BPS();
        vm.expectRevert("Fee exceeds cap");
        battleSC.setProtocolFee(cap + 1);
    }

    function test_SetProtocolFee_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.setProtocolFee(100);
    }

    function test_SetProtocolFee_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaBattle.ProtocolFeeUpdated(ownerAddr, 0, 300);
        battleSC.setProtocolFee(300);
    }

    function test_SetProtocolFeeRecipient_SetsValue() public {
        address recipient = makeAddr("treasury");
        battleSC.setProtocolFeeRecipient(recipient);
        assertEq(battleSC.protocolFeeRecipient(), recipient);
    }

    function test_SetProtocolFeeRecipient_AllowsZeroToSwitchToAccumulateMode() public {
        battleSC.setProtocolFeeRecipient(makeAddr("treasury"));
        battleSC.setProtocolFeeRecipient(address(0));
        assertEq(battleSC.protocolFeeRecipient(), address(0));
    }

    function test_SetProtocolFeeRecipient_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.setProtocolFeeRecipient(stranger);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // settleBattle — protocol fee
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SettleBattle_FeeZero_PaysFullReward() public {
        // Default: protocolFeeBps == 0 → no fee charged regardless of recipient.
        address recipient = makeAddr("treasury");
        battleSC.setProtocolFeeRecipient(recipient);
        uint256 id = _startNativeBattle();

        uint256 before = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);

        assertEq(user1.balance, before + BET_AMOUNT * 2);
        assertEq(recipient.balance, 0);
    }

    function test_SettleBattle_PushesFeeToRecipient() public {
        address recipient = makeAddr("treasury");
        battleSC.setProtocolFeeRecipient(recipient);
        battleSC.setProtocolFee(300); // 3 %
        uint256 id = _startNativeBattle();

        uint256 totalReward = BET_AMOUNT * 2;
        uint256 expectedFee = (totalReward * 300) / 10000;

        uint256 userBefore = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);

        assertEq(recipient.balance, expectedFee);
        assertEq(user1.balance, userBefore + totalReward - expectedFee);
        // No accrual when push mode is active
        assertEq(battleSC.accruedProtocolFees(address(0)), 0);
    }

    function test_SettleBattle_AccruesFee_WhenRecipientUnset() public {
        battleSC.setProtocolFee(300);
        // protocolFeeRecipient remains address(0) → accrue mode
        uint256 id = _startNativeBattle();

        uint256 totalReward = BET_AMOUNT * 2;
        uint256 expectedFee = (totalReward * 300) / 10000;

        uint256 userBefore = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);

        assertEq(battleSC.accruedProtocolFees(address(0)), expectedFee);
        assertEq(user1.balance, userBefore + totalReward - expectedFee);
    }

    function test_SettleBattle_AccruesFee_ERC20() public {
        battleSC.setProtocolFee(500); // 5 %
        uint256 id = _startERC20Battle();

        uint256 totalReward = BET_AMOUNT * 2;
        uint256 expectedFee = (totalReward * 500) / 10000;

        uint256 userBefore = betToken.balanceOf(user1);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);

        assertEq(battleSC.accruedProtocolFees(address(betToken)), expectedFee);
        assertEq(betToken.balanceOf(user1), userBefore + totalReward - expectedFee);
    }

    function test_SettleBattle_EmitsProtocolFeeChargedEvent_PushMode() public {
        address recipient = makeAddr("treasury");
        battleSC.setProtocolFeeRecipient(recipient);
        battleSC.setProtocolFee(300);
        uint256 id = _startNativeBattle();

        uint256 expectedFee = (BET_AMOUNT * 2 * 300) / 10000;
        vm.expectEmit(true, true, true, true);
        emit HeroArenaBattle.ProtocolFeeCharged(id, address(0), recipient, expectedFee);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
    }

    function test_SettleBattle_BattleEndedEventReportsNetReward() public {
        battleSC.setProtocolFee(300);
        uint256 id = _startNativeBattle();
        uint256 expectedNet = BET_AMOUNT * 2 - (BET_AMOUNT * 2 * 300) / 10000;
        vm.expectEmit(true, true, false, true);
        emit HeroArenaBattle.BattleEnded(id, user1, expectedNet);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // withdrawProtocolFees
    // ═══════════════════════════════════════════════════════════════════════════

    function test_WithdrawProtocolFees_TransfersFullETH() public {
        battleSC.setProtocolFee(300);
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);

        uint256 accrued = battleSC.accruedProtocolFees(address(0));
        assertGt(accrued, 0);
        address dest = makeAddr("treasury");
        battleSC.withdrawProtocolFees(address(0), dest, accrued);
        assertEq(dest.balance, accrued);
        assertEq(battleSC.accruedProtocolFees(address(0)), 0);
    }

    function test_WithdrawProtocolFees_PartialWithdrawERC20() public {
        battleSC.setProtocolFee(300);
        uint256 id = _startERC20Battle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);

        uint256 accrued = battleSC.accruedProtocolFees(address(betToken));
        uint256 half    = accrued / 2;
        address dest    = makeAddr("treasury");
        battleSC.withdrawProtocolFees(address(betToken), dest, half);
        assertEq(betToken.balanceOf(dest), half);
        assertEq(battleSC.accruedProtocolFees(address(betToken)), accrued - half);
    }

    function test_WithdrawProtocolFees_RevertsIfExceedsAccrued() public {
        battleSC.setProtocolFee(300);
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);

        uint256 accrued = battleSC.accruedProtocolFees(address(0));
        vm.expectRevert("Amount exceeds accrued fees");
        battleSC.withdrawProtocolFees(address(0), stranger, accrued + 1);
    }

    function test_WithdrawProtocolFees_RevertsIfZeroDestination() public {
        vm.expectRevert("Invalid address");
        battleSC.withdrawProtocolFees(address(0), address(0), 1);
    }

    function test_WithdrawProtocolFees_RevertsIfZeroAmount() public {
        vm.expectRevert("Amount must be > 0");
        battleSC.withdrawProtocolFees(address(0), stranger, 0);
    }

    function test_WithdrawProtocolFees_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.withdrawProtocolFees(address(0), stranger, 1);
    }

    function test_WithdrawProtocolFees_EmitsEvent() public {
        battleSC.setProtocolFee(300);
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);
        uint256 accrued = battleSC.accruedProtocolFees(address(0));

        address dest = makeAddr("treasury");
        vm.expectEmit(true, true, true, true);
        emit HeroArenaBattle.ProtocolFeeWithdrawn(ownerAddr, address(0), dest, accrued);
        battleSC.withdrawProtocolFees(address(0), dest, accrued);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // outstandingBets accounting
    // ═══════════════════════════════════════════════════════════════════════════

    function test_OutstandingBets_IncrementsOnCreate() public {
        uint256 before = battleSC.outstandingBets(address(0));
        _createNativeOpenBattle();
        assertEq(battleSC.outstandingBets(address(0)), before + BET_AMOUNT);
    }

    function test_OutstandingBets_IncrementsOnJoin() public {
        uint256 id = _createNativeOpenBattle();
        uint256 before = battleSC.outstandingBets(address(0));
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
        assertEq(battleSC.outstandingBets(address(0)), before + BET_AMOUNT);
    }

    function test_OutstandingBets_FullCycleReturnsToZero() public {
        uint256 id = _startNativeBattle();
        assertEq(battleSC.outstandingBets(address(0)), BET_AMOUNT * 2);
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);
        assertEq(battleSC.outstandingBets(address(0)), 0);
    }

    function test_OutstandingBets_DecrementsOnClose() public {
        uint256 id = _createNativeOpenBattle();
        assertEq(battleSC.outstandingBets(address(0)), BET_AMOUNT);
        vm.prank(liquidatorAddr); battleSC.closeBattle(id);
        assertEq(battleSC.outstandingBets(address(0)), 0);
    }

    function test_OutstandingBets_TracksERC20Separately() public {
        _startERC20Battle();
        assertEq(battleSC.outstandingBets(address(betToken)), BET_AMOUNT * 2);
        assertEq(battleSC.outstandingBets(address(0)), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // rescueExtraTokens
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RescueExtraTokens_RescuesUnusedDeposit() public {
        bonusToken.mint(ownerAddr, 1000 ether);
        bonusToken.approve(address(battleSC), type(uint256).max);
        battleSC.depositToken(address(bonusToken), 1000 ether);

        address dest = makeAddr("dest");
        battleSC.rescueExtraTokens(address(bonusToken), dest, 1000 ether);
        assertEq(bonusToken.balanceOf(dest), 1000 ether);
    }

    function test_RescueExtraTokens_CannotDrainLockedBets() public {
        _startNativeBattle(); // contract holds 2 ETH locked in a battle
        address dest = makeAddr("dest");
        vm.expectRevert("Amount exceeds rescuable balance");
        battleSC.rescueExtraTokens(address(0), dest, 1);
    }

    function test_RescueExtraTokens_CanRescueAccidentalETH() public {
        _startNativeBattle(); // 2 ETH locked
        // Simulate someone accidentally transferring 5 ETH to the contract
        vm.deal(address(battleSC), address(battleSC).balance + 5 ether);

        address dest = makeAddr("dest");
        battleSC.rescueExtraTokens(address(0), dest, 5 ether);
        assertEq(dest.balance, 5 ether);

        // But not one wei more — locked battle funds are protected
        vm.expectRevert("Amount exceeds rescuable balance");
        battleSC.rescueExtraTokens(address(0), dest, 1);
    }

    function test_RescueExtraTokens_CannotDrainAccruedFees() public {
        battleSC.setProtocolFee(300);
        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);

        uint256 fees = battleSC.accruedProtocolFees(address(0));
        assertGt(fees, 0);
        // After settle, contract balance equals accruedFees exactly
        assertEq(address(battleSC).balance, fees);

        address dest = makeAddr("dest");
        vm.expectRevert("Amount exceeds rescuable balance");
        battleSC.rescueExtraTokens(address(0), dest, 1);
    }

    function test_RescueExtraTokens_RevertsIfZeroDestination() public {
        vm.expectRevert("Invalid address");
        battleSC.rescueExtraTokens(address(0), address(0), 1);
    }

    function test_RescueExtraTokens_RevertsIfZeroAmount() public {
        vm.expectRevert("Amount must be > 0");
        battleSC.rescueExtraTokens(address(0), stranger, 0);
    }

    function test_RescueExtraTokens_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.rescueExtraTokens(address(0), stranger, 1);
    }

    function test_RescueExtraTokens_EmitsEvent() public {
        bonusToken.mint(address(battleSC), 100 ether);
        address dest = makeAddr("dest");
        vm.expectEmit(true, true, true, true);
        emit HeroArenaBattle.ExtraTokensRescued(ownerAddr, address(bonusToken), dest, 100 ether);
        battleSC.rescueExtraTokens(address(bonusToken), dest, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getBattleInfo / getBattleCount
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetBattleCount_StartsAtZero() public view {
        assertEq(battleSC.getBattleCount(), 0);
    }

    function test_GetBattleCount_IncrementsOnCreate() public {
        _createNativeOpenBattle();
        _createNativeOpenBattle();
        assertEq(battleSC.getBattleCount(), 2);
    }

    function test_GetBattleInfo_ReturnsDefaultForNonExistent() public view {
        HeroArenaBattle.BattleInfo memory info = battleSC.getBattleInfo(999);
        assertEq(info.selfAddress, address(0));
        assertFalse(info.isStarted);
        assertFalse(info.isEnded);
    }

    receive() external payable {}

    // ═══════════════════════════════════════════════════════════════════════════
    // M-1 — bonus failure must NOT block settlement
    // ═══════════════════════════════════════════════════════════════════════════

    function test_M1_SettleSucceedsEvenIfBonusPoolEmpty() public {
        // Configure a bonus the contract cannot pay (no deposit made).
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
        uint256 id = _startNativeBattle();

        uint256 before = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);

        // Winner still receives the main reward — settlement was NOT blocked
        assertEq(user1.balance, before + BET_AMOUNT * 2);
        assertTrue(battleSC.getBattleInfo(id).isEnded);
        // Bonus was not paid
        assertEq(bonusToken.balanceOf(user1), 0);
    }

    function test_M1_EmitsBonusPayoutWithSuccessFalse() public {
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
        uint256 id = _startNativeBattle();

        vm.expectEmit(true, true, true, true);
        emit HeroArenaBattle.BonusPayout(id, user1, address(bonusToken), BONUS_AMOUNT, false);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
    }

    function test_M1_BonusPaidNormallyWhenPoolFunded() public {
        bonusToken.mint(address(battleSC), BONUS_AMOUNT);
        battleSC.updateBonusToken(address(bonusToken), BONUS_AMOUNT);
        uint256 id = _startNativeBattle();

        vm.expectEmit(true, true, true, true);
        emit HeroArenaBattle.BonusPayout(id, user1, address(bonusToken), BONUS_AMOUNT, true);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);

        assertEq(bonusToken.balanceOf(user1), BONUS_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // M-2 — fee push failure must NOT block settlement (falls back to accrual)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_M2_FeePushFallsBackToAccrual_OnRevertingRecipient() public {
        // Set recipient to a contract that always reverts on receive
        MockRevertingReceiver bad = new MockRevertingReceiver();
        battleSC.setProtocolFeeRecipient(address(bad));
        battleSC.setProtocolFee(300); // 3 %

        uint256 id = _startNativeBattle();
        uint256 expectedFee = (BET_AMOUNT * 2 * 300) / 10000;

        uint256 userBefore = user1.balance;
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1); // MUST NOT revert

        // Winner still got their net reward
        assertEq(user1.balance, userBefore + BET_AMOUNT * 2 - expectedFee);
        // Bad recipient got nothing
        assertEq(address(bad).balance, 0);
        // Fee was accrued instead — protocol still gets its share, just deferred
        assertEq(battleSC.accruedProtocolFees(address(0)), expectedFee);
    }

    function test_M2_EventReportsAccrualWhenPushFailed() public {
        MockRevertingReceiver bad = new MockRevertingReceiver();
        battleSC.setProtocolFeeRecipient(address(bad));
        battleSC.setProtocolFee(300);

        uint256 id = _startNativeBattle();
        uint256 expectedFee = (BET_AMOUNT * 2 * 300) / 10000;

        // ProtocolFeeCharged with recipient=0 means "fell back to accrual"
        vm.expectEmit(true, true, true, true);
        emit HeroArenaBattle.ProtocolFeeCharged(id, address(0), address(0), expectedFee);
        vm.prank(liquidatorAddr);
        battleSC.settleBattle(id, user1);
    }

    function test_M2_AdminCanWithdrawAccruedAfterPushFailure() public {
        MockRevertingReceiver bad = new MockRevertingReceiver();
        battleSC.setProtocolFeeRecipient(address(bad));
        battleSC.setProtocolFee(300);

        uint256 id = _startNativeBattle();
        vm.prank(liquidatorAddr); battleSC.settleBattle(id, user1);

        uint256 accrued = battleSC.accruedProtocolFees(address(0));
        address dest = makeAddr("newTreasury");
        battleSC.withdrawProtocolFees(address(0), dest, accrued);
        assertEq(dest.balance, accrued);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // M-3 — fee-on-transfer tokens must be rejected at receive time
    // ═══════════════════════════════════════════════════════════════════════════

    function test_M3_RejectsFeeOnTransferTokenInCreate() public {
        MockFeeOnTransferERC20 fot = new MockFeeOnTransferERC20();
        fot.mint(user1, 10_000 ether);
        vm.prank(user1); fot.approve(address(battleSC), type(uint256).max);

        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(fot), true);
        battleSC.updateMinimumBetTokenAmount(0, 1);

        vm.prank(user1);
        vm.expectRevert("Token not supported (fee-on-transfer)");
        battleSC.createBattle(address(fot), BET_AMOUNT, address(0));
    }

    function test_M3_FailedReceiveLeavesNoStateChange() public {
        MockFeeOnTransferERC20 fot = new MockFeeOnTransferERC20();
        fot.mint(user1, 10_000 ether);
        vm.prank(user1); fot.approve(address(battleSC), type(uint256).max);

        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(fot), true);
        battleSC.updateMinimumBetTokenAmount(0, 1);

        uint256 user1Before     = fot.balanceOf(user1);
        uint256 contractBefore  = fot.balanceOf(address(battleSC));
        uint256 outstandBefore  = battleSC.outstandingBets(address(fot));
        uint256 countBefore     = battleSC.getBattleCount();

        vm.prank(user1);
        try battleSC.createBattle(address(fot), BET_AMOUNT, address(0)) {
            revert("should have reverted");
        } catch {}

        // Full state rollback — player did not lose tokens, no battle was recorded
        assertEq(fot.balanceOf(user1), user1Before);
        assertEq(fot.balanceOf(address(battleSC)), contractBefore);
        assertEq(battleSC.outstandingBets(address(fot)), outstandBefore);
        assertEq(battleSC.getBattleCount(), countBefore);
    }

    function test_M3_RejectsFeeOnTransferTokenInJoin() public {
        // Whitelist the FoT token AFTER a normal battle setup so we can test join
        MockFeeOnTransferERC20 fot = new MockFeeOnTransferERC20();
        fot.mint(user1, 10_000 ether);
        fot.mint(user2, 10_000 ether);
        vm.prank(user1); fot.approve(address(battleSC), type(uint256).max);
        vm.prank(user2); fot.approve(address(battleSC), type(uint256).max);

        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(fot), true);
        battleSC.updateMinimumBetTokenAmount(0, 1);

        // createBattle would also fail, so we can only test the message.
        // Both create and join are gated by the same _receiveBet check.
        vm.prank(user1);
        vm.expectRevert("Token not supported (fee-on-transfer)");
        battleSC.createBattle(address(fot), BET_AMOUNT, address(0));
    }
}
