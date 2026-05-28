// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title HapTreasury
 * @notice Manages the long-term treasury of the Hero Arena project
 * @dev Supports receiving and disbursing multiple token types (HAP, BNB, USDT, other ERC-20s)
 *
 * ⚠️ AUDIT NOTES:
 * - This contract is not itself a multisig; it is a fund manager controlled by a multisig
 * - DEFAULT_ADMIN_ROLE should be a Gnosis Safe 3-of-5 multisig
 * - PROPOSAL_ROLE can create proposals (individual EOA addresses of multisig members)
 * - EXECUTOR_ROLE can execute approved proposals (can be anyone, gas payer)
 * - GUARDIAN_ROLE can emergency pause (independent from admin, prevents internal collusion)
 */
contract HapTreasury is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========================================================================
    // Roles
    // ========================================================================

    /// @notice Role that can create disbursement proposals (multisig members)
    bytes32 public constant PROPOSAL_ROLE = keccak256("PROPOSAL_ROLE");

    /// @notice Role that can execute approved proposals (anyone, gas-efficient)
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice Role that can emergency pause Treasury operations
    /// @dev Separated from DEFAULT_ADMIN to prevent internal collusion
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // ========================================================================
    // Constants
    // ========================================================================

    /// @notice Proposal timelock duration (seconds)
    /// @dev Proposals must wait 7 days after approval before execution
    /// @dev In emergencies admin can shorten this, but requires a new proposal
    uint64 public constant TIMELOCK_DURATION = 7 days;

    /// @notice Maximum validity period (proposals must be executed within 30 days of approval)
    uint64 public constant PROPOSAL_EXPIRY = 30 days;

    // ========================================================================
    // Structs
    // ========================================================================

    /**
     * @notice Disbursement proposal
     */
    struct Proposal {
        // Disbursement token address (address(0) = native BNB)
        address token;

        // Recipient address
        address recipient;

        // Disbursement amount
        uint256 amount;

        // Purpose description (recorded on-chain for auditing)
        string purpose;

        // Proposal creation timestamp
        uint64 createdAt;

        // Proposal approval timestamp (non-zero means approved)
        uint64 approvedAt;

        // Whether the proposal has been executed
        bool executed;

        // Whether the proposal has been cancelled
        bool cancelled;

        // Proposal creator
        address proposer;
    }

    // ========================================================================
    // State Variables
    // ========================================================================

    /// @notice Proposal ID => proposal data
    mapping(uint256 => Proposal) public proposals;

    /// @notice Next proposal ID
    uint256 public nextProposalId;

    /// @notice Cumulative received amount (by token address)
    /// @dev Only tracks amounts received via receiveFunds; direct transfers are not counted
    mapping(address => uint256) public totalReceived;

    /// @notice Cumulative spent amount (by token address)
    mapping(address => uint256) public totalSpent;

    // ========================================================================
    // Events
    // ========================================================================

    event FundsReceived(address indexed token, address indexed from, uint256 amount, string source);
    event ProposalCreated(uint256 indexed proposalId, address indexed token, address indexed recipient, uint256 amount, string purpose, address proposer);
    event ProposalApproved(uint256 indexed proposalId, address indexed approver);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);
    event EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount);

    // ========================================================================
    // Custom Errors
    // ========================================================================

    error InvalidRecipient();
    error InvalidAmount();
    error EmptyPurpose();
    error ProposalDoesNotExist();
    error ProposalAlreadyApproved();
    error ProposalNotApproved();
    error ProposalAlreadyExecuted();
    error ProposalAlreadyCancelled();
    error TimelockNotPassed();
    error ProposalExpired();
    error InsufficientBalance();
    error TransferFailed();
    error NotAuthorizedToCancel();

    // ========================================================================
    // Constructor
    // ========================================================================

    /**
     * @param admin Primary admin (should be a Gnosis Safe multisig)
     * @param guardian Guardian emergency pause authority (should be a different multisig or EOA from admin)
     *
     * @dev ⚠️ admin and guardian must be different addresses (prevents single point of failure).
     *      For testnet: use two default Hardhat accounts (deployer, signers[1]).
     *      For mainnet: admin = Gnosis Safe 3-of-5, guardian = a separate independent Gnosis Safe 2-of-3.
     */
    constructor(address admin, address guardian) {
        require(admin != address(0), "Invalid admin");
        require(guardian != address(0), "Invalid guardian");
        require(admin != guardian, "Admin and guardian must differ");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PROPOSAL_ROLE, admin);
        _grantRole(EXECUTOR_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, guardian);
    }

    // ========================================================================
    // Receive Funds
    // ========================================================================

    /**
     * @notice Receives ERC-20 tokens (with source label)
     * @param token Token contract address
     * @param amount Amount
     * @param source Source description ("WAGER_RAKE", "MARKETPLACE_FEE", "VESTING", "DONATION", etc.)
     *
     * @dev Caller must approve this contract to spend amount before calling.
     */
    function receiveFunds(address token, uint256 amount, string calldata source) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();

        // Fee-on-transfer / rebasing tokens (USDT-with-fee, PAXG, stETH, etc.) can
        // deliver less than `amount`. Credit only what actually arrived so
        // totalReceived[token] tracks real inflow, not the requested amount.
        uint256 balBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;
        if (received == 0) revert InvalidAmount();

        totalReceived[token] += received;

        emit FundsReceived(token, msg.sender, received, source);
    }

    /**
     * @notice Receives native BNB
     * @dev The fallback receive function accepts BNB automatically but does not emit an event.
     *      Use depositBNB to explicitly record the source.
     */
    function depositBNB(string calldata source) external payable whenNotPaused {
        if (msg.value == 0) revert InvalidAmount();
        totalReceived[address(0)] += msg.value;
        emit FundsReceived(address(0), msg.sender, msg.value, source);
    }

    /// @notice Fallback receive (allows EOA to transfer BNB directly).
    /// @dev    Guarded with whenNotPaused so direct native transfers cannot
    ///         bypass the emergency pause and mutate totalReceived.
    receive() external payable whenNotPaused {
        if (msg.value > 0) {
            totalReceived[address(0)] += msg.value;
            emit FundsReceived(address(0), msg.sender, msg.value, "DIRECT_TRANSFER");
        }
    }

    // ========================================================================
    // Create Proposal
    // ========================================================================

    /**
     * @notice Creates a new disbursement proposal
     * @param token Disbursement token (address(0) = BNB)
     * @param recipient Recipient address
     * @param amount Disbursement amount
     * @param purpose Purpose description (recorded on-chain, required)
     * @return proposalId Proposal ID
     *
     * @dev Creating a proposal does not execute it immediately; it follows approve → wait timelock → execute flow.
     */
    function createProposal(
        address token,
        address recipient,
        uint256 amount,
        string calldata purpose
    ) external onlyRole(PROPOSAL_ROLE) whenNotPaused returns (uint256 proposalId) {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (bytes(purpose).length == 0) revert EmptyPurpose();

        proposalId = nextProposalId++;
        proposals[proposalId] = Proposal({
            token: token,
            recipient: recipient,
            amount: amount,
            purpose: purpose,
            createdAt: uint64(block.timestamp),
            approvedAt: 0,
            executed: false,
            cancelled: false,
            proposer: msg.sender
        });

        emit ProposalCreated(proposalId, token, recipient, amount, purpose, msg.sender);
    }

    // ========================================================================
    // Approve Proposal
    // ========================================================================

    /**
     * @notice Approves a proposal (admin multisig only)
     * @param proposalId Proposal ID
     *
     * @dev After approval, a 7-day timelock must pass before execution.
     *      The multisig-level "approval" occurs when this function is called (after 3-of-5 multisig signs off).
     *      whenNotPaused prevents approvals during an active emergency pause.
     */
    function approveProposal(uint256 proposalId) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.createdAt == 0) revert ProposalDoesNotExist();
        if (proposal.approvedAt != 0) revert ProposalAlreadyApproved();
        if (proposal.cancelled) revert ProposalAlreadyCancelled();
        if (proposal.executed) revert ProposalAlreadyExecuted();

        proposal.approvedAt = uint64(block.timestamp);

        emit ProposalApproved(proposalId, msg.sender);
    }

    // ========================================================================
    // Execute Proposal
    // ========================================================================

    /**
     * @notice Executes a proposal that has passed the timelock
     * @param proposalId Proposal ID
     *
     * @dev Any address holding EXECUTOR_ROLE can execute (gas payer).
     *      Requirements: approved + timelock passed + not expired + not executed + not cancelled.
     */
    function executeProposal(uint256 proposalId) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.createdAt == 0) revert ProposalDoesNotExist();
        if (proposal.approvedAt == 0) revert ProposalNotApproved();
        if (proposal.cancelled) revert ProposalAlreadyCancelled();
        if (proposal.executed) revert ProposalAlreadyExecuted();

        // Timelock must have passed
        if (block.timestamp < proposal.approvedAt + TIMELOCK_DURATION) revert TimelockNotPassed();

        // Proposal must not be expired (no execution within 30 days of approval is considered expired)
        if (block.timestamp > proposal.approvedAt + PROPOSAL_EXPIRY) revert ProposalExpired();

        proposal.executed = true;
        totalSpent[proposal.token] += proposal.amount;

        // Execute the actual transfer
        if (proposal.token == address(0)) {
            // BNB transfer
            if (address(this).balance < proposal.amount) revert InsufficientBalance();
            (bool success, ) = proposal.recipient.call{value: proposal.amount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC-20 transfer
            if (IERC20(proposal.token).balanceOf(address(this)) < proposal.amount) revert InsufficientBalance();
            IERC20(proposal.token).safeTransfer(proposal.recipient, proposal.amount);
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    // ========================================================================
    // Cancel Proposal
    // ========================================================================

    /**
     * @notice Cancels a proposal that has not yet been executed
     * @param proposalId Proposal ID
     *
     * @dev The proposer or admin can cancel. Intentionally not gated by whenNotPaused
     *      so that proposals can still be cancelled during an emergency pause.
     */
    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        if (proposal.createdAt == 0) revert ProposalDoesNotExist();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.cancelled) revert ProposalAlreadyCancelled();

        // Only the proposer or admin can cancel
        if (proposal.proposer != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedToCancel();
        }

        proposal.cancelled = true;

        emit ProposalCancelled(proposalId, msg.sender);
    }

    // ========================================================================
    // Emergency Controls
    // ========================================================================

    /**
     * @notice Guardian emergency pause of all Treasury operations
     * @dev Use only when a critical vulnerability is discovered.
     *      Guardian is separated from admin so the contract can still be paused
     *      even if the admin multisig is compromised.
     */
    function emergencyPause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Called by admin (after multisig approval).
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal bypassing the timelock
     * @param token Token (address(0) = BNB)
     * @param to Recipient address
     * @param amount Amount
     *
     * @dev ⚠️ This is the nuclear option, use only in the following situations:
     *      1. The Treasury contract is under attack and funds must be immediately moved to a safe address
     *      2. A court order requires freezing funds
     *      Requirements: contract must first be paused, and admin (multisig) must call.
     *      Cyberscope may flag as Critical: consider adding a timelock, even for emergencies, of at least 24h.
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused nonReentrant {
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();

        totalSpent[token] += amount;

        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit EmergencyWithdrawal(token, to, amount);
    }

    // ========================================================================
    // View Functions
    // ========================================================================

    /**
     * @notice Returns the current balance for a given token
     * @param token Token address (address(0) = BNB)
     */
    function balanceOf(address token) external view returns (uint256) {
        if (token == address(0)) return address(this).balance;
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Returns cumulative net inflow statistics for a given token
     * @return received Total received
     * @return spent Total spent
     * @return current Current balance
     */
    function tokenStats(address token) external view returns (uint256 received, uint256 spent, uint256 current) {
        received = totalReceived[token];
        spent = totalSpent[token];
        current = (token == address(0)) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Returns the current status of a proposal
     */
    function proposalStatus(uint256 proposalId) external view returns (string memory) {
        Proposal memory p = proposals[proposalId];
        if (p.createdAt == 0) return "NOT_EXIST";
        if (p.cancelled) return "CANCELLED";
        if (p.executed) return "EXECUTED";
        if (p.approvedAt == 0) return "PENDING_APPROVAL";
        if (block.timestamp < p.approvedAt + TIMELOCK_DURATION) return "TIMELOCK";
        if (block.timestamp > p.approvedAt + PROPOSAL_EXPIRY) return "EXPIRED";
        return "READY_TO_EXECUTE";
    }

    /**
     * @notice Returns the remaining timelock seconds for a proposal
     */
    function timeUntilExecutable(uint256 proposalId) external view returns (uint256) {
        Proposal memory p = proposals[proposalId];
        if (p.approvedAt == 0) return type(uint256).max;
        uint256 executableAt = p.approvedAt + TIMELOCK_DURATION;
        if (block.timestamp >= executableAt) return 0;
        return executableAt - block.timestamp;
    }
}
