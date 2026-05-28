// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract HeroArenaChallenges is AccessControl {
    bytes32 public constant CHALLENGE_ADMIN_ROLE = keccak256("CHALLENGE_ADMIN_ROLE");

    /// @notice Reserved sentinel returned by getLevelIdBatch for challengeIds
    ///         that do not exist. levelId of `INVALID_LEVEL_ID` can never be
    ///         configured, so callers can distinguish a real levelId 0 from a
    ///         missing challenge.
    uint8 public constant INVALID_LEVEL_ID = type(uint8).max;

    // Mapping the number of challenges for each levelId
    mapping(uint8 => uint256) public lvCount;

    // Used for generating the challengeId when every new user win the PvE game
    uint256 private _challengeCounter;

    // Mapping if the user has already submit for a specific levelId
    mapping(address => mapping(uint8 => bool)) private _lvSubmits;

    // Mapping the lvId for each challengId
    mapping(uint256 => uint8) private _lvIds;

    // Mapping the name of levels
    mapping(uint8 => string) private _lvNames;

    // Mapping the reward points of levels
    mapping(uint8 => uint256) private _lvRewardPoints;

    /// @notice Tracks which levelIds have been configured via
    ///         setLevelNameAndRewardPoints(). submit() requires the level to be
    ///         configured first so a never-touched levelId cannot accept
    ///         submissions.
    mapping(uint8 => bool) public lvConfigured;

    /// @notice Emitted when a level's display name and reward points are set.
    event LevelMetadataUpdated(uint8 indexed lvId, string lvName, uint256 lvPts);

    modifier onlyChallengeAdmin() {
        require(hasRole(CHALLENGE_ADMIN_ROLE, msg.sender), "Not a challenge admin role");
        _;
    }

    /**
     * @dev Grants both DEFAULT_ADMIN_ROLE and CHALLENGE_ADMIN_ROLE to the
     *      deployer so the contract is operational immediately. The deployer
     *      should then grant CHALLENGE_ADMIN_ROLE to HeroArenaMeetTheCouncil
     *      and renounce its own challenge-admin role if desired.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CHALLENGE_ADMIN_ROLE, msg.sender);
    }

    /**
     * Submit a result of challenge, only the challenge admin can call it.
     */
    function submit(address _to, uint8 _lvId) external onlyChallengeAdmin returns (uint256) {
        require(_to != address(0), "Recipient cannot be zero");
        require(lvConfigured[_lvId], "Level not configured");
        require(!_lvSubmits[_to][_lvId], "User can only submit once");
        _lvSubmits[_to][_lvId] = true;
        _challengeCounter += 1;
        uint256 _newChallengeId = _challengeCounter;
        _lvIds[_newChallengeId] = _lvId;
        lvCount[_lvId] += 1;
        return _newChallengeId;
    }

    /**
     * Set a unique name and reward points for each levelId. The levelId is
     * also marked as configured so submit() will accept it.
     */
    function setLevelNameAndRewardPoints(uint8 _lvId, string calldata _lvName, uint256 _lvPts) external onlyChallengeAdmin {
        require(_lvId != INVALID_LEVEL_ID, "Reserved lvId");
        _lvNames[_lvId] = _lvName;
        _lvRewardPoints[_lvId] = _lvPts;
        lvConfigured[_lvId] = true;
        emit LevelMetadataUpdated(_lvId, _lvName, _lvPts);
    }

    /**
     * @notice Returns true if the given challengeId currently corresponds to a
     *         recorded submission (counter range 1.._challengeCounter).
     */
    function challengeExists(uint256 _challengeId) external view returns (bool) {
        return _challengeId != 0 && _challengeId <= _challengeCounter;
    }

    /**
     *
     * Get level's reward points
     */
    function getLevelRewardPoints(uint8 _lvId) external view returns (uint256) {
        return _lvRewardPoints[_lvId];
    }

    /**
     * Get status if the user has already submit this level.
     */
    function getSubmitStatus(address _to, uint8 _lvId) external view returns (bool) {
        return _lvSubmits[_to][_lvId];
    }

    /**
     * Get levelIds for a group of specific challengeIds.
     * @dev Returns INVALID_LEVEL_ID (255) for challengeIds that have never been
     *      submitted. Callers MUST treat 255 as "no challenge" rather than a
     *      real levelId — the default mapping value 0 is itself a valid lvId.
     */
    function getLevelIdBatch(uint256[] calldata _challengeIds) external view returns (uint8[] memory) {
        uint8[] memory _Ids = new uint8[](_challengeIds.length);
        uint256 maxId = _challengeCounter;
        for (uint256 i = 0; i < _challengeIds.length; i++) {
            uint256 cid = _challengeIds[i];
            if (cid == 0 || cid > maxId) {
                _Ids[i] = INVALID_LEVEL_ID;
            } else {
                _Ids[i] = _lvIds[cid];
            }
        }
        return _Ids;
    }

    /**
     * To get a group of levels' names
     */
    function getLevelNameAndPointsBatch(uint8[] calldata _Ids) external view returns (string[] memory, uint256[] memory) {
        require(_Ids.length < 1001, "Group size must be < 1001");

        string[] memory _names = new string[](_Ids.length);
        uint256[] memory _rewardPoints = new uint256[](_Ids.length);
        for (uint256 i = 0; i < _Ids.length; i++) {
            _names[i] = _lvNames[_Ids[i]];
            _rewardPoints[i] = _lvRewardPoints[_Ids[i]];
        }
        return (_names, _rewardPoints);
    }
}
