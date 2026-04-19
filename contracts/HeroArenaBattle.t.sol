// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaBattle} from "./HeroArenaBattle.sol";
import {HeroArenaProfile} from "./HeroArenaProfile.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaBattleTest is Test {
    HeroArenaBattle battleSC;
    HeroArenaProfile profileSC;

    MockERC20 hapToken;
    MockERC20 betToken;
    MockERC20 feeToken;
    MockERC20 bonusToken;

    address ownerAddr;
    address user1;
    address user2;
    address liquidatorAddr;
    address stranger;

    uint256 constant BET_AMOUNT   = 1 ether;
    uint256 constant FEE_AMOUNT   = 0.1 ether;
    uint256 constant BONUS_AMOUNT = 0.5 ether;

    bytes32 constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    function setUp() public {
        ownerAddr      = address(this);
        user1          = makeAddr("user1");
        user2          = makeAddr("user2");
        liquidatorAddr = makeAddr("liquidator");
        stranger       = makeAddr("stranger");

        // Deploy profile (free registration)
        hapToken  = new MockERC20();
        profileSC = new HeroArenaProfile(IERC20(address(hapToken)), 0, 0);
        profileSC.addTeam("Warriors", "Warriors team");
        vm.prank(user1); profileSC.createProfile(1);
        vm.prank(user2); profileSC.createProfile(1);

        // Deploy tokens
        betToken   = new MockERC20();
        feeToken   = new MockERC20();
        bonusToken = new MockERC20();

        // Deploy battle contract
        battleSC = new HeroArenaBattle(profileSC);
        battleSC.grantRole(LIQUIDATOR_ROLE, liquidatorAddr);

        // Fund users
        betToken.mint(user1, 10_000 ether);
        betToken.mint(user2, 10_000 ether);
        feeToken.mint(user1, 10_000 ether);
        feeToken.mint(user2, 10_000 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(stranger, 100 ether);

        vm.prank(user1); betToken.approve(address(battleSC), type(uint256).max);
        vm.prank(user2); betToken.approve(address(battleSC), type(uint256).max);
        vm.prank(user1); feeToken.approve(address(battleSC), type(uint256).max);
        vm.prank(user2); feeToken.approve(address(battleSC), type(uint256).max);
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _enableNative() internal {
        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(0), true);
        battleSC.updateMinimunBetTokenAmount(0.01 ether, 0);
    }

    function _enableERC20() internal {
        battleSC.updateAvailableCreateBattle(true);
        battleSC.updateAllowedBetToken(address(betToken), true);
        battleSC.updateMinimunBetTokenAmount(0, 1);
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
    // updateFeeAndBounsTokenAddressWithAmount
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateFeeAndBonus_SetsValues() public {
        battleSC.updateFeeAndBounsTokenAddressWithAmount(
            address(feeToken), FEE_AMOUNT, address(bonusToken), BONUS_AMOUNT
        );
        assertEq(battleSC.tokenAddresses(0), address(feeToken));
        assertEq(battleSC.tokenAddresses(1), address(bonusToken));
        assertEq(battleSC.tokenAmounts(0), FEE_AMOUNT);
        assertEq(battleSC.tokenAmounts(1), BONUS_AMOUNT);
    }

    function test_UpdateFeeAndBonus_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaBattle.FeeTokenAndBounsTokenUpdated(
            ownerAddr, address(feeToken), FEE_AMOUNT, address(bonusToken), BONUS_AMOUNT
        );
        battleSC.updateFeeAndBounsTokenAddressWithAmount(
            address(feeToken), FEE_AMOUNT, address(bonusToken), BONUS_AMOUNT
        );
    }

    function test_UpdateFeeAndBonus_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateFeeAndBounsTokenAddressWithAmount(address(feeToken), 1, address(0), 0);
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
    // updateMinimunBetTokenAmount
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpdateMinBet_SetsValues() public {
        battleSC.updateMinimunBetTokenAmount(0.5 ether, 10 ether);
        assertEq(battleSC.minBetAmount(0), 0.5 ether);
        assertEq(battleSC.minBetAmount(1), 10 ether);
    }

    function test_UpdateMinBet_RevertsIfNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.updateMinimunBetTokenAmount(1, 1);
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
        assertEq(battleSC.getBattleInfo(1).targetAddress, user2);
    }

    function test_CreateBattle_Native_RevertsIfWrongETHAmount() public {
        _enableNative();
        vm.prank(user1);
        vm.expectRevert("Incorrect ETH amount sent");
        battleSC.createBattle{value: 0.5 ether}(address(0), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_Native_RevertsBelowMinBet() public {
        _enableNative();
        battleSC.updateMinimunBetTokenAmount(2 ether, 0);
        vm.prank(user1);
        vm.expectRevert("Bet amount below minimum");
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, address(0));
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
        vm.expectRevert("BetToken not allowed");
        battleSC.createBattle(address(betToken), BET_AMOUNT, address(0));
    }

    function test_CreateBattle_WithFee_CollectsFee() public {
        _enableERC20();
        battleSC.updateFeeAndBounsTokenAddressWithAmount(address(feeToken), FEE_AMOUNT, address(0), 0);
        vm.prank(user1);
        battleSC.createBattle(address(betToken), BET_AMOUNT, address(0));
        assertEq(feeToken.balanceOf(address(battleSC)), FEE_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // createBattle — access control
    // ═══════════════════════════════════════════════════════════════════════════

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

    function test_JoinBattle_PrivateBattle_InvitedUserCanJoin() public {
        _enableNative();
        vm.prank(user1);
        battleSC.createBattle{value: BET_AMOUNT}(address(0), BET_AMOUNT, user2);
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(1);
        assertTrue(battleSC.getBattleInfo(1).isStarted);
    }

    function test_JoinBattle_WithFee_CollectsFee() public {
        _enableERC20();
        battleSC.updateFeeAndBounsTokenAddressWithAmount(address(feeToken), FEE_AMOUNT, address(0), 0);
        vm.prank(user1); battleSC.createBattle(address(betToken), BET_AMOUNT, address(0));
        vm.prank(user2); battleSC.joinExistBattle(1);
        assertEq(feeToken.balanceOf(address(battleSC)), FEE_AMOUNT * 2);
    }

    function test_JoinBattle_EmitsEvent() public {
        uint256 id = _createNativeOpenBattle();
        vm.expectEmit(true, true, false, false);
        emit HeroArenaBattle.BattleJoined(id, user2);
        vm.prank(user2);
        battleSC.joinExistBattle{value: BET_AMOUNT}(id);
    }

    function test_JoinBattle_RevertsIfBattleNotExist() public {
        _enableNative();
        vm.prank(user2);
        vm.expectRevert("Battle does not exist");
        battleSC.joinExistBattle{value: BET_AMOUNT}(999);
    }

    function test_JoinBattle_RevertsIfAlreadyStarted() public {
        uint256 id = _startNativeBattle();
        address user3 = makeAddr("user3");
        vm.prank(user3); profileSC.createProfile(1);
        vm.deal(user3, 10 ether);
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
        address user3 = makeAddr("user3");
        vm.prank(user3); profileSC.createProfile(1);
        vm.deal(user3, 10 ether);
        vm.prank(user3);
        vm.expectRevert("Not invited to this battle");
        battleSC.joinExistBattle{value: BET_AMOUNT}(1);
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
        battleSC.updateFeeAndBounsTokenAddressWithAmount(address(0), 0, address(bonusToken), BONUS_AMOUNT);
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
        vm.expectRevert("Not an liquidator role");
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
    // claimTokens
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ClaimTokens_TransfersETH() public {
        _startNativeBattle();
        address dest = makeAddr("dest");
        address[] memory tokens = new address[](0);
        battleSC.claimTokens(dest, tokens);
        assertEq(dest.balance, BET_AMOUNT * 2);
    }

    function test_ClaimTokens_TransfersERC20() public {
        _startERC20Battle();
        address dest = makeAddr("dest");
        address[] memory tokens = new address[](1);
        tokens[0] = address(betToken);
        battleSC.claimTokens(dest, tokens);
        assertEq(betToken.balanceOf(dest), BET_AMOUNT * 2);
    }

    function test_ClaimTokens_SkipsZeroAddressToken() public {
        address dest = makeAddr("dest");
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);
        battleSC.claimTokens(dest, tokens);
    }

    function test_ClaimTokens_RevertsIfInvalidDestination() public {
        address[] memory tokens = new address[](0);
        vm.expectRevert("Invalid destination");
        battleSC.claimTokens(address(0), tokens);
    }

    function test_ClaimTokens_RevertsIfNotOwner() public {
        address[] memory tokens = new address[](0);
        vm.prank(stranger);
        vm.expectRevert();
        battleSC.claimTokens(stranger, tokens);
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
}
