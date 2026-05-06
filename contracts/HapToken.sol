// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title HapToken
 * @notice Hero Arena Play ($HAP) - The native token of the Hero Arena ecosystem
 * @dev Fixed supply BEP-20 token with burn, pause, and blacklist functionality.
 *      Mint function is intentionally NOT included. Total supply is locked at deployment.
 *
 * ⚠️ AUDIT NOTES FOR ALEX / CYBERSCOPE:
 * - Role management uses AccessControl instead of Ownable for multisig compatibility
 * - DEFAULT_ADMIN_ROLE should be transferred to a 3-of-5 Gnosis Safe multisig immediately after deployment
 * - PAUSER_ROLE should only be used in emergencies (contract vulnerabilities, black swan events)
 * - BLACKLIST_ROLE is for OFAC compliance (only add sanctioned addresses)
 *
 * ⚠️ Known unimplemented features (to be added before production):
 * - No EIP-2612 permit() function (required for DeFi integrations)
 * - No EIP-1967 upgrade proxy (by design: this contract is non-upgradeable and permanently fixed)
 * - No cross-chain bridging logic (a separate contract is required for future multi-chain support)
 */
contract HapToken is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========================================================================
    // Constants
    // ========================================================================

    /// @notice Total supply: 1 billion HAP (fixed, non-mintable)
    /// @dev 1_000_000_000 * 10^18 = 1e27
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;

    /// @notice Pauser admin role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Blacklist admin role (for adding OFAC sanctioned addresses)
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");

    // ========================================================================
    // State Variables
    // ========================================================================

    /// @notice Blacklisted address mapping (OFAC sanctioned addresses, etc.)
    mapping(address => bool) public blacklisted;

    /// @notice Addresses that are permanently exempt from blacklisting (core protocol contracts)
    mapping(address => bool) public protectedFromBlacklist;

    /// @notice Cumulative burn amount — updated on every burn path via _update
    uint256 public totalBurned;

    // ========================================================================
    // Events
    // ========================================================================

    event AddressBlacklisted(address indexed account, address indexed admin);
    event AddressUnblacklisted(address indexed account, address indexed admin);
    event TokensBurnedFromRevenue(uint256 amount, string reason);
    event ProtectedAddressSet(address indexed account, bool protected_);

    // ========================================================================
    // Custom Errors
    // ========================================================================

    error AddressIsBlacklisted(address account);
    error CannotBlacklistZeroAddress();
    error CannotBlacklistProtectedAddress(address account);
    error AddressAlreadyBlacklisted(address account);
    error AddressNotBlacklisted(address account);
    error InsufficientBalance(uint256 requested, uint256 available);

    // ========================================================================
    // Constructor
    // ========================================================================

    /**
     * @notice Deploys the contract and mints the full supply to the initial admin address
     * @param initialAdmin Initial admin address (should be a 3-of-5 Gnosis Safe multisig)
     *
     * @dev ⚠️ Immediately transfer all tokens to the Vesting contract and Treasury multisig after deployment.
     *      Do not leave 1B HAP in a regular wallet!
     */
    constructor(address initialAdmin) ERC20("Hero Arena Play", "HAP") {
        require(initialAdmin != address(0), "Admin cannot be zero address");

        // Set initial admin (should be a multisig)
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
        _grantRole(BLACKLIST_ROLE, initialAdmin);

        // One-time mint of full supply to initial admin (cannot be minted again).
        // ⚠️ Warning: do not allocate 1B to a regular wallet in production.
        // The deploy script should immediately call transfer() to distribute tokens to the Vesting contract.
        _mint(initialAdmin, TOTAL_SUPPLY);
    }

    // ========================================================================
    // Blacklist Management
    // ========================================================================

    /**
     * @notice Registers or removes a core protocol contract as exempt from blacklisting
     * @param account Address to protect (e.g. HapVesting, HapTreasury)
     * @param status true = protected, false = unprotected
     *
     * @dev ⚠️ Call this immediately after deploying HapVesting and HapTreasury.
     *      Blacklisting those addresses would permanently freeze all protocol fund movements.
     */
    function setProtected(address account, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Cannot protect zero address");
        protectedFromBlacklist[account] = status;
        emit ProtectedAddressSet(account, status);
    }

    /**
     * @notice Adds an address to the blacklist (for OFAC sanctioned addresses)
     * @param account Address to blacklist
     *
     * @dev ⚠️ This function must be used with caution, only for:
     *      1. OFAC sanctions list addresses
     *      2. Addresses adjudicated as proceeds of crime by a court
     *      Do not use for ordinary commercial disputes.
     */
    function blacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        if (account == address(0)) revert CannotBlacklistZeroAddress();
        if (protectedFromBlacklist[account]) revert CannotBlacklistProtectedAddress(account);
        if (blacklisted[account]) revert AddressAlreadyBlacklisted(account);

        blacklisted[account] = true;
        emit AddressBlacklisted(account, msg.sender);
    }

    /**
     * @notice Removes an address from the blacklist
     * @param account Address to remove from the blacklist
     */
    function unblacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        if (!blacklisted[account]) revert AddressNotBlacklisted(account);

        blacklisted[account] = false;
        emit AddressUnblacklisted(account, msg.sender);
    }

    // ========================================================================
    // Pause Functionality
    // ========================================================================

    /**
     * @notice Emergency pause of all transfers (use only for critical vulnerabilities)
     *
     * @dev ⚠️ Calling this function pauses all transfer operations (including IDO withdrawals, player rewards, etc.)
     *      Use only in the following situations:
     *      1. A critical vulnerability is discovered in the smart contract
     *      2. An active hack is in progress
     *      3. Court order
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ========================================================================
    // Burn Functionality (for Buyback & Burn mechanism)
    // ========================================================================

    /**
     * @notice Burns tokens from project revenue (for transparent buyback & burn accounting)
     * @param amount Amount to burn
     * @param reason Burn reason ("WAGER_RAKE", "MARKETPLACE_FEE", "TOURNAMENT_ENTRY", "NFT_MINT")
     *
     * @dev Functionally equivalent to ERC20Burnable.burn(), but additionally records the reason.
     *      totalBurned is updated inside _update to capture ALL burn paths uniformly.
     */
    function burnFromRevenue(uint256 amount, string calldata reason) external nonReentrant {
        _burn(msg.sender, amount);
        emit TokensBurnedFromRevenue(amount, reason);
    }

    // ========================================================================
    // Transfer Hook (overrides parent contracts)
    // ========================================================================

    /**
     * @dev Checks before each transfer:
     *      1. The contract is not paused
     *      2. Neither the sender nor the receiver is blacklisted
     *      3. If this is a burn (to == address(0)), increments totalBurned
     *
     * @notice This is the standard hook method name in OpenZeppelin v5.x.
     *         If using OpenZeppelin v4.x, the method name is _beforeTokenTransfer.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        // Blacklist check
        if (blacklisted[from]) revert AddressIsBlacklisted(from);
        if (blacklisted[to]) revert AddressIsBlacklisted(to);

        // Track all burns uniformly: burn(), burnFrom(), and burnFromRevenue() all pass through here
        if (to == address(0)) {
            totalBurned += value;
        }

        super._update(from, to, value);
    }

    // ========================================================================
    // Emergency Recovery
    // ========================================================================

    /**
     * @notice Rescues ERC-20 tokens accidentally sent to this contract (not HAP itself)
     * @param token Address of the token to rescue
     * @param to Rescue destination address
     * @param amount Amount to rescue
     *
     * @dev Prevents permanently locking tokens that users accidentally send to this contract (e.g. USDT, BNB).
     *      ⚠️ This function cannot rescue HAP itself (to prevent admin abuse).
     */
    function rescueERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(this), "Cannot rescue HAP itself");
        require(to != address(0), "Cannot rescue to zero address");

        // SafeERC20 handles non-standard tokens that don't return a bool (e.g. USDT)
        IERC20(token).safeTransfer(to, amount);
    }

    // ========================================================================
    // View Functions (for frontend use)
    // ========================================================================

    /**
     * @notice Returns cumulative burn stats (for frontend display)
     * @return burned Total HAP burned across all burn paths
     * @return remaining Current total supply (equals initial supply minus all burned)
     */
    function burnStats() external view returns (uint256 burned, uint256 remaining) {
        burned = totalBurned;
        remaining = totalSupply();
    }
}
