// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HeroArenaFrames is ERC721Enumerable, Ownable {
    // Mapping the number of tokens for each frameId
    mapping(uint8 => uint256) public frameCount;

    // Mapping the number of tokens burn for each frameId
    mapping(uint8 => uint256) public frameBurnCount;

    // Used for generating the tokenId when every new NFT minted
    uint256 private _tokenCounter;

    // Mapping the frameId for each tokenId
    mapping(uint256 => uint8) private _frameIds;

    // Mapping the name of frames 
    mapping(uint8 => string) private _frameNames;

    // Mapping the timestamp of frames 
    mapping(uint8 => uint256) private _frameCreatedTimestamps;

    constructor() ERC721("HA Frames", "HAF") Ownable(msg.sender) {

    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "frames/";
    }

    /**
     * Mint a NFT, only the owner can call it.
     */
    function mint(address _to, uint8 _frameId) external onlyOwner returns (uint256) {
        _tokenCounter += 1;
        uint256 _newTokenId = _tokenCounter;
        _frameIds[_newTokenId] = _frameId;
        frameCount[_frameId] += 1;
        _mint(_to, _newTokenId);
        return _newTokenId;
    }

    /**
     * Set a unique name for each frameId, only the owner can call it.
     */
    function setFrameNameAndCreatedTimestamp(uint8 _frameId, string calldata _frameName) external onlyOwner {
        _frameNames[_frameId] = _frameName;
        _frameCreatedTimestamps[_frameId] = block.timestamp;
    }

    /**
     * Burn a NFT, only the owner can call it.
     */
    function burn(uint256 _tokenId) external onlyOwner {
        uint8 _frameId = _frameIds[_tokenId];
        frameCount[_frameId] -= 1;
        frameBurnCount[_frameId] += 1;
        delete _frameIds[_tokenId];
        _burn(_tokenId);
    }

    /**
     * Get frameIds for a group of specific tokenId.
     */
    function getFrameIdBatch(uint256[] calldata _tokenIds) external view returns (uint8[] memory) {
        uint8[] memory _Ids = new uint8[](_tokenIds.length);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _Ids[i] = _frameIds[_tokenIds[i]];
        }
        return _Ids;
    }

    /**
     * To get a group of frames' names and timestamps
     */
    function getFrameNameAndCreatedTimestampBatch(uint8[] calldata _Ids) external view returns (string[] memory, uint256[] memory) {
        require(_Ids.length < 1001, "Group size must be < 1001");
        
        string[] memory _names = new string[](_Ids.length);
        uint256[] memory _timestamps = new uint256[](_Ids.length);
        for (uint256 i = 0; i < _Ids.length; i++) {
            _names[i] = _frameNames[_Ids[i]];
            _timestamps[i] = _frameCreatedTimestamps[_Ids[i]];
        }
        return (_names, _timestamps);
    }

    /**
     * To get a user's total frames in one time.
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