// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract HeroArenaChallenges is AccessControl {
    bytes32 public constant CHALLENGE_ADMIN_ROLE = keccak256("CHALLENGE_ADMIN_ROLE");

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

    modifier onlyChallengeAdmin() {
        require(hasRole(CHALLENGE_ADMIN_ROLE, msg.sender), "Not a challenge admin role");
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * Submit a result of challenge, only the owner can call it.
     */
    function submit(address _to, uint8 _lvId) external onlyChallengeAdmin returns (uint256) {
        require(!_lvSubmits[_to][_lvId], "User can only submit once");
        _lvSubmits[_to][_lvId] = true;
        _challengeCounter += 1;
        uint256 _newChallengeId = _challengeCounter;
        _lvIds[_newChallengeId] = _lvId;
        lvCount[_lvId] += 1;
        return _newChallengeId;
    }

    /**
     * Set a unique name and reward points for each levelId, only the owner can call it.
     */
    function setLevelNameAndRewardPoints(uint8 _lvId, string calldata _lvName, uint256 _lvPts) external onlyChallengeAdmin {
        _lvNames[_lvId] = _lvName;
        _lvRewardPoints[_lvId] = _lvPts;
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
     */
    function getLevelIdBatch(uint256[] calldata _challengeIds) external view returns (uint8[] memory) {
        uint8[] memory _Ids = new uint8[](_challengeIds.length);
        for (uint256 i = 0; i < _challengeIds.length; i++) {
            _Ids[i] = _lvIds[_challengeIds[i]];
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