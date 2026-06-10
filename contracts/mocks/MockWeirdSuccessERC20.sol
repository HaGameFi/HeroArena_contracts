// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/**
 * @notice Mock "ERC20" whose transfer() actually moves balances correctly but
 *         returns a non-zero, non-one uint256 value (here `2`) instead of the
 *         canonical `1`. Used to verify the AME fix: HeroArenaBattle._tryPayout
 *         must treat any non-zero 32-byte return as success, otherwise it would
 *         credit pendingPayouts in addition to the already-delivered transfer
 *         and produce duplicate payouts on later claim.
 *
 *         Only the bits HeroArenaBattle touches are implemented — transfer(),
 *         balanceOf(), and a mint helper for tests.
 */
contract MockWeirdSuccessERC20 {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address who) external view returns (uint256) {
        return _balances[who];
    }

    /// @notice Performs a real balance update and returns the (non-canonical)
    ///         value 2 as a 32-byte word.
    function transfer(address to, uint256 amount) external returns (uint256) {
        require(_balances[msg.sender] >= amount, "balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return 2;
    }
}
