// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// A contract that implements supportsInterface but is NOT an ERC721.
/// Used in tests to trigger the "Not ERC721" require in addAvatarAddress.
contract MockNonERC721 is IERC165 {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}
