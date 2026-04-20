// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface HeroArenaProfileInterface {
    function hasRegistered(address user) external view returns (bool);
}
