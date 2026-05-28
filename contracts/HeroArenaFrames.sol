// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HeroArenaFrames is ERC721Enumerable, Ownable {
    /// @notice Reserved sentinel returned by getFrameIdBatch for tokenIds that do
    ///         not exist or have been burned. frameId of `INVALID_FRAME_ID` can
    ///         never be minted, so callers can distinguish a real frameId 0 from
    ///         a missing token.
    uint8 public constant INVALID_FRAME_ID = type(uint8).max;

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

    /// @notice Emitted when a frame type's display metadata is configured.
    event FrameMetadataUpdated(uint8 indexed frameId, string name, uint256 createdAt);

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
     * @dev Minting and burning are centralized to the owner role; the owner is
     *      intended to be transferred to a multisig after deployment.
     *      INVALID_FRAME_ID is forbidden so the batch lookup sentinel cannot
     *      collide with a real frameId.
     */
    function mint(address _to, uint8 _frameId) external onlyOwner returns (uint256) {
        require(_frameId != INVALID_FRAME_ID, "Reserved frameId");
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
        emit FrameMetadataUpdated(_frameId, _frameName, block.timestamp);
    }

    /**
     * Burn a NFT, only the owner can call it.
     * @dev See the governance comment on mint(). The ERC721 Transfer(...to=0)
     *      event emitted by _burn is the canonical record of burns.
     */
    function burn(uint256 _tokenId) external onlyOwner {
        uint8 _frameId = _frameIds[_tokenId];
        frameCount[_frameId] -= 1;
        frameBurnCount[_frameId] += 1;
        delete _frameIds[_tokenId];
        _burn(_tokenId);
    }

    /**
     * @notice Returns true if the given token currently exists (minted and not burned).
     */
    function tokenExists(uint256 _tokenId) external view returns (bool) {
        return _ownerOf(_tokenId) != address(0);
    }

    /**
     * Get frameIds for a group of specific tokenId.
     * @dev Returns INVALID_FRAME_ID (255) for tokenIds that do not exist or
     *      have been burned. Callers MUST treat 255 as "no token" rather than
     *      a real frameId — the default mapping value 0 is itself a valid frameId.
     */
    function getFrameIdBatch(uint256[] calldata _tokenIds) external view returns (uint8[] memory) {
        uint8[] memory _Ids = new uint8[](_tokenIds.length);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (_ownerOf(_tokenIds[i]) == address(0)) {
                _Ids[i] = INVALID_FRAME_ID;
            } else {
                _Ids[i] = _frameIds[_tokenIds[i]];
            }
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
