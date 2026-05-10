// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/**
 * @notice Contract that always reverts when receiving ETH.
 * @dev Used to verify that HeroArenaBattle.settleBattle's protocol-fee push
 *      gracefully falls back to accrual when the recipient is unreachable.
 */
contract MockRevertingReceiver {
    error CannotReceive();

    receive() external payable {
        revert CannotReceive();
    }

    fallback() external payable {
        revert CannotReceive();
    }
}
