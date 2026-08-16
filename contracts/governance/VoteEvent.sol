// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IVotingEscrowHAP {
    function votingPowerAt(uint256 tokenId, uint256 timestamp) external view returns (uint256);
    function ownerAt(uint256 tokenId, uint256 timestamp) external view returns (address);
    function delegateAt(uint256 tokenId, uint256 timestamp) external view returns (address);
}

interface IHeroArenaProfile {
    function hasRegistered(address user) external view returns (bool);
}

/// @title VoteEvent
/// @notice One immutable, snapshot-based Hero Arena voting event.
contract VoteEvent {
    uint256 public constant MAX_OPTIONS = 32;
    uint256 public constant MAX_METADATA_URI_LENGTH = 512;

    IVotingEscrowHAP public immutable votingEscrow;
    IHeroArenaProfile public immutable heroArenaProfile;
    address public immutable factory;
    address public immutable creator;
    uint48 public immutable startTime;
    uint48 public immutable endTime;
    uint256 public immutable quorumVotePower;
    string public metadataURI;

    bytes32[] private _options;
    mapping(bytes32 => bool) public isOption;
    mapping(bytes32 => uint256) public optionVotePower;
    mapping(bytes32 => uint256) public optionVoteCount;
    mapping(uint256 => bool) public hasVoted;
    mapping(uint256 => bytes32) public choiceOf;
    mapping(uint256 => uint256) public votePowerOf;
    mapping(uint256 => address) public rewardRecipientOf;
    mapping(address => bool) public hasParticipated;
    uint256 public totalVotePower;
    uint256 public totalBallots;
    uint256 public totalVoters;
    bool public finalized;
    uint48 public finalizedAt;
    bool public cancelled;
    bool public passed;
    bool public tied;
    bytes32 public winningOption;
    uint256 public winningVotePower;

    error InvalidTimeRange();
    error InvalidOption();
    error DuplicateOption();
    error VotingNotActive();
    error AlreadyVoted();
    error NoSnapshotPower();
    error NotAuthorizedVoter();
    error TooManyOptions();
    error MetadataTooLong();
    error VotingNotEnded();
    error AlreadyFinalized();
    error NotRegisteredProfile();
    error EventCancelled();
    error OnlyFactory();

    event VoteCast(address indexed voter, uint256 indexed tokenId, bytes32 indexed option, uint256 votePower);
    event VoteFinalized(bool passed, bool tied, bytes32 indexed winningOption, uint256 winningVotePower, uint256 totalVotePower);
    event VoteCancelled(address indexed creator);

    constructor(
        address escrow,
        address profile,
        address factory_,
        address eventCreator,
        uint48 start,
        uint48 end,
        uint256 quorumVotePower_,
        bytes32[] memory options_,
        string memory metadataURI_
    ) {
        if (start <= block.timestamp || end <= start) revert InvalidTimeRange();
        if (options_.length < 2) revert InvalidOption();
        if (options_.length > MAX_OPTIONS) revert TooManyOptions();
        if (bytes(metadataURI_).length > MAX_METADATA_URI_LENGTH) revert MetadataTooLong();
        votingEscrow = IVotingEscrowHAP(escrow);
        heroArenaProfile = IHeroArenaProfile(profile);
        factory = factory_;
        creator = eventCreator;
        startTime = start;
        endTime = end;
        quorumVotePower = quorumVotePower_;
        metadataURI = metadataURI_;
        for (uint256 i; i < options_.length; ++i) {
            bytes32 option = options_[i];
            if (option == bytes32(0)) revert InvalidOption();
            if (isOption[option]) revert DuplicateOption();
            isOption[option] = true;
            _options.push(option);
        }
    }

    function vote(uint256 tokenId, bytes32 option) external {
        if (cancelled) revert EventCancelled();
        if (block.timestamp < startTime || block.timestamp >= endTime) revert VotingNotActive();
        if (!isOption[option]) revert InvalidOption();
        if (hasVoted[tokenId]) revert AlreadyVoted();

        uint256 power = votingEscrow.votingPowerAt(tokenId, startTime);
        if (power == 0) revert NoSnapshotPower();
        address owner = votingEscrow.ownerAt(tokenId, startTime);
        if (!heroArenaProfile.hasRegistered(owner)) revert NotRegisteredProfile();
        address delegatee = votingEscrow.delegateAt(tokenId, startTime);
        address authorized = delegatee == address(0) ? owner : delegatee;
        if (msg.sender != authorized) revert NotAuthorizedVoter();

        hasVoted[tokenId] = true;
        choiceOf[tokenId] = option;
        votePowerOf[tokenId] = power;
        rewardRecipientOf[tokenId] = owner;
        totalVotePower += power;
        totalBallots += 1;
        if (!hasParticipated[owner]) {
            hasParticipated[owner] = true;
            totalVoters += 1;
        }
        optionVotePower[option] += power;
        optionVoteCount[option] += 1;
        emit VoteCast(msg.sender, tokenId, option, power);
    }

    function options() external view returns (bytes32[] memory) { return _options; }
    function optionCount() external view returns (uint256) { return _options.length; }

    /// @notice Produces one canonical result. A tie or failure to meet quorum
    ///         has no winning option and sets passed=false.
    function finalize() external {
        if (cancelled) revert EventCancelled();
        if (block.timestamp < endTime) revert VotingNotEnded();
        if (finalized) revert AlreadyFinalized();
        finalized = true;
        finalizedAt = uint48(block.timestamp);

        bytes32 leader;
        uint256 leaderPower;
        bool isTie;
        for (uint256 i; i < _options.length; ++i) {
            bytes32 current = _options[i];
            uint256 currentPower = optionVotePower[current];
            if (currentPower > leaderPower) {
                leader = current;
                leaderPower = currentPower;
                isTie = false;
            } else if (currentPower == leaderPower && currentPower != 0) {
                isTie = true;
            }
        }

        tied = isTie;
        winningVotePower = leaderPower;
        if (totalVotePower >= quorumVotePower && leaderPower != 0 && !isTie) {
            passed = true;
            winningOption = leader;
        }
        emit VoteFinalized(passed, tied, winningOption, winningVotePower, totalVotePower);
    }

    /// @dev Called atomically by VoteEventFactory.cancelVoteEvent after it has
    ///      authenticated the event creator.
    function cancelFromFactory() external {
        if (msg.sender != factory) revert OnlyFactory();
        if (block.timestamp >= startTime) revert VotingNotActive();
        if (cancelled) revert EventCancelled();
        cancelled = true;
        emit VoteCancelled(creator);
    }
}
