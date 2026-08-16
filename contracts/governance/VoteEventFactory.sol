// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VoteEvent} from "./VoteEvent.sol";
import {VotingRewardVault} from "./VotingRewardVault.sol";

interface IVotingEscrowToken {
    function hap() external view returns (address);
}

/// @title VoteEventFactory
/// @notice Deploys immutable events and atomically enforces pre-funded rewards.
contract VoteEventFactory is Ownable, AccessControl {
    uint256 public constant MAX_PAGE_SIZE = 100;
    bytes32 public constant EVENT_CREATOR_ROLE = keccak256("EVENT_CREATOR_ROLE");
    address public immutable votingEscrow;
    address public immutable heroArenaProfile;
    address public immutable hap;
    VotingRewardVault public immutable rewardVault;
    uint48 public minimumLeadTime = 1 hours;
    uint256 public minimumReward = 1 ether;
    address[] private _events;
    mapping(address => bool) public isVoteEvent;

    error InvalidLeadTime();
    error RewardBelowMinimum();
    error InvalidPageSize();
    error InvalidProfile();
    error NotEventCreator();
    error UnknownVoteEvent();

    event VoteEventCreated(
        address indexed voteEvent,
        address indexed creator,
        uint256 rewardAmount,
        uint48 startTime,
        uint48 endTime
    );
    event MinimumLeadTimeSet(uint48 oldLeadTime, uint48 newLeadTime);
    event MinimumRewardSet(uint256 oldMinimum, uint256 newMinimum);
    event VoteEventCancelled(address indexed voteEvent, address indexed creator, uint256 refundedReward);

    constructor(address escrow, address profile, address initialOwner) Ownable(initialOwner) {
        if (escrow == address(0) || profile == address(0)) revert OwnableInvalidOwner(address(0));
        if (profile.code.length == 0) revert InvalidProfile();
        votingEscrow = escrow;
        heroArenaProfile = profile;
        hap = IVotingEscrowToken(escrow).hap();
        rewardVault = new VotingRewardVault(address(this), hap);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(EVENT_CREATOR_ROLE, initialOwner);
    }

    /// @dev Keep ownership and role-admin authority aligned so a previous
    ///      owner cannot continue granting EVENT_CREATOR_ROLE after transfer.
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

    /// @dev Creator must approve rewardVault before calling. Deployment and funding
    ///      happen in one transaction, so an unfunded event can never be registered.
    function createVoteEvent(
        uint48 startTime,
        uint48 endTime,
        uint256 quorumVotePower,
        bytes32[] calldata options,
        string calldata metadataURI,
        uint256 rewardAmount
    ) external onlyRole(EVENT_CREATOR_ROLE) returns (address voteEvent) {
        if (startTime < block.timestamp + minimumLeadTime) revert InvalidLeadTime();
        if (rewardAmount < minimumReward) revert RewardBelowMinimum();
        VoteEvent event_ = new VoteEvent(
            votingEscrow,
            heroArenaProfile,
            address(this),
            msg.sender,
            startTime,
            endTime,
            quorumVotePower,
            options,
            metadataURI
        );
        voteEvent = address(event_);
        isVoteEvent[voteEvent] = true;
        _events.push(voteEvent);
        rewardVault.registerAndFund(voteEvent, msg.sender, rewardAmount);
        emit VoteEventCreated(voteEvent, msg.sender, rewardAmount, startTime, endTime);
    }

    function cancelVoteEvent(address voteEvent) external returns (uint256 refundedReward) {
        if (!isVoteEvent[voteEvent]) revert UnknownVoteEvent();
        if (VoteEvent(voteEvent).creator() != msg.sender) revert NotEventCreator();
        VoteEvent(voteEvent).cancelFromFactory();
        refundedReward = rewardVault.refundCancelled(voteEvent);
        emit VoteEventCancelled(voteEvent, msg.sender, refundedReward);
    }

    function setMinimumLeadTime(uint48 newLeadTime) external onlyOwner {
        if (newLeadTime == 0) revert InvalidLeadTime();
        uint48 old = minimumLeadTime;
        minimumLeadTime = newLeadTime;
        emit MinimumLeadTimeSet(old, newLeadTime);
    }

    function setMinimumReward(uint256 newMinimum) external onlyOwner {
        if (newMinimum == 0) revert RewardBelowMinimum();
        uint256 old = minimumReward;
        minimumReward = newMinimum;
        emit MinimumRewardSet(old, newMinimum);
    }

    function eventCount() external view returns (uint256) { return _events.length; }
    function eventAt(uint256 index) external view returns (address) { return _events[index]; }
    function getEvents(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        if (limit == 0 || limit > MAX_PAGE_SIZE) revert InvalidPageSize();
        if (offset >= _events.length) return new address[](0);
        uint256 end = offset + limit;
        if (end > _events.length) end = _events.length;
        page = new address[](end - offset);
        for (uint256 i; i < page.length; ++i) page[i] = _events[offset + i];
    }
}
