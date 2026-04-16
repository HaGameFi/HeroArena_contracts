// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    uint256 private _nextTokenId;

    constructor() ERC721("Mock NFT", "MNFT") {}

    function mint(address to) external returns (uint256) {
        _nextTokenId += 1;
        _mint(to, _nextTokenId);
        return _nextTokenId;
    }
}
