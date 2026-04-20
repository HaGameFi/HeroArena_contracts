// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HeroArenaSwap} from "./HeroArenaSwap.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract HeroArenaSwapTest is Test {
    HeroArenaSwap swap;
    MockERC20     hapToken;

    address owner;
    address user1;
    address user2;

    // 1 ETH → 5000 HAP
    uint256 constant INITIAL_RATE     = 5000 * 10 ** 18;
    uint256 constant HAP_DEPOSIT      = 100_000 * 10 ** 18;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        hapToken = new MockERC20();
        swap     = new HeroArenaSwap(address(hapToken), INITIAL_RATE);

        // Fund owner with HAP and approve swap contract
        hapToken.mint(owner, HAP_DEPOSIT);
        hapToken.approve(address(swap), type(uint256).max);

        // Give test users some ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // constructor
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsHapToken() public view {
        assertEq(address(swap.HapToken()), address(hapToken));
    }

    function test_Constructor_SetsRate() public view {
        assertEq(swap.rate(), INITIAL_RATE);
    }

    function test_Constructor_SwapEnabledByDefault() public view {
        assertTrue(swap.swapEnabled());
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(swap.owner(), owner);
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert("Invalid HAP token address");
        new HeroArenaSwap(address(0), INITIAL_RATE);
    }

    function test_Constructor_RevertsOnZeroRate() public {
        vm.expectRevert("Rate must be > 0");
        new HeroArenaSwap(address(hapToken), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setRate
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetRate_UpdatesRate() public {
        uint256 newRate = 10_000 * 10 ** 18;
        swap.setRate(newRate);
        assertEq(swap.rate(), newRate);
    }

    function test_SetRate_EmitsEvent() public {
        uint256 newRate = 10_000 * 10 ** 18;
        vm.expectEmit(false, false, false, true);
        emit HeroArenaSwap.RateUpdated(INITIAL_RATE, newRate);
        swap.setRate(newRate);
    }

    function test_SetRate_RevertsOnZeroRate() public {
        vm.expectRevert("Rate must be > 0");
        swap.setRate(0);
    }

    function test_SetRate_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        swap.setRate(1000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // setSwapEnabled
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetSwapEnabled_DisablesSwap() public {
        swap.setSwapEnabled(false);
        assertFalse(swap.swapEnabled());
    }

    function test_SetSwapEnabled_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit HeroArenaSwap.SwapEnabledUpdated(false);
        swap.setSwapEnabled(false);
    }

    function test_SetSwapEnabled_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        swap.setSwapEnabled(false);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // depositHap
    // ═══════════════════════════════════════════════════════════════════════════

    function test_DepositHap_TransfersTokensToContract() public {
        swap.depositHap(HAP_DEPOSIT);
        assertEq(hapToken.balanceOf(address(swap)), HAP_DEPOSIT);
    }

    function test_DepositHap_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit HeroArenaSwap.HapDeposited(owner, HAP_DEPOSIT);
        swap.depositHap(HAP_DEPOSIT);
    }

    function test_DepositHap_RevertsOnZeroAmount() public {
        vm.expectRevert("Amount must be > 0");
        swap.depositHap(0);
    }

    function test_DepositHap_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        swap.depositHap(1000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // withdrawHap
    // ═══════════════════════════════════════════════════════════════════════════

    function test_WithdrawHap_TransfersTokensToOwner() public {
        swap.depositHap(HAP_DEPOSIT);
        uint256 before = hapToken.balanceOf(owner);
        swap.withdrawHap(HAP_DEPOSIT);
        assertEq(hapToken.balanceOf(owner), before + HAP_DEPOSIT);
    }

    function test_WithdrawHap_EmitsEvent() public {
        swap.depositHap(HAP_DEPOSIT);
        vm.expectEmit(true, false, false, true);
        emit HeroArenaSwap.HapWithdrawn(owner, HAP_DEPOSIT);
        swap.withdrawHap(HAP_DEPOSIT);
    }

    function test_WithdrawHap_RevertsOnZeroAmount() public {
        swap.depositHap(HAP_DEPOSIT);
        vm.expectRevert("Amount must be > 0");
        swap.withdrawHap(0);
    }

    function test_WithdrawHap_RevertsOnInsufficientBalance() public {
        vm.expectRevert("Insufficient HAP balance");
        swap.withdrawHap(1);
    }

    function test_WithdrawHap_RevertsIfNotOwner() public {
        swap.depositHap(HAP_DEPOSIT);
        vm.prank(user1);
        vm.expectRevert();
        swap.withdrawHap(HAP_DEPOSIT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // withdrawNativeToken
    // ═══════════════════════════════════════════════════════════════════════════

    function test_WithdrawNativeToken_TransfersEthToOwner() public {
        // Send 1 ETH to contract first via swap
        swap.depositHap(HAP_DEPOSIT);
        vm.prank(user1);
        swap.swap{value: 1 ether}();

        uint256 before = owner.balance;
        swap.withdrawNativeToken(1 ether);
        assertEq(owner.balance, before + 1 ether);
    }

    function test_WithdrawNativeToken_EmitsEvent() public {
        swap.depositHap(HAP_DEPOSIT);
        vm.prank(user1);
        swap.swap{value: 1 ether}();

        vm.expectEmit(true, false, false, true);
        emit HeroArenaSwap.NativeTokenWithdrawn(owner, 1 ether);
        swap.withdrawNativeToken(1 ether);
    }

    function test_WithdrawNativeToken_RevertsOnZeroAmount() public {
        vm.expectRevert("Amount must be > 0");
        swap.withdrawNativeToken(0);
    }

    function test_WithdrawNativeToken_RevertsOnInsufficientBalance() public {
        vm.expectRevert("Insufficient ETH balance");
        swap.withdrawNativeToken(1 ether);
    }

    function test_WithdrawNativeToken_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        swap.withdrawNativeToken(1 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // swap
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Swap_TransfersHapToUser() public {
        swap.depositHap(HAP_DEPOSIT);
        uint256 ethIn  = 1 ether;
        uint256 hapOut = (ethIn * INITIAL_RATE) / 1 ether;

        vm.prank(user1);
        swap.swap{value: ethIn}();

        assertEq(hapToken.balanceOf(user1), hapOut);
    }

    function test_Swap_ContractReceivesEth() public {
        swap.depositHap(HAP_DEPOSIT);
        vm.prank(user1);
        swap.swap{value: 1 ether}();
        assertEq(address(swap).balance, 1 ether);
    }

    function test_Swap_EmitsEvent() public {
        swap.depositHap(HAP_DEPOSIT);
        uint256 ethIn  = 1 ether;
        uint256 hapOut = (ethIn * INITIAL_RATE) / 1 ether;

        vm.expectEmit(true, false, false, true);
        emit HeroArenaSwap.Swapped(user1, ethIn, hapOut);
        vm.prank(user1);
        swap.swap{value: ethIn}();
    }

    function test_Swap_RevertsWhenDisabled() public {
        swap.depositHap(HAP_DEPOSIT);
        swap.setSwapEnabled(false);
        vm.prank(user1);
        vm.expectRevert("Swap is disabled");
        swap.swap{value: 1 ether}();
    }

    function test_Swap_RevertsOnZeroEth() public {
        swap.depositHap(HAP_DEPOSIT);
        vm.prank(user1);
        vm.expectRevert("Must send Native token");
        swap.swap{value: 0}();
    }

    function test_Swap_RevertsOnInsufficientHap() public {
        // No HAP deposited
        vm.prank(user1);
        vm.expectRevert("Insufficient HAP in contract");
        swap.swap{value: 1 ether}();
    }

    function test_Swap_MultipleUsers() public {
        swap.depositHap(HAP_DEPOSIT);

        vm.prank(user1);
        swap.swap{value: 2 ether}();

        vm.prank(user2);
        swap.swap{value: 3 ether}();

        assertEq(hapToken.balanceOf(user1), (2 ether * INITIAL_RATE) / 1 ether);
        assertEq(hapToken.balanceOf(user2), (3 ether * INITIAL_RATE) / 1 ether);
        assertEq(address(swap).balance, 5 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // previewSwap
    // ═══════════════════════════════════════════════════════════════════════════

    function test_PreviewSwap_ReturnsCorrectAmount() public view {
        uint256 ethIn  = 2 ether;
        uint256 hapOut = swap.previewSwap(ethIn);
        assertEq(hapOut, (ethIn * INITIAL_RATE) / 1 ether);
    }

    function test_PreviewSwap_ZeroEthReturnsZero() public view {
        assertEq(swap.previewSwap(0), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // receive (plain ETH transfer)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Receive_AcceptsPlainEthTransfer() public {
        vm.deal(owner, 1 ether);
        (bool ok, ) = address(swap).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(swap).balance, 1 ether);
    }

    // Allow the test contract (= owner) to receive ETH from withdrawNativeToken
    receive() external payable {}
}
