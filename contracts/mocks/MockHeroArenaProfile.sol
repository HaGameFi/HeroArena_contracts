// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {HeroArenaProfileInterface} from "../interfaces/HeroArenaProfileInterface.sol";

/**
 * @notice Minimal stand-in for HeroArenaProfile used by the WorldCup tests.
 *         Lets a test toggle whether an address "owns a profile".
 */
contract MockHeroArenaProfile is HeroArenaProfileInterface {
    mapping(address => bool) public registered;

    function setRegistered(address user, bool value) external {
        registered[user] = value;
    }

    function hasRegistered(address user) external view override returns (bool) {
        return registered[user];
    }
}
