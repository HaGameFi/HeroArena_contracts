// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title HapVesting
 * @notice Manages vesting and token release for Hero Arena $HAP
 * @dev Each beneficiary has an independent VestingSchedule supporting TGE unlock + Cliff + linear vesting.
 *
 * ⚠️ AUDIT NOTES:
 * - Timestamps use block.timestamp (accepts up to ~15s miner manipulation risk, negligible for month-level vesting)
 * - All amounts use uint256; max 1B * 10^18 = 1e27, well within uint256 range
 * - revoked field is reserved for revocation (only team/advisor vesting; community allocations are non-revocable)
 * - Beneficiary address is immutable (prevents transfers in case of hot wallet compromise)
 */
contract HapVesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========================================================================
    // Roles
    // ========================================================================

    /// @notice Role that can create vesting schedules (should be a multisig after deployment)
    bytes32 public constant VESTING_ADMIN_ROLE = keccak256("VESTING_ADMIN_ROLE");

    // ========================================================================
    // Constants
    // ========================================================================

    /// @notice Maximum allowed cliff or vesting duration (10 years) to guard against admin input errors
    uint64 public constant MAX_VESTING_DURATION = 10 * 365 days;

    /// @notice Maximum number of schedules per beneficiary address to prevent gas exhaustion in releaseAllMine
    uint256 public constant MAX_SCHEDULES_PER_BENEFICIARY = 50;

    // ========================================================================
    // Structs
    // ========================================================================

    /**
     * @notice A single vesting schedule
     * @dev All timestamps are Unix epoch seconds
     */
    struct VestingSchedule {
        // Beneficiary address (same address can have multiple schedules, differentiated by scheduleId)
        address beneficiary;

        // Purpose label ("PUBLIC_IDO", "TEAM", "P2E_REWARDS", "STAKING_REWARDS", etc.)
        // Used for on-chain earmark transparency and frontend display
        bytes32 label;

        // Total allocated amount (including TGE immediate unlock portion)
        uint256 totalAmount;

        // TGE immediate unlock amount (use absolute value rather than percentage; compute at deploy time)
        uint256 tgeUnlockAmount;

        // Cliff lock period (seconds), counted from TGE time
        uint64 cliffDuration;

        // Total linear vesting duration (seconds), starting after cliff ends
        uint64 vestingDuration;

        // Cumulative amount already claimed by this beneficiary
        uint256 released;

        // Whether this schedule can be revoked by admin (true only for team/advisor types)
        bool revocable;

        // Whether this schedule has been revoked
        bool revoked;

        // Timestamp of revocation (0 if not revoked)
        uint64 revokedAt;
    }

    // ========================================================================
    // State Variables
    // ========================================================================

    /// @notice $HAP token contract address
    IERC20 public immutable hapToken;

    /// @notice TGE timestamp (all vesting times are counted from this point)
    /// @dev Set at deployment, immutable
    uint64 public immutable tgeTimestamp;

    /// @notice scheduleId => VestingSchedule
    /// @dev Uses scheduleId instead of address to support multiple schedules per address
    ///      (e.g. Treasury can receive P2E, Staking, Treasury, and Ecosystem allocations simultaneously)
    mapping(uint256 => VestingSchedule) public schedules;

    /// @notice Beneficiary address => all scheduleIds ever held by that address.
    /// @dev    Append-only history, used by getSchedulesOf() / frontend visibility.
    ///         The per-beneficiary cap and the batch-release iteration both operate
    ///         on `activeScheduleIds` instead so completed or revoked schedules do
    ///         not permanently consume slots or waste gas.
    mapping(address => uint256[]) public beneficiarySchedules;

    /// @notice Beneficiary address => scheduleIds that are still active.
    /// @dev    "Active" = not fully released AND not revoked. This is the list
    ///         releaseAllMine() iterates, and its length is what
    ///         MAX_SCHEDULES_PER_BENEFICIARY caps.
    mapping(address => uint256[]) public activeScheduleIds;

    /// @dev 1-indexed position of `scheduleId` inside activeScheduleIds[beneficiary].
    ///      0 means the schedule is not (no longer) active. Enables O(1) removal
    ///      via swap-and-pop.
    mapping(uint256 => uint256) private _activeIdxPlusOne;

    /// @notice Next schedule ID
    uint256 public nextScheduleId;

    /// @notice Deduplicated list of all beneficiary addresses (for frontend enumeration)
    address[] public allBeneficiaries;
    mapping(address => bool) private _isBeneficiary;

    /// @notice Total allocated but not yet released token amount (for auditing)
    uint256 public totalAllocated;

    /// @notice Total token amount released to beneficiaries
    uint256 public totalReleased;

    // ========================================================================
    // Events
    // ========================================================================

    event VestingScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        bytes32 indexed label,
        uint256 totalAmount,
        uint256 tgeUnlockAmount,
        uint64 cliffDuration,
        uint64 vestingDuration,
        bool revocable
    );

    event TokensReleased(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);

    event VestingRevoked(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 vestedAndAutoReleased,
        uint256 forfeited,
        address indexed revokedBy
    );

    // ========================================================================
    // Custom Errors
    // ========================================================================

    error TGENotReached();
    error NoVestingSchedule();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidDuration();
    error CliffNotReached();
    error NothingToRelease();
    error NotRevocable();
    error AlreadyRevoked();
    error InsufficientContractBalance();
    error TooManySchedules();

    // ========================================================================
    // Constructor
    // ========================================================================

    /**
     * @param hapTokenAddress HapToken contract address
     * @param _tgeTimestamp TGE timestamp (Unix epoch seconds)
     * @param admin Initial admin (should be a multisig)
     *
     * @dev ⚠️ TGE timestamp cannot be changed once set — ensure it is correct.
     */
    constructor(
        address hapTokenAddress,
        uint64 _tgeTimestamp,
        address admin
    ) {
        if (hapTokenAddress == address(0)) revert InvalidBeneficiary();
        if (admin == address(0)) revert InvalidBeneficiary();

        // TGE time should be in the future (minimum 1 hour buffer)
        require(_tgeTimestamp > block.timestamp + 1 hours, "TGE must be in future");

        hapToken = IERC20(hapTokenAddress);
        tgeTimestamp = _tgeTimestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VESTING_ADMIN_ROLE, admin);
    }

    // ========================================================================
    // Create Schedule
    // ========================================================================

    /**
     * @notice Creates a new vesting schedule
     * @param beneficiary Beneficiary address (can be a contract or EOA)
     * @param label Label (e.g. "TEAM", "P2E_REWARDS"), for on-chain identification and frontend display
     * @param totalAmount Total allocated amount (including TGE portion)
     * @param tgeUnlockAmount TGE immediate unlock amount
     * @param cliffDuration Cliff duration (seconds), counted from TGE; max MAX_VESTING_DURATION
     * @param vestingDuration Linear vesting duration (seconds), counted after cliff ends; max MAX_VESTING_DURATION
     * @param revocable Whether revocable (true for team/advisors, false for community allocations)
     * @return scheduleId Newly created schedule ID
     *
     * @dev The same beneficiary can have multiple schedules (differentiated by scheduleId),
     *      up to MAX_SCHEDULES_PER_BENEFICIARY to prevent gas exhaustion in releaseAllMine().
     *
     * @dev ⚠️ Ensure the contract holds sufficient HAP balance before calling.
     */
    function createVestingSchedule(
        address beneficiary,
        bytes32 label,
        uint256 totalAmount,
        uint256 tgeUnlockAmount,
        uint64 cliffDuration,
        uint64 vestingDuration,
        bool revocable
    ) external onlyRole(VESTING_ADMIN_ROLE) returns (uint256 scheduleId) {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (totalAmount == 0) revert InvalidAmount();
        if (tgeUnlockAmount > totalAmount) revert InvalidAmount();
        if (cliffDuration > MAX_VESTING_DURATION) revert InvalidDuration();
        if (vestingDuration > MAX_VESTING_DURATION) revert InvalidDuration();

        // If vestingDuration == 0, tgeUnlockAmount must equal totalAmount (e.g. Liquidity 100% TGE)
        if (vestingDuration == 0 && tgeUnlockAmount != totalAmount) revert InvalidDuration();

        // Cap is on the ACTIVE list (also what releaseAllMine iterates), so the
        // gas bound is preserved while fully released/revoked schedules free
        // their slot for future allocations.
        if (activeScheduleIds[beneficiary].length >= MAX_SCHEDULES_PER_BENEFICIARY) revert TooManySchedules();

        // Check that contract balance is sufficient to cover all schedules
        if (hapToken.balanceOf(address(this)) < totalAllocated + totalAmount - totalReleased) {
            revert InsufficientContractBalance();
        }

        scheduleId = nextScheduleId++;

        schedules[scheduleId] = VestingSchedule({
            beneficiary: beneficiary,
            label: label,
            totalAmount: totalAmount,
            tgeUnlockAmount: tgeUnlockAmount,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            released: 0,
            revocable: revocable,
            revoked: false,
            revokedAt: 0
        });

        beneficiarySchedules[beneficiary].push(scheduleId);
        // Also push to the active list. _activeIdxPlusOne records the
        // (1-indexed) position so _removeFromActive can do an O(1) swap-and-pop.
        activeScheduleIds[beneficiary].push(scheduleId);
        _activeIdxPlusOne[scheduleId] = activeScheduleIds[beneficiary].length;

        // Add to allBeneficiaries if not already present
        if (!_isBeneficiary[beneficiary]) {
            allBeneficiaries.push(beneficiary);
            _isBeneficiary[beneficiary] = true;
        }

        totalAllocated += totalAmount;

        emit VestingScheduleCreated(
            scheduleId,
            beneficiary,
            label,
            totalAmount,
            tgeUnlockAmount,
            cliffDuration,
            vestingDuration,
            revocable
        );
    }

    // ========================================================================
    // Release Tokens
    // ========================================================================

    /**
     * @notice Releases vested but unclaimed tokens for a given schedule
     * @param scheduleId Schedule ID to release
     * @dev Anyone can call (caller pays gas, tokens go to beneficiary).
     *      This design allows keeper bots to periodically release on behalf of all beneficiaries.
     */
    function release(uint256 scheduleId) external nonReentrant {
        VestingSchedule storage schedule = schedules[scheduleId];
        if (schedule.totalAmount == 0) revert NoVestingSchedule();

        uint256 releasable = _computeReleasableAmount(scheduleId);
        if (releasable == 0) revert NothingToRelease();

        schedule.released += releasable;
        totalReleased += releasable;

        // Once fully released, drop the schedule from the active list so its
        // slot is freed and releaseAllMine stops iterating it.
        if (!schedule.revoked && schedule.released == schedule.totalAmount) {
            _removeFromActive(scheduleId, schedule.beneficiary);
        }

        hapToken.safeTransfer(schedule.beneficiary, releasable);

        emit TokensReleased(scheduleId, schedule.beneficiary, releasable);
    }

    /**
     * @notice Batch releases all schedules held by the caller
     * @dev Gas is bounded by MAX_SCHEDULES_PER_BENEFICIARY (50 schedules max per address).
     */
    function releaseAllMine() external nonReentrant {
        // Iterate the active list (capped at MAX_SCHEDULES_PER_BENEFICIARY) rather
        // than the full historical list, so gas stays bounded no matter how many
        // lifetime schedules the caller has accumulated. Snapshot to memory
        // before mutating storage via _removeFromActive.
        uint256[] memory ids = activeScheduleIds[msg.sender];
        uint256 totalReleasedNow = 0;

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 scheduleId = ids[i];
            VestingSchedule storage schedule = schedules[scheduleId];

            uint256 releasable = _computeReleasableAmount(scheduleId);
            if (releasable == 0) continue;

            schedule.released += releasable;
            totalReleasedNow += releasable;

            // Schedules that became fully released drop out of the active list
            // immediately so subsequent batch releases stay short.
            if (!schedule.revoked && schedule.released == schedule.totalAmount) {
                _removeFromActive(scheduleId, msg.sender);
            }

            emit TokensReleased(scheduleId, msg.sender, releasable);
        }

        if (totalReleasedNow == 0) revert NothingToRelease();

        totalReleased += totalReleasedNow;
        hapToken.safeTransfer(msg.sender, totalReleasedNow);
    }

    // ========================================================================
    // Revoke (applicable only to team/advisor types)
    // ========================================================================

    /**
     * @notice Revokes a revocable vesting schedule
     * @param scheduleId Schedule ID to revoke
     * @return forfeited Amount forfeited (not yet vested at revocation time)
     *
     * @dev Already vested but unreleased tokens are automatically sent to the beneficiary
     *      at revocation time, so they are not left stranded in the contract.
     */
    function revoke(uint256 scheduleId) external onlyRole(VESTING_ADMIN_ROLE) nonReentrant returns (uint256 forfeited) {
        VestingSchedule storage schedule = schedules[scheduleId];
        if (schedule.totalAmount == 0) revert NoVestingSchedule();
        if (!schedule.revocable) revert NotRevocable();
        if (schedule.revoked) revert AlreadyRevoked();

        uint256 vestedSoFar = _computeVestedAmount(schedule);
        forfeited = schedule.totalAmount - vestedSoFar;

        schedule.revoked = true;
        schedule.revokedAt = uint64(block.timestamp);

        // Subtract forfeited amount from total allocated
        totalAllocated -= forfeited;

        // Revoked schedules never need future processing — drop them from the
        // active list. _removeFromActive is a no-op if the schedule was already
        // removed (e.g. fully released earlier), so this handles the rare
        // release-then-revoke ordering safely.
        _removeFromActive(scheduleId, schedule.beneficiary);

        // Auto-release any vested but not yet claimed tokens to the beneficiary,
        // so they don't need a separate release() call after being revoked.
        uint256 autoReleased = vestedSoFar - schedule.released;
        if (autoReleased > 0) {
            schedule.released += autoReleased;
            totalReleased += autoReleased;
            hapToken.safeTransfer(schedule.beneficiary, autoReleased);
            emit TokensReleased(scheduleId, schedule.beneficiary, autoReleased);
        }

        emit VestingRevoked(scheduleId, schedule.beneficiary, autoReleased, forfeited, msg.sender);
    }

    /**
     * @notice Withdraws revoked but unreleased tokens (recommended destination: Treasury)
     * @param to Recipient address (should be the Treasury multisig)
     * @param amount Amount to withdraw
     *
     * @dev ⚠️ This function is separate from revoke() to keep the revoke operation atomic.
     *      The withdrawal requires separate multisig approval.
     */
    function rescueRevokedTokens(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");

        // Max rescuable = contract balance - total unreleased amount owed to beneficiaries
        uint256 unreleasedTotal = totalAllocated - totalReleased;
        uint256 contractBalance = hapToken.balanceOf(address(this));
        uint256 maxRescuable = contractBalance > unreleasedTotal ? contractBalance - unreleasedTotal : 0;

        require(amount <= maxRescuable, "Amount exceeds rescuable balance");

        hapToken.safeTransfer(to, amount);
    }

    // ========================================================================
    // View Functions
    // ========================================================================

    /**
     * @notice Computes the currently releasable amount for a given schedule
     */
    function computeReleasableAmount(uint256 scheduleId) external view returns (uint256) {
        return _computeReleasableAmount(scheduleId);
    }

    /**
     * @notice Computes the total vested amount for a given schedule up to now
     */
    function computeVestedAmount(uint256 scheduleId) external view returns (uint256) {
        VestingSchedule memory schedule = schedules[scheduleId];
        if (schedule.totalAmount == 0) return 0;
        return _computeVestedAmount(schedule);
    }

    /**
     * @notice Computes the total releasable amount across all schedules for a given beneficiary
     */
    function computeReleasableForBeneficiary(address beneficiary) external view returns (uint256 total) {
        uint256[] memory ids = beneficiarySchedules[beneficiary];
        for (uint256 i = 0; i < ids.length; i++) {
            total += _computeReleasableAmount(ids[i]);
        }
    }

    /**
     * @notice Returns the total number of schedules
     */
    function scheduleCount() external view returns (uint256) {
        return nextScheduleId;
    }

    /**
     * @notice Returns the number of unique beneficiaries
     */
    function beneficiaryCount() external view returns (uint256) {
        return allBeneficiaries.length;
    }

    /**
     * @notice Returns all schedule IDs held by a given beneficiary, historical
     *         and active alike (for frontend visibility / accounting).
     */
    function getSchedulesOf(address beneficiary) external view returns (uint256[] memory) {
        return beneficiarySchedules[beneficiary];
    }

    /**
     * @notice Returns only the currently-active schedule IDs (not fully released
     *         and not revoked) for a beneficiary. Mirrors what releaseAllMine()
     *         iterates and what the per-beneficiary cap restricts.
     */
    function getActiveSchedulesOf(address beneficiary) external view returns (uint256[] memory) {
        return activeScheduleIds[beneficiary];
    }

    /**
     * @notice Number of currently-active schedules for a beneficiary.
     * @dev    activeScheduleIds[beneficiary].length. Used by tests and frontends
     *         to query the remaining slot count against MAX_SCHEDULES_PER_BENEFICIARY.
     */
    function activeScheduleCount(address beneficiary) external view returns (uint256) {
        return activeScheduleIds[beneficiary].length;
    }

    /**
     * @notice Returns the full data for a given schedule
     */
    function getSchedule(uint256 scheduleId) external view returns (VestingSchedule memory) {
        return schedules[scheduleId];
    }

    /**
     * @notice Computes the vested amount at a specific timestamp (for frontend visualization)
     */
    function computeVestedAt(uint256 scheduleId, uint64 timestamp) external view returns (uint256) {
        VestingSchedule memory schedule = schedules[scheduleId];
        if (schedule.totalAmount == 0) return 0;
        return _computeVestedAtTimestamp(schedule, timestamp);
    }

    // ========================================================================
    // Internal: active-schedule index maintenance
    // ========================================================================

    /**
     * @dev Removes `scheduleId` from activeScheduleIds[beneficiary] in O(1) via
     *      swap-and-pop. No-op if the schedule is not in the active list (already
     *      removed by an earlier full-release or revoke).
     */
    function _removeFromActive(uint256 scheduleId, address beneficiary) internal {
        uint256 idxPlusOne = _activeIdxPlusOne[scheduleId];
        if (idxPlusOne == 0) return;

        uint256[] storage arr = activeScheduleIds[beneficiary];
        uint256 idx = idxPlusOne - 1;
        uint256 lastIdx = arr.length - 1;

        if (idx != lastIdx) {
            uint256 lastId = arr[lastIdx];
            arr[idx] = lastId;
            _activeIdxPlusOne[lastId] = idxPlusOne; // last item now lives at idx (1-indexed)
        }
        arr.pop();
        _activeIdxPlusOne[scheduleId] = 0;
    }

    // ========================================================================
    // Internal Calculations
    // ========================================================================

    /**
     * @dev Computes releasable amount = vested - released
     */
    function _computeReleasableAmount(uint256 scheduleId) internal view returns (uint256) {
        VestingSchedule memory schedule = schedules[scheduleId];
        if (schedule.totalAmount == 0) return 0;

        uint256 vested = _computeVestedAmount(schedule);
        if (vested <= schedule.released) return 0;

        return vested - schedule.released;
    }

    /**
     * @dev Core calculation: total vested amount up to the current moment
     *
     * Formula:
     *   if (now < TGE):                                    return 0
     *   if (revoked):                                      return vested at revokedAt
     *   if (now >= TGE && now < TGE + cliff):              return tgeUnlockAmount
     *   if (now >= TGE + cliff && now < TGE + cliff + vesting):
     *     vestedAfterCliff = (totalAmount - tgeUnlock) * elapsed / vestingDuration
     *     return tgeUnlockAmount + vestedAfterCliff
     *   if (now >= TGE + cliff + vesting):                 return totalAmount
     */
    function _computeVestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        return _computeVestedAtTimestamp(schedule, uint64(block.timestamp));
    }

    /**
     * @dev Computes vested amount at a specified timestamp
     */
    function _computeVestedAtTimestamp(VestingSchedule memory schedule, uint64 timestamp) internal view returns (uint256) {
        // 1. Before TGE: return 0
        if (timestamp < tgeTimestamp) {
            return 0;
        }

        // 2. If revoked, settle as of revokedAt timestamp
        uint64 effectiveTime = timestamp;
        if (schedule.revoked && timestamp > schedule.revokedAt) {
            effectiveTime = schedule.revokedAt;
        }

        // A revocation executed before TGE has revokedAt < tgeTimestamp; treat
        // it as zero-vested. Without this clamp, `effectiveTime - tgeTimestamp`
        // would underflow and revert, permanently breaking vested/releasable
        // views for the revoked schedule.
        if (effectiveTime < tgeTimestamp) {
            return 0;
        }

        // 3. Calculate elapsed time since TGE
        uint64 timeElapsed = effectiveTime - tgeTimestamp;

        // 4. Still within cliff period: only TGE unlock amount is available
        if (timeElapsed < schedule.cliffDuration) {
            return schedule.tgeUnlockAmount;
        }

        // 5. Past all cliff + vesting time: full amount is available
        uint64 totalVestingTime = schedule.cliffDuration + schedule.vestingDuration;
        if (timeElapsed >= totalVestingTime) {
            return schedule.totalAmount;
        }

        // 6. Past cliff, within vesting period: linear calculation
        uint64 elapsedInVesting = timeElapsed - schedule.cliffDuration;
        uint256 vestingAmount = schedule.totalAmount - schedule.tgeUnlockAmount;
        uint256 linearVested = (vestingAmount * elapsedInVesting) / schedule.vestingDuration;

        return schedule.tgeUnlockAmount + linearVested;
    }
}
