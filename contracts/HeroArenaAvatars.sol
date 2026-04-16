// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HeroArenaAvatars is ERC721Enumerable, Ownable {
    // Mapping the number of tokens for each avatarId
    mapping(uint8 => uint256) public avatarCount;

    // Mapping the number of tokens burn for each avatarId
    mapping(uint8 => uint256) public avatarBurnCount;

    // Used for generating the tokenId when every new NFT minted
    uint256 private _tokenCounter;

    // Mapping the avatarId for each tokenId
    mapping(uint256 => uint8) private _avatarIds;

    // Mapping the name of avatars 
    mapping(uint8 => string) private _avatarNames;

    // Mapping the timestamp of avatars 
    mapping(uint8 => uint256) private _avatarCreatedTimestamps;

    constructor() ERC721("HA Avatars", "HAA") Ownable(msg.sender) {

    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "avatars/";
    }

    /**
     * Mint a NFT, only the owner can call it.
     */
    function mint(address _to, uint8 _avatarId) external onlyOwner returns (uint256) {
        _tokenCounter += 1;
        uint256 _newTokenId = _tokenCounter;
        _avatarIds[_newTokenId] = _avatarId;
        avatarCount[_avatarId] += 1;
        _mint(_to, _newTokenId);
        return _newTokenId;
    }

    /**
     * Set a unique name for each avatarId, only the owner can call it.
     */
    function setAvatarNameAndCreatedTimestamp(uint8 _avatarId, string calldata _avatarName) external onlyOwner {
        _avatarNames[_avatarId] = _avatarName;
        _avatarCreatedTimestamps[_avatarId] = block.timestamp;
    }

    /**
     * Burn a NFT, only the owner can call it.
     */
    function burn(uint256 _tokenId) external onlyOwner {
        uint8 _avatarId = _avatarIds[_tokenId];
        avatarCount[_avatarId] -= 1;
        avatarBurnCount[_avatarId] += 1;
        delete _avatarIds[_tokenId];
        _burn(_tokenId);
    }

    /**
     * To get a group of avatars' names and timestamps
     */
    function getAvatarNameAndCreatedTimestampsBatch(uint8[] calldata _Ids) external view returns (string[] memory, uint256[] memory) {
        require(_Ids.length < 1001, "Group size must be < 1001");
        
        string[] memory names = new string[](_Ids.length);
        uint256[] memory timestamps = new uint256[](_Ids.length);
        for (uint256 i = 0; i < _Ids.length; i++) {
            names[i] = _avatarNames[_Ids[i]];
            timestamps[i] = _avatarCreatedTimestamps[_Ids[i]];
        }
        return (names, timestamps);
    }

    /**
     * To get a user's total avatars in one time.
     */
    function getTokensByOwner(address _owner) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }
}