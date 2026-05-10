// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice Mock token that takes a 1 % fee on every transfer.
 * @dev Used to verify that HeroArenaBattle._receiveBet correctly detects and
 *      rejects fee-on-transfer / rebasing tokens.
 */
contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public constant FEE_BPS = 100; // 1 %

    constructor() ERC20("MockFoT", "FoT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        // Burn 1 % on transfer (skip on mint/burn where from/to is zero).
        if (from != address(0) && to != address(0) && value > 0) {
            uint256 fee = (value * FEE_BPS) / 10000;
            if (fee > 0) {
                super._update(from, address(0), fee); // burn the fee
                value -= fee;
            }
        }
        super._update(from, to, value);
    }
}
