// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title VotingEscrowHAP
/// @notice Soulbound veHAP positions with linearly decaying voting power.
/// @dev Inspired by Velodrome V2's point-history model, deliberately omitting
///      transfers, approvals, split/merge, permanent locks and managed NFTs.
contract VotingEscrowHAP is ERC721, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_LOCK_TIME = 4 * 365 days;
    uint256 public constant MIN_LOCK_TIME = 1 weeks;

    IERC20 public immutable hap;
    uint256 public nextTokenId = 1;
    uint256 public totalLocked;

    struct Lock {
        uint208 amount;
        uint48 end;
    }

    struct LockCheckpoint {
        uint48 timestamp;
        uint48 end;
        uint208 amount;
    }

    struct AddressCheckpoint {
        uint48 timestamp;
        address account;
    }

    mapping(uint256 => Lock) public locks;
    mapping(uint256 => LockCheckpoint[]) private _lockHistory;
    mapping(uint256 => AddressCheckpoint[]) private _ownerHistory;
    mapping(uint256 => AddressCheckpoint[]) private _delegateHistory;
    mapping(uint256 => address) public delegates;

    error ZeroAddress();
    error ZeroAmount();
    error NotTokenOwner();
    error Soulbound();
    error InvalidUnlockTime();
    error LockNotExpired();
    error LockExpired();
    error AmountOverflow();

    event LockCreated(address indexed owner, uint256 indexed tokenId, uint256 amount, uint256 unlockTime);
    event LockAmountIncreased(uint256 indexed tokenId, address indexed payer, uint256 amount);
    event LockExtended(uint256 indexed tokenId, uint256 oldUnlockTime, uint256 newUnlockTime);
    event DelegateChanged(uint256 indexed tokenId, address indexed owner, address indexed delegate);
    event Withdrawn(address indexed owner, uint256 indexed tokenId, uint256 amount);

    constructor(address hapToken) ERC721("Vote Escrowed HAP", "veHAP") {
        if (hapToken == address(0)) revert ZeroAddress();
        hap = IERC20(hapToken);
    }

    function createLock(uint256 amount, uint256 unlockTime) external nonReentrant returns (uint256 tokenId) {
        if (amount == 0) revert ZeroAmount();
        _validateNewUnlockTime(unlockTime);
        if (amount > type(uint208).max) revert AmountOverflow();

        tokenId = nextTokenId++;
        locks[tokenId] = Lock(uint208(amount), uint48(unlockTime));
        totalLocked += amount;
        _safeMint(msg.sender, tokenId);
        _writeLockCheckpoint(tokenId);
        hap.safeTransferFrom(msg.sender, address(this), amount);
        emit LockCreated(msg.sender, tokenId, amount, unlockTime);
    }

    /// @notice Anyone may add HAP to an existing live lock; ownership never changes.
    function increaseAmount(uint256 tokenId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Lock storage lock = locks[tokenId];
        if (_ownerOf(tokenId) == address(0)) revert ERC721NonexistentToken(tokenId);
        if (block.timestamp >= lock.end) revert LockExpired();
        uint256 newAmount = uint256(lock.amount) + amount;
        if (newAmount > type(uint208).max) revert AmountOverflow();
        lock.amount = uint208(newAmount);
        totalLocked += amount;
        _writeLockCheckpoint(tokenId);
        hap.safeTransferFrom(msg.sender, address(this), amount);
        emit LockAmountIncreased(tokenId, msg.sender, amount);
    }

    function extendLock(uint256 tokenId, uint256 newUnlockTime) external {
        _checkOwner(tokenId);
        Lock storage lock = locks[tokenId];
        if (block.timestamp >= lock.end) revert LockExpired();
        if (newUnlockTime <= lock.end || newUnlockTime > block.timestamp + MAX_LOCK_TIME) {
            revert InvalidUnlockTime();
        }
        uint256 oldEnd = lock.end;
        lock.end = uint48(newUnlockTime);
        _writeLockCheckpoint(tokenId);
        emit LockExtended(tokenId, oldEnd, newUnlockTime);
    }

    /// @notice Delegate may vote, but ownership and withdrawal rights remain with the owner.
    function delegate(uint256 tokenId, address delegatee) external {
        _checkOwner(tokenId);
        delegates[tokenId] = delegatee;
        _writeAddressCheckpoint(_delegateHistory[tokenId], delegatee);
        emit DelegateChanged(tokenId, msg.sender, delegatee);
    }

    function withdraw(uint256 tokenId) external nonReentrant {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner) revert NotTokenOwner();
        Lock memory lock = locks[tokenId];
        if (block.timestamp < lock.end) revert LockNotExpired();

        delete locks[tokenId];
        delete delegates[tokenId];
        totalLocked -= lock.amount;
        _burn(tokenId);
        _writeLockCheckpoint(tokenId);
        hap.safeTransfer(owner, lock.amount);
        emit Withdrawn(owner, tokenId, lock.amount);
    }

    function votingPower(uint256 tokenId) external view returns (uint256) {
        return _power(locks[tokenId].amount, locks[tokenId].end, block.timestamp);
    }

    function votingPowerAt(uint256 tokenId, uint256 timestamp) public view returns (uint256) {
        LockCheckpoint memory cp = _lockCheckpointBefore(tokenId, timestamp);
        return _power(cp.amount, cp.end, timestamp);
    }

    function ownerAt(uint256 tokenId, uint256 timestamp) external view returns (address) {
        return _addressAt(_ownerHistory[tokenId], timestamp);
    }

    function delegateAt(uint256 tokenId, uint256 timestamp) external view returns (address) {
        return _addressAt(_delegateHistory[tokenId], timestamp);
    }

    function lockCheckpointCount(uint256 tokenId) external view returns (uint256) {
        return _lockHistory[tokenId].length;
    }

    function _validateNewUnlockTime(uint256 unlockTime) private view {
        if (unlockTime < block.timestamp + MIN_LOCK_TIME || unlockTime > block.timestamp + MAX_LOCK_TIME) {
            revert InvalidUnlockTime();
        }
    }

    function _checkOwner(uint256 tokenId) private view {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
    }

    function _power(uint256 amount, uint256 end, uint256 timestamp) private pure returns (uint256) {
        if (timestamp >= end) return 0;
        return amount * (end - timestamp) / MAX_LOCK_TIME;
    }

    function _writeLockCheckpoint(uint256 tokenId) private {
        Lock memory lock = locks[tokenId];
        LockCheckpoint[] storage history = _lockHistory[tokenId];
        LockCheckpoint memory cp = LockCheckpoint(uint48(block.timestamp), lock.end, lock.amount);
        if (history.length != 0 && history[history.length - 1].timestamp == block.timestamp) history[history.length - 1] = cp;
        else history.push(cp);
    }

    function _writeAddressCheckpoint(AddressCheckpoint[] storage history, address account) private {
        AddressCheckpoint memory cp = AddressCheckpoint(uint48(block.timestamp), account);
        if (history.length != 0 && history[history.length - 1].timestamp == block.timestamp) history[history.length - 1] = cp;
        else history.push(cp);
    }

    /// @dev Strictly-before semantics are intentional: state changes in the
    ///      first block whose timestamp equals an event start are post-snapshot.
    function _lockCheckpointBefore(uint256 tokenId, uint256 timestamp) private view returns (LockCheckpoint memory) {
        LockCheckpoint[] storage history = _lockHistory[tokenId];
        uint256 high = history.length;
        uint256 low;
        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (history[mid].timestamp < timestamp) low = mid + 1;
            else high = mid;
        }
        return low == 0 ? LockCheckpoint(0, 0, 0) : history[low - 1];
    }

    function _addressAt(AddressCheckpoint[] storage history, uint256 timestamp) private view returns (address) {
        uint256 high = history.length;
        uint256 low;
        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (history[mid].timestamp < timestamp) low = mid + 1;
            else high = mid;
        }
        return low == 0 ? address(0) : history[low - 1].account;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        address previousOwner = super._update(to, tokenId, auth);
        _writeAddressCheckpoint(_ownerHistory[tokenId], to);
        return previousOwner;
    }

    function approve(address, uint256) public pure override { revert Soulbound(); }
    function setApprovalForAll(address, bool) public pure override { revert Soulbound(); }
}
