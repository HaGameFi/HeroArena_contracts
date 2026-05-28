// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/**
 * @notice Mock "ERC20" whose transfer() returns 64 bytes of junk instead of
 *         the standard `bool` (32 bytes) or nothing (USDT-style).
 * @dev Used to verify the TCR fix: HeroArenaBattle._tryPayout must treat a
 *      malformed return payload as a failed transfer instead of letting
 *      abi.decode(ret, (bool)) revert and tear down the whole settlement.
 *
 *      Only the bits HeroArenaBattle actually touches are implemented —
 *      transfer(), balanceOf(), and a mint helper for tests.
 */
contract MockMalformedReturnERC20 {
    mapping(address => uint256) private _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address who) external view returns (uint256) {
        return _balances[who];
    }

    /// @notice Performs the balance update, then returns 64 bytes of junk so a
    ///         naïve `abi.decode(ret, (bool))` on a 64-byte payload would revert
    ///         (length mismatch for a single bool decode in the unfixed path).
    function transfer(address to, uint256 amount) external {
        require(_balances[msg.sender] >= amount, "balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        assembly {
            // Return 64 bytes: two 32-byte words (0x01, 0x01)
            mstore(0x00, 0x0000000000000000000000000000000000000000000000000000000000000001)
            mstore(0x20, 0x0000000000000000000000000000000000000000000000000000000000000001)
            return(0x00, 0x40)
        }
    }
}
