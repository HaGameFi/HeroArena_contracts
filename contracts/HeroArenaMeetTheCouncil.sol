// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./HeroArenaChallenges.sol";
import "./HeroArenaProfile.sol";

/**
 * @title HeroArenaMeetTheCouncil
 * @notice Operator-driven submission flow that records PvE level completions
 *         in HeroArenaChallenges and credits the reward points to the user's
 *         profile in HeroArenaProfile.
 *
 * @dev Cross-contract role wiring required before this contract is operational:
 *      1. HeroArenaChallenges must grant CHALLENGE_ADMIN_ROLE to this council
 *         contract (so submit() / setLevelNameAndRewardPoints() succeed).
 *      2. HeroArenaProfile must grant POINT_ROLE to this council contract
 *         (so increaseUserPoints() succeeds).
 *      3. This contract must grant OPERATOR_ROLE to the backend operator
 *         address that will call submitLv().
 *      Step 1 must complete before initLevels() is called. The deployment
 *      script is responsible for performing these atomically and verifying
 *      them before the contract is considered ready.
 */
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
        require(address(_HeroArenaChallengesSC) != address(0), "Challenges cannot be zero");
        require(address(_HeroArenaProfileSC)    != address(0), "Profile cannot be zero");
        HeroArenaChallengesSC = _HeroArenaChallengesSC;
        HeroArenaProfileSC = _HeroArenaProfileSC;

        // _grantRole here is now redundant with the _transferOwnership override
        // that fires from Ownable's constructor, but kept for explicitness — it
        // is idempotent.
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Keep Ownable and AccessControl authorities aligned. When the owner
     *      changes (including renounceOwnership which transfers to address(0)),
     *      grant DEFAULT_ADMIN_ROLE to the new owner and revoke it from the
     *      previous owner. Without this, transferOwnership would leave the
     *      original deployer able to administer OPERATOR_ROLE even after they
     *      are no longer Ownable.owner().
     *
     *      Fires from Ownable's constructor too (previousOwner = address(0)),
     *      so the initial DEFAULT_ADMIN_ROLE grant is handled here.
     */
    function _transferOwnership(address newOwner) internal override {
        address previousOwner = owner();
        super._transferOwnership(newOwner);
        if (previousOwner != address(0) && previousOwner != newOwner) {
            _revokeRole(DEFAULT_ADMIN_ROLE, previousOwner);
        }
        if (newOwner != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        }
    }

    /**
     * @notice Initialize level names and reward points. Must be called once,
     *         after this contract has been granted CHALLENGE_ADMIN_ROLE on
     *         HeroArenaChallenges. (HeroArenaChallenges itself is governed by
     *         CHALLENGE_ADMIN_ROLE, not Ownable, so no ownership transfer is
     *         needed — only the role grant.)
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
