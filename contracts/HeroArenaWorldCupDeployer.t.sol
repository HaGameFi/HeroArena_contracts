// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {HeroArenaWorldCupDeployer} from "./HeroArenaWorldCupDeployer.sol";
import {HeroArenaWorldCupInitializable} from "./HeroArenaWorldCupInitializable.sol";
import {HeroArenaProfileInterface} from "./interfaces/HeroArenaProfileInterface.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockHeroArenaProfile} from "./mocks/MockHeroArenaProfile.sol";

contract HeroArenaWorldCupDeployerTest is Test {
    HeroArenaWorldCupDeployer deployer;
    MockERC20 hap;
    MockERC20 bonusTok;
    MockHeroArenaProfile profile;

    address admin;
    address stranger;

    uint256 constant REG_FEE = 100e18;
    bytes32 constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    function setUp() public {
        admin    = makeAddr("admin");
        stranger = makeAddr("stranger");

        hap      = new MockERC20();
        bonusTok = new MockERC20();
        profile  = new MockHeroArenaProfile();

        deployer = new HeroArenaWorldCupDeployer(
            hap,
            REG_FEE,
            HeroArenaProfileInterface(address(profile))
        );
    }

    // ═════════════════════════════════════════════════════════════════════════
    // constructor
    // ═════════════════════════════════════════════════════════════════════════

    function test_Constructor_SetsDeps() public view {
        assertEq(address(deployer.HapToken()), address(hap));
        assertEq(deployer.registrationFee(), REG_FEE);
        assertEq(address(deployer.HeroArenaProfileSC()), address(profile));
        assertEq(deployer.owner(), address(this));
    }

    function test_Constructor_RejectsZeroHap() public {
        vm.expectRevert("HapToken cannot be zero");
        new HeroArenaWorldCupDeployer(MockERC20(address(0)), REG_FEE, HeroArenaProfileInterface(address(profile)));
    }

    function test_Constructor_RejectsZeroProfile() public {
        vm.expectRevert("Profile SC cannot be zero");
        new HeroArenaWorldCupDeployer(hap, REG_FEE, HeroArenaProfileInterface(address(0)));
    }

    // ═════════════════════════════════════════════════════════════════════════
    // createWC — happy path & dependency forwarding (C-1)
    // ═════════════════════════════════════════════════════════════════════════

    function test_CreateWC_DeploysAndInitializes() public {
        deployer.createWC(admin, address(0), 0);
        address wcAddr = deployer.currentWCAddress();
        assertTrue(wcAddr != address(0));

        HeroArenaWorldCupInitializable wc = HeroArenaWorldCupInitializable(payable(wcAddr));
        // C-1: deps are forwarded into the deployed contract
        assertEq(address(wc.HapToken()), address(hap));
        assertEq(wc.registrationFee(), REG_FEE);
        assertEq(address(wc.HeroArenaProfileSC()), address(profile));
        // admin owns it and is a liquidator (H-3)
        assertEq(wc.owner(), admin);
        assertTrue(wc.hasRole(wc.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(wc.hasRole(LIQUIDATOR_ROLE, admin));
    }

    function test_CreateWC_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        deployer.createWC(admin, address(0), 0);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // H-2: admin zero-address guard
    // ═════════════════════════════════════════════════════════════════════════

    function test_CreateWC_RejectsZeroAdmin() public {
        vm.expectRevert("admin cannot be zero");
        deployer.createWC(address(0), address(0), 0);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // M-3: bonus token must be a contract
    // ═════════════════════════════════════════════════════════════════════════

    function test_CreateWC_RejectsEoaBonusToken() public {
        vm.expectRevert("Bonus token must be a contract");
        deployer.createWC(admin, stranger, 1e18); // stranger is an EOA
    }

    function test_CreateWC_AcceptsContractBonusToken() public {
        deployer.createWC(admin, address(bonusTok), 1e18);
        HeroArenaWorldCupInitializable wc =
            HeroArenaWorldCupInitializable(payable(deployer.currentWCAddress()));
        assertEq(wc.bonusToken(), address(bonusTok));
        assertEq(wc.bonusAmount(), 1e18);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // H-1: nonce-based salt lets identical params deploy twice without collision
    // ═════════════════════════════════════════════════════════════════════════

    function test_CreateWC_SameParamsTwiceProducesDistinctContracts() public {
        deployer.createWC(admin, address(0), 0);
        address first = deployer.currentWCAddress();

        // identical params — would collide under a nonce-less salt
        deployer.createWC(admin, address(0), 0);
        address second = deployer.currentWCAddress();

        assertTrue(first != address(0) && second != address(0));
        assertTrue(first != second, "H-1: distinct addresses via deployNonce");
        assertEq(deployer.deployNonce(), 2);
    }

    // ═════════════════════════════════════════════════════════════════════════
    // recoverWrongTokens
    // ═════════════════════════════════════════════════════════════════════════

    function test_RecoverWrongTokens() public {
        bonusTok.mint(address(deployer), 7e18);
        uint256 before = bonusTok.balanceOf(address(this));
        deployer.recoverWrongTokens(address(bonusTok));
        assertEq(bonusTok.balanceOf(address(this)) - before, 7e18);
    }

    function test_RecoverWrongTokens_RevertsOnZeroBalance() public {
        vm.expectRevert("Operations: Balance must be > 0");
        deployer.recoverWrongTokens(address(bonusTok));
    }

    function test_RecoverWrongTokens_OnlyOwner() public {
        bonusTok.mint(address(deployer), 1e18);
        vm.prank(stranger);
        vm.expectRevert();
        deployer.recoverWrongTokens(address(bonusTok));
    }
}
