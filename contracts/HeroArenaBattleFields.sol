// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HeroArenaBattleFields is ERC721Enumerable, Ownable {
    /// @notice Reserved sentinel returned by getBattleFieldIdBatch for tokenIds that do
    ///         not exist or have been burned. battleFieldId of `INVALID_BATTLEFIELD_ID` can
    ///         never be minted, so callers can distinguish a real battleFieldId 0 from
    ///         a missing token.
    uint8 public constant INVALID_BATTLEFIELD_ID = type(uint8).max;

    // Mapping the number of tokens for each battleFieldId
    mapping(uint8 => uint256) public battleFieldCount;

    // Mapping the number of tokens burn for each battleFieldId
    mapping(uint8 => uint256) public battleFieldBurnCount;

    // Used for generating the tokenId when every new NFT minted
    uint256 private _tokenCounter;

    // Mapping the battleFieldId for each tokenId
    mapping(uint256 => uint8) private _battleFieldIds;

    // Mapping the name of battleFields
    mapping(uint8 => string) private _battleFieldNames;

    // Mapping the timestamp of battleFields
    mapping(uint8 => uint256) private _battleFieldCreatedTimestamps;

    /// @notice Emitted when an battleField type's display metadata is configured.
    event BattleFieldMetadataUpdated(uint8 indexed battleFieldId, string name, uint256 createdAt);

    constructor() ERC721("HA BattleFields", "HAB") Ownable(msg.sender) {

    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "battleFields/";
    }

    /**
     * Mint a NFT, only the owner can call it.
     * @dev Minting and burning are centralized to the owner role; the owner is
     *      intended to be transferred to a multisig after deployment.
     *      INVALID_BATTLEFIELD_ID is forbidden so the batch lookup sentinel cannot
     *      collide with a real battleFieldId.
     */
    function mint(address _to, uint8 _battleFieldId) external onlyOwner returns (uint256) {
        require(_battleFieldId != INVALID_BATTLEFIELD_ID, "Reserved battleFieldId");
        _tokenCounter += 1;
        uint256 _newTokenId = _tokenCounter;
        _battleFieldIds[_newTokenId] = _battleFieldId;
        battleFieldCount[_battleFieldId] += 1;
        _mint(_to, _newTokenId);
        return _newTokenId;
    }

    /**
     * Set a unique name for each battleFieldId, only the owner can call it.
     */
    function setBattleFieldNameAndCreatedTimestamp(uint8 _battleFieldId, string calldata _battleFieldName) external onlyOwner {
        _battleFieldNames[_battleFieldId] = _battleFieldName;
        _battleFieldCreatedTimestamps[_battleFieldId] = block.timestamp;
        emit BattleFieldMetadataUpdated(_battleFieldId, _battleFieldName, block.timestamp);
    }

    /**
     * Burn a NFT, only the owner can call it.
     * @dev See the governance comment on mint(). The ERC721 Transfer(...to=0)
     *      event emitted by _burn is the canonical record of burns.
     */
    function burn(uint256 _tokenId) external onlyOwner {
        uint8 _battleFieldId = _battleFieldIds[_tokenId];
        battleFieldCount[_battleFieldId] -= 1;
        battleFieldBurnCount[_battleFieldId] += 1;
        delete _battleFieldIds[_tokenId];
        _burn(_tokenId);
    }

    /**
     * @notice Returns true if the given token currently exists (minted and not burned).
     */
    function tokenExists(uint256 _tokenId) external view returns (bool) {
        return _ownerOf(_tokenId) != address(0);
    }

    /**
     * Get battleFieldIds for a group of specific tokenId.
     * @dev Returns INVALID_BATTLEFIELD_ID (255) for tokenIds that do not exist or
     *      have been burned. Callers MUST treat 255 as "no token" rather than
     *      a real battleFieldId — the default mapping value 0 is itself a valid battleFieldId.
     */
    function getBattleFieldIdBatch(uint256[] calldata _tokenIds) external view returns (uint8[] memory) {
        uint8[] memory _Ids = new uint8[](_tokenIds.length);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (_ownerOf(_tokenIds[i]) == address(0)) {
                _Ids[i] = INVALID_BATTLEFIELD_ID;
            } else {
                _Ids[i] = _battleFieldIds[_tokenIds[i]];
            }
        }
        return _Ids;
    }

    /**
     * Returns whether an owner currently holds at least one token of a specific
     * battleFieldId. Transferred and burned tokens are automatically excluded
     * because ERC721Enumerable only enumerates the owner's current tokens.
     */
    function hasBattleField(address _owner, uint8 _battleFieldId) external view returns (bool) {
        uint256 balance = balanceOf(_owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_owner, i);
            if (_battleFieldIds[tokenId] == _battleFieldId) {
                return true;
            }
        }
        return false;
    }

    /**
     * To get a group of battleFields' names and timestamps
     */
    function getBattleFieldNameAndCreatedTimestampBatch(uint8[] calldata _Ids) external view returns (string[] memory, uint256[] memory) {
        require(_Ids.length < 1001, "Group size must be < 1001");

        string[] memory _names = new string[](_Ids.length);
        uint256[] memory _timestamps = new uint256[](_Ids.length);
        for (uint256 i = 0; i < _Ids.length; i++) {
            _names[i] = _battleFieldNames[_Ids[i]];
            _timestamps[i] = _battleFieldCreatedTimestamps[_Ids[i]];
        }
        return (_names, _timestamps);
    }

    /**
     * To get a user's total battleFields in one time.
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
