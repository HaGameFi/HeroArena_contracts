// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./HeroArenaChallenges.sol";
import "./HeroArenaProfile.sol";

contract HeroArenaMeetTheCouncil is AccessControl, Ownable {

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    HeroArenaChallenges public HeroArenaChallengesSC;
    HeroArenaProfile public HeroArenaProfileSC;

    bool public availableSubmit;

    uint8 public submitMinLevelId;
    uint8 public submitMaxLevelId;

    event LevelSubmited(address indexed user, uint256 indexed challengeId, uint8 indexed lvId, uint256 lvRewardPts);
    event AvailableSubmitUpdated(address indexed owner, bool isAvail);

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not an operator role");
        _;
    }

    constructor(HeroArenaChallenges _HeroArenaChallengesSC, HeroArenaProfile _HeroArenaProfileSC) Ownable(msg.sender) {
        HeroArenaChallengesSC = _HeroArenaChallengesSC;
        HeroArenaProfileSC = _HeroArenaProfileSC;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * Initialize level names and points. Must be called after HeroArenaChallenges
     * ownership has been transferred to this contract.
     */
    function initLevels() external onlyOwner {
        require(submitMaxLevelId == 0, "Already initialized");

        HeroArenaChallengesSC.setLevelNameAndRewardPoints(0, "Ladder Climb", 5);
        HeroArenaChallengesSC.setLevelNameAndRewardPoints(1, "Knight Fight", 5);
        HeroArenaChallengesSC.setLevelNameAndRewardPoints(2, "Warrior Bath", 10);
        HeroArenaChallengesSC.setLevelNameAndRewardPoints(3, "Firestorm", 10);
        HeroArenaChallengesSC.setLevelNameAndRewardPoints(4, "Switcheroo", 15);
        HeroArenaChallengesSC.setLevelNameAndRewardPoints(5, "Wizard Dance", 15);
        HeroArenaChallengesSC.setLevelNameAndRewardPoints(6, "Cluster Bomb", 20);

        submitMinLevelId = 0;
        submitMaxLevelId = 6;
    }

    /**
     * Update the availableSubmit to allow user submit.
     */
    function updateAvailableSubmit(bool _isAvailable) external onlyOwner {
        availableSubmit = _isAvailable;

        // emit event
        emit AvailableSubmitUpdated(msg.sender, _isAvailable);
    }

    /**
     * Submit levels from the HeroArenaChallenges contract.
     */
    function submitLv(address _userAddress, uint8 _lvId) external onlyOperator {
        require(availableSubmit, "Cannot submit");
        require(_lvId >= submitMinLevelId && _lvId <= submitMaxLevelId, "Input levelId unavailable");

        // generate the new challenge id
        uint256 _challengeId = HeroArenaChallengesSC.submit(_userAddress, _lvId);

        // get the reward points of this level
        uint256 _lvRewardPoints = HeroArenaChallengesSC.getLevelRewardPoints(_lvId);

        // increase user's points
        HeroArenaProfileSC.increaseUserPoints(_userAddress, _lvRewardPoints, _lvId);

        // emit event
        emit LevelSubmited(_userAddress, _challengeId, _lvId, _lvRewardPoints);
    }
}