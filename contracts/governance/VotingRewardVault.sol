// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IVoteEventRewardView {
    function startTime() external view returns (uint48);
    function endTime() external view returns (uint48);
    function totalVoters() external view returns (uint256);
    function totalVotePower() external view returns (uint256);
    function votePowerOf(uint256 tokenId) external view returns (uint256);
    function rewardRecipientOf(uint256 tokenId) external view returns (address);
    function finalized() external view returns (bool);
    function finalizedAt() external view returns (uint48);
    function cancelled() external view returns (bool);
}

/// @title VotingRewardVault
/// @notice HAP-only pre-funded rewards: 40% per unique voter, 60% by snapshot power.
contract VotingRewardVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant EQUAL_SHARE_BPS = 4_000;
    uint256 public constant BPS = 10_000;
    uint256 public constant CLAIM_WINDOW = 90 days;
    address public immutable factory;
    IERC20 public immutable hap;

    struct RewardConfig {
        address sponsor;
        uint256 totalReward;
        uint256 claimedReward;
        bool registered;
        bool settled;
    }

    mapping(address => RewardConfig) public rewards;
    mapping(address => mapping(uint256 => bool)) public claimed;
    mapping(address => mapping(address => bool)) public equalShareClaimed;

    error OnlyFactory();
    error EventAlreadyRegistered();
    error EventNotRegistered();
    error RewardFundingClosed();
    error InvalidFunding();
    error EventNotEnded();
    error NotValidVoter();
    error AlreadyClaimed();
    error HasVotes();
    error NotSponsor();
    error ClaimPeriodEnded();
    error ClaimPeriodActive();
    error AlreadySettled();
    error EventNotFinalized();
    error EventNotCancelled();

    event EventFunded(address indexed voteEvent, address indexed token, address indexed sponsor, uint256 amount);
    event RewardAdded(address indexed voteEvent, address indexed funder, uint256 amount);
    event RewardClaimed(address indexed voteEvent, uint256 indexed tokenId, address indexed recipient, uint256 amount);
    event NoVoteRewardRefunded(address indexed voteEvent, address indexed sponsor, uint256 amount);
    event RemainingRewardSwept(address indexed voteEvent, address indexed sponsor, uint256 amount);
    event CancelledRewardRefunded(address indexed voteEvent, address indexed sponsor, uint256 amount);

    constructor(address factory_, address hap_) {
        if (factory_ == address(0) || hap_ == address(0)) revert InvalidFunding();
        factory = factory_;
        hap = IERC20(hap_);
    }

    function registerAndFund(address voteEvent, address sponsor, uint256 amount) external nonReentrant {
        if (msg.sender != factory) revert OnlyFactory();
        if (rewards[voteEvent].registered) revert EventAlreadyRegistered();
        if (sponsor == address(0) || amount == 0) revert InvalidFunding();
        if (block.timestamp >= IVoteEventRewardView(voteEvent).startTime()) revert RewardFundingClosed();
        _pullExact(sponsor, amount);
        rewards[voteEvent] = RewardConfig(sponsor, amount, 0, true, false);
        emit EventFunded(voteEvent, address(hap), sponsor, amount);
    }

    function addReward(address voteEvent, uint256 amount) external nonReentrant {
        RewardConfig storage config = rewards[voteEvent];
        if (!config.registered) revert EventNotRegistered();
        if (msg.sender != config.sponsor) revert NotSponsor();
        if (block.timestamp >= IVoteEventRewardView(voteEvent).startTime()) revert RewardFundingClosed();
        if (amount == 0) revert InvalidFunding();
        _pullExact(msg.sender, amount);
        config.totalReward += amount;
        emit RewardAdded(voteEvent, msg.sender, amount);
    }

    function claim(address voteEvent, uint256 tokenId) external nonReentrant returns (uint256 amount) {
        RewardConfig storage config = rewards[voteEvent];
        if (!config.registered) revert EventNotRegistered();
        if (config.settled) revert AlreadySettled();
        IVoteEventRewardView event_ = IVoteEventRewardView(voteEvent);
        if (block.timestamp < event_.endTime()) revert EventNotEnded();
        if (!event_.finalized()) revert EventNotFinalized();
        if (block.timestamp >= uint256(event_.finalizedAt()) + CLAIM_WINDOW) revert ClaimPeriodEnded();
        if (claimed[voteEvent][tokenId]) revert AlreadyClaimed();
        uint256 power = event_.votePowerOf(tokenId);
        address recipient = event_.rewardRecipientOf(tokenId);
        if (power == 0 || recipient == address(0)) revert NotValidVoter();

        claimed[voteEvent][tokenId] = true;
        uint256 equalPool = Math.mulDiv(config.totalReward, EQUAL_SHARE_BPS, BPS);
        amount = Math.mulDiv(config.totalReward - equalPool, power, event_.totalVotePower());
        if (!equalShareClaimed[voteEvent][recipient]) {
            equalShareClaimed[voteEvent][recipient] = true;
            amount += equalPool / event_.totalVoters();
        }
        config.claimedReward += amount;
        hap.safeTransfer(recipient, amount);
        emit RewardClaimed(voteEvent, tokenId, recipient, amount);
    }

    /// @notice Returns the amount if this token is the owner's first token to
    ///         claim. For owners with multiple voted veHAPs, do not sum this
    ///         value before the first claim: the 40% equal share is paid once.
    function previewClaim(address voteEvent, uint256 tokenId) external view returns (uint256) {
        RewardConfig storage config = rewards[voteEvent];
        IVoteEventRewardView event_ = IVoteEventRewardView(voteEvent);
        if (!event_.finalized()) return 0;
        if (block.timestamp < event_.endTime()) return 0;
        if (block.timestamp >= uint256(event_.finalizedAt()) + CLAIM_WINDOW) return 0;
        uint256 power = event_.votePowerOf(tokenId);
        if (!config.registered || config.settled || power == 0 || event_.totalVoters() == 0) return 0;
        uint256 equalPool = Math.mulDiv(config.totalReward, EQUAL_SHARE_BPS, BPS);
        uint256 amount = Math.mulDiv(config.totalReward - equalPool, power, event_.totalVotePower());
        if (!equalShareClaimed[voteEvent][event_.rewardRecipientOf(tokenId)]) {
            amount += equalPool / event_.totalVoters();
        }
        return amount;
    }

    function refundIfNoVotes(address voteEvent) external nonReentrant {
        RewardConfig storage config = rewards[voteEvent];
        if (!config.registered) revert EventNotRegistered();
        if (config.settled) revert AlreadySettled();
        IVoteEventRewardView event_ = IVoteEventRewardView(voteEvent);
        if (block.timestamp < event_.endTime()) revert EventNotEnded();
        if (event_.totalVoters() != 0) revert HasVotes();
        if (msg.sender != config.sponsor) revert NotSponsor();
        config.settled = true;
        hap.safeTransfer(config.sponsor, config.totalReward);
        emit NoVoteRewardRefunded(voteEvent, config.sponsor, config.totalReward);
    }

    function refundCancelled(address voteEvent) external nonReentrant returns (uint256 amount) {
        if (msg.sender != factory) revert OnlyFactory();
        RewardConfig storage config = rewards[voteEvent];
        if (!config.registered) revert EventNotRegistered();
        if (config.settled) revert AlreadySettled();
        if (!IVoteEventRewardView(voteEvent).cancelled()) revert EventNotCancelled();
        config.settled = true;
        amount = config.totalReward;
        hap.safeTransfer(config.sponsor, amount);
        emit CancelledRewardRefunded(voteEvent, config.sponsor, amount);
    }

    function sweepRemaining(address voteEvent) external nonReentrant returns (uint256 remaining) {
        RewardConfig storage config = rewards[voteEvent];
        if (!config.registered) revert EventNotRegistered();
        if (config.settled) revert AlreadySettled();
        if (msg.sender != config.sponsor) revert NotSponsor();
        IVoteEventRewardView event_ = IVoteEventRewardView(voteEvent);
        if (!event_.finalized()) revert EventNotFinalized();
        uint256 deadline = uint256(event_.finalizedAt()) + CLAIM_WINDOW;
        if (block.timestamp < deadline) revert ClaimPeriodActive();
        config.settled = true;
        remaining = config.totalReward - config.claimedReward;
        hap.safeTransfer(config.sponsor, remaining);
        emit RemainingRewardSwept(voteEvent, config.sponsor, remaining);
    }

    function claimDeadline(address voteEvent) external view returns (uint256) {
        IVoteEventRewardView event_ = IVoteEventRewardView(voteEvent);
        if (!event_.finalized()) return 0;
        return uint256(event_.finalizedAt()) + CLAIM_WINDOW;
    }

    function _pullExact(address from, uint256 amount) private {
        uint256 beforeBalance = hap.balanceOf(address(this));
        hap.safeTransferFrom(from, address(this), amount);
        if (hap.balanceOf(address(this)) - beforeBalance != amount) revert InvalidFunding();
    }
}
