// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {HeroArenaProfileInterface} from "./interfaces/HeroArenaProfileInterface.sol";

/**
 * @title HeroArenaWorldCupInitializable
 *
 * @notice Tournament bracket bootstrap. Three-phase lifecycle:
 *
 *   1. Registration. While registration is open, any address that meets the
 *      basic conditions (currently: owns a HeroArenaProfile) may register itself
 *      as an eligible player. The owner controls the registration window through
 *      a single cut-off timestamp (see setRegisterDeadline).
 *
 *   2. Battle creation. The owner creates an arbitrary number of battles. Each
 *      battle has two seats (player0 / player1) that MUST both be assigned by
 *      the owner at creation time to distinct registered players.
 *
 *   3. Settlement. An address holding LIQUIDATOR_ROLE settles a battle by
 *      naming the winner. Settlement is the only terminal state.
 */
contract HeroArenaWorldCupInitializable is Ownable, AccessControl, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    // ---------- Roles ----------
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // ---------- External deps ----------
    /// @dev HapToken is set once in the constructor and never mutated;
    IERC20 public HapToken;
    HeroArenaProfileInterface public HeroArenaProfileSC;

    // Fee of HAP that a user needs to pay to for registration
    uint256 public registrationFee;

    mapping(address => bool) public registeredPlayerAddresses;

    /// @notice The battle a player occupies a seat in. 0 = none (not seated).
    ///         A player can be in at most one battle; once seated they remain
    ///         seated until the battle is settled.
    mapping(address => uint256) public playerBattleId;

    /// @notice HAP actually paid by each player at registration time. Refunds use
    ///         this exact amount so a later registrationFee change cannot over- or
    ///         under-pay. 0 for players added via addRegisterPlayerAddresses.
    mapping(address => uint256) public paidFee;

    /// @notice Sum of paidFee across all players still eligible for a refund
    ///         (registered and not yet seated in a battle). This pool is reserved:
    ///         claimFee() may only withdraw HAP held in excess of it.
    uint256 public totalRefundable;

    /// @notice Optional bonus paid to a battle's winner on settlement.
    /// @dev    Disabled iff bonusAmount == 0. When enabled, bonusToken == address(0)
    ///         pays a NATIVE ETH bonus and any other value pays that ERC20. The pool
    ///         must be funded by the owner (depositToken / depositNative / direct
    ///         transfer). A bonus is paid only from free balance, so when bonusToken
    ///         == HAP it can never eat into the reserved refund pool (totalRefundable).
    address public bonusToken;
    uint256 public bonusAmount;

    // ---------- Structs ----------
    struct BattleInfo {
        address player0Address;    // player 0 (left side)
        address player1Address;    // player 1 (right side)
        uint256 createdAt;         // 0 = battle does not exist
        address winner;
        bool isEnded;              // true once settled
    }

    // ---------- State ----------
    /// @notice Registration cut-off (unix timestamp) and the sole switch for
    ///         registration. 0 = closed. When non-zero, registration is open until
    ///         block.timestamp reaches it, then auto-closes. Set a future value to
    ///         open registration; set back to 0 to close it immediately.
    uint256 public registerDeadline;

    mapping(uint256 => BattleInfo) private _battles;
    uint256 private _battleCount;

    // ---------- Events ----------
    event RegistrationFeeUpdated(uint256 newFee);
    event RegisterDeadlineUpdated(address indexed owner, uint256 deadline);
    event BattleRegistered(address indexed player);
    event BattleCreated(
        uint256 indexed battleId,
        address indexed creator,
        address player0Address,
        address player1Address
    );
    event BattleEnded(uint256 indexed battleId, address indexed winner);
    event FeeClaimed(address indexed owner, uint256 amount);
    event RegistrationRefunded(address indexed player, uint256 amount, bool selfInitiated);
    event RefundSkipped(address indexed player);
    event BonusTokenUpdated(address indexed owner, address bonusToken, uint256 bonusAmount);
    event TokenDeposited(address indexed depositor, address indexed token, uint256 amount);
    /// @notice Bonus payout result on settlement. success=false means the bonus was
    ///         skipped (pool short of free balance, or token reverted); the battle
    ///         still settled normally.
    event BonusPayout(uint256 indexed battleId, address indexed winner, address token, uint256 amount, bool success);
    event ExtraTokensRescued(address indexed owner, address indexed token, address indexed to, uint256 amount);

    error AlreadyInitialized();

    // ---------- Constructor ----------
    constructor() Ownable(msg.sender) {
        
    }

    function initialize(address _adminAddress, address _hapTokenAddress, uint256 _registrationFee, address _haProfileAddress, address _bonusToken, uint256 _bonusAmount) public {
        if (isInitialized) {
            revert AlreadyInitialized();
        }

        // Transfer ownership to admin. H-3: also seed LIQUIDATOR_ROLE on the admin
        // so battles are settleable out of the box; admin can grant/revoke more
        // liquidators later via AccessControl.
        _grantRole(DEFAULT_ADMIN_ROLE, _adminAddress);
        _grantRole(LIQUIDATOR_ROLE, _adminAddress);
        transferOwnership(_adminAddress);

        HapToken = IERC20(_hapTokenAddress);
        registrationFee = _registrationFee;
        HeroArenaProfileSC = HeroArenaProfileInterface(_haProfileAddress);

        bonusToken = _bonusToken;
        bonusAmount = _bonusAmount;

        // Make this contract initialized
        isInitialized = true;
    }

    // =====================================================================
    //                    Ownership / role synchronization
    // =====================================================================

    /**
     * @dev Keep DEFAULT_ADMIN_ROLE in lock-step with Ownable ownership so the
     *      two permission models can never silently diverge. Transferring ownership
     *      moves the admin role to the new owner and revokes it from the old one.
     *      (LIQUIDATOR_ROLE is intentionally independent and is NOT moved.)
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), "New owner is zero");
        address previousOwner = owner();
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        if (previousOwner != newOwner) {
            _revokeRole(DEFAULT_ADMIN_ROLE, previousOwner);
        }
        super.transferOwnership(newOwner);
    }

    /**
     * @dev Renouncing ownership must also drop the matching admin role so a
     *      stale DEFAULT_ADMIN_ROLE can't linger after the owner is gone.
     */
    function renounceOwnership() public override onlyOwner {
        _revokeRole(DEFAULT_ADMIN_ROLE, owner());
        super.renounceOwnership();
    }

    // =====================================================================
    //                          Registration
    // =====================================================================

    /**
     * @notice Whether registration is currently open. Open iff a future deadline
     *         is set and not yet reached.
     */
    function isRegistrationOpen() public view returns (bool) {
        return registerDeadline != 0 && block.timestamp < registerDeadline;
    }

    /**
     * @notice Register the caller as an eligible player.
     * @dev    Basic condition (for now): the caller must own a HeroArenaProfile.
     *         Additional conditions can be layered in later.
     * @param _maxFee Maximum HAP fee the caller is willing to pay. Pass
     *                `type(uint256).max` to opt out of slippage protection.
     */
    function registerBattle(uint256 _maxFee) external nonReentrant {
        require(isRegistrationOpen(), "Registration is closed");
        require(HeroArenaProfileSC.hasRegistered(msg.sender), "Profile not registered");
        require(!registeredPlayerAddresses[msg.sender], "Already registered");

        uint256 _fee = registrationFee;
        require(_fee <= _maxFee, "Fee exceeds maximum");

        registeredPlayerAddresses[msg.sender] = true;
        paidFee[msg.sender] = _fee;
        totalRefundable += _fee;

        // transfer fee
        HapToken.safeTransferFrom(msg.sender, address(this), _fee);

        emit BattleRegistered(msg.sender);
    }

    /**
     * @notice Batch-register player addresses as eligible players.
     * @param playerAddresses The player addresses to register.
     * @dev    Owner-only. Skips the zero address and addresses already registered.
     *         These players pay no fee (paidFee stays 0), so they are not entitled
     *         to a refund.
     */
    function addRegisterPlayerAddresses(address[] calldata playerAddresses) external onlyOwner {
        uint256 len = playerAddresses.length;
        for (uint256 i = 0; i < len; ) {
            address player = playerAddresses[i];
            if (player != address(0) && !registeredPlayerAddresses[player]) {
                registeredPlayerAddresses[player] = true;
                emit BattleRegistered(player);
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Self-service: cancel your own registration and get your HAP back.
     * @dev    Only allowed while you have not been seated in a battle. Once seated
     *         (playerBattleId != 0) the fee is committed and cannot be withdrawn.
     */
    function cancelRegistration() external nonReentrant {
        require(registeredPlayerAddresses[msg.sender], "Not registered");
        require(playerBattleId[msg.sender] == 0, "Already in a battle");
        _refundAndDeregister(msg.sender, true);
    }

    /**
     * @notice Owner refunds registered players who were never seated in a battle.
     * @param players Addresses to process. Non-registered or already-seated
     *                addresses are silently skipped.
     * @dev    Only callable once the registration deadline has passed, i.e. after
     *         the bracket has been finalized via createBattle. Pass the players in
     *         batches to stay within the block gas limit.
     */
    function refundUnselectedPlayers(address[] calldata players) external nonReentrant onlyOwner {
        require(registerDeadline != 0 && block.timestamp >= registerDeadline, "Deadline not reached");
        uint256 len = players.length;
        for (uint256 i = 0; i < len; ) {
            address player = players[i];
            // Only registered, not-yet-seated players are refundable.
            if (registeredPlayerAddresses[player] && playerBattleId[player] == 0) {
                // Isolate each refund through an external self-call: if a recipient
                // reverts on receipt, try/catch rolls back only that player's state
                // changes and the batch carries on instead of bricking entirely.
                try this.refundSeat(player) {
                } catch {
                    emit RefundSkipped(player);
                }
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Refund a single not-yet-seated registered player. Self-call helper
     *         for refundUnselectedPlayers; not callable externally by others.
     */
    function refundSeat(address player) external {
        require(msg.sender == address(this), "Only self");
        _refundAndDeregister(player, false);
    }

    /**
     * @dev Refund a player's recorded fee, clear their registration and release the
     *      reserved amount from the refundable pool. Caller must guarantee the
     *      player is registered and not seated in any battle.
     */
    function _refundAndDeregister(address player, bool selfInitiated) internal {
        uint256 amount = paidFee[player];

        registeredPlayerAddresses[player] = false;
        paidFee[player] = 0;

        if (amount > 0) {
            totalRefundable -= amount;
            HapToken.safeTransfer(player, amount);
        }

        emit RegistrationRefunded(player, amount, selfInitiated);
    }

    // =====================================================================
    //                          Battle lifecycle
    // =====================================================================

    /**
     * @notice Create a new battle. Owner decides how many to create.
     * @param _player0Address Designated player0; must be a registered player.
     * @param _player1Address Designated player1; must be a registered player.
     * @dev    Both seats must be assigned at creation time. Each player must be
     *         registered and not already in another battle, and the two seats
     *         must be distinct addresses. A battle is started immediately.
     */
    function createBattle(
        address _player0Address,
        address _player1Address
    ) external nonReentrant onlyOwner {
        require(_player0Address != address(0), "player0 required");
        require(_player1Address != address(0), "player1 required");
        require(_player0Address != _player1Address, "Players must differ");

        require(registeredPlayerAddresses[_player0Address], "player0 not registered");
        require(registeredPlayerAddresses[_player1Address], "player1 not registered");

        require(playerBattleId[_player0Address] == 0, "player0 already in a battle");
        require(playerBattleId[_player1Address] == 0, "player1 already in a battle");

        uint256 battleId = ++_battleCount;
        playerBattleId[_player0Address] = battleId;
        playerBattleId[_player1Address] = battleId;

        // NOTE: a seat's fee stays in the refundable pool until the battle is
        // settled, at which point it becomes "earned" (see settleBattle).

        BattleInfo storage b = _battles[battleId];
        b.player0Address = _player0Address;
        b.player1Address = _player1Address;
        b.createdAt = block.timestamp;

        emit BattleCreated(battleId, msg.sender, _player0Address, _player1Address);
    }

    /**
     * @notice Settle a started battle by declaring its winner.
     * @param _battleId Battle to settle.
     * @param _winner   Winner; must be one of the two seated players.
     */
    function settleBattle(uint256 _battleId, address _winner)
        external
        nonReentrant
        onlyRole(LIQUIDATOR_ROLE)
    {
        BattleInfo storage b = _battles[_battleId];
        require(b.createdAt != 0, "Battle does not exist");
        require(!b.isEnded, "Battle already ended");
        require(
            _winner == b.player0Address || _winner == b.player1Address,
            "Invalid winner address"
        );

        b.winner = _winner;
        b.isEnded = true;

        // Settlement is terminal: the two seats' fees are now earned and leave the
        // refundable pool, becoming withdrawable by the owner via claimFee.
        // M-2: clamp the release to the current pool. Under the present invariant
        // both fees are always still in the pool, but clamping guarantees a future
        // accounting bug can never underflow here and permanently brick settlement.
        uint256 released = paidFee[b.player0Address] + paidFee[b.player1Address];
        if (released > totalRefundable) {
            released = totalRefundable;
        }
        totalRefundable -= released;

        // Optional bonus to the winner. A bonus failure (pool short of free
        // balance, weird token) MUST NOT block settlement, so we draw only from
        // unreserved balance and use a non-reverting payout; on miss we just emit
        // success=false. (Done after the totalRefundable release above so the two
        // just-earned seat fees count toward free balance.)
        // bonus disabled iff amount == 0. token == address(0) is a *native ETH*
        // bonus (not "disabled"); a non-zero token is an ERC20 bonus.
        address _bonusToken = bonusToken;
        uint256 _bonusAmount = bonusAmount;
        if (_bonusAmount > 0) {
            bool sent = false;
            if (_hasFreeBalance(_bonusToken, _bonusAmount)) {
                sent = _tryPayout(_bonusToken, _winner, _bonusAmount);
            }
            emit BonusPayout(_battleId, _winner, _bonusToken, _bonusAmount, sent);
        }

        emit BattleEnded(_battleId, _winner);
    }

    // =====================================================================
    //                          Internals
    // =====================================================================

    /**
     * @dev True if the contract holds enough `token` to send `amount` WITHOUT
     *      touching reserved balance. Only HAP carries a reserved liability (the
     *      refund pool); any other token held here is fully free for bonuses.
     */
    function _hasFreeBalance(address token, uint256 amount) internal view returns (bool) {
        uint256 balance = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
        // Only HAP carries a reserved liability (the refund pool). Native ETH and
        // every other token are fully free. HapToken is never address(0), so a
        // native bonus (token == address(0)) always has reserved == 0.
        uint256 reserved = token == address(HapToken) ? totalRefundable : 0;
        if (balance < reserved) return false;
        return balance - reserved >= amount;
    }

    /**
     * @dev Non-reverting payout. Returns true on success, false on failure instead
     *      of reverting, so an optional bonus can never brick settlement.
     *      token == address(0) sends native ETH via a low-level call; otherwise a
     *      low-level ERC20 transfer is used, supporting both standard tokens (return
     *      bool) and non-standard ones (USDT-style, no return value).
     */
    function _tryPayout(address token, address to, uint256 amount) internal returns (bool ok) {
        if (token == address(0)) {
            (ok, ) = to.call{value: amount}("");
            return ok;
        }
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        (bool success, bytes memory ret) = token.call(data);
        if (!success) return false;
        if (ret.length == 0) {
            ok = true;
        } else if (ret.length == 32) {
            ok = (abi.decode(ret, (uint256)) != 0);
        } else {
            ok = false;
        }
    }

    // =====================================================================
    //                          Views
    // =====================================================================

    function getBattleInfo(uint256 _battleId) external view returns (BattleInfo memory) {
        return _battles[_battleId];
    }

    function getBattleCount() external view returns (uint256) {
        return _battleCount;
    }

    // =====================================================================
    //                          Admin
    // =====================================================================

    /**
     * Update Registration's fee.
     */
    function updateRegistrationFee(uint256 _newFee) external onlyOwner {
        registrationFee = _newFee;

        // emit event
        emit RegistrationFeeUpdated(_newFee);
    }

    /**
     * @notice Open or close registration by setting its cut-off timestamp.
     * @param _deadline Unix timestamp in the future to open registration until
     *                  then, or 0 to close registration immediately.
     */
    function setRegisterDeadline(uint256 _deadline) external onlyOwner {
        require(_deadline == 0 || _deadline > block.timestamp, "Deadline must be in the future");
        registerDeadline = _deadline;
        emit RegisterDeadlineUpdated(msg.sender, _deadline);
    }

    /**
     * @notice Configure the winner bonus. Set bonusAmount to 0 to disable. When
     *         enabled, bonusToken == address(0) pays a native ETH bonus; any other
     *         address pays that ERC20. The pool must be funded separately.
     */
    function updateBonusToken(address _bonusToken, uint256 _bonusAmount) external onlyOwner {
        bonusToken = _bonusToken;
        bonusAmount = _bonusAmount;
        emit BonusTokenUpdated(msg.sender, _bonusToken, _bonusAmount);
    }

    /**
     * @notice Fund the contract with a token (e.g. to top up the bonus pool).
     * @dev    Owner pulls `_amount` of `_token` into the contract. For HAP this
     *         counts as free/claimable balance, not reserved refunds.
     */
    function depositToken(address _token, uint256 _amount) external onlyOwner nonReentrant {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        emit TokenDeposited(msg.sender, _token, _amount);
    }

    /**
     * @notice Fund the contract with native ETH (e.g. to top up a native bonus pool).
     * @dev    Native ETH carries no reserved liability, so it counts as fully free
     *         balance available for the winner bonus.
     */
    function depositNative() external payable onlyOwner nonReentrant {
        emit TokenDeposited(msg.sender, address(0), msg.value);
    }

    /// @dev Accept plain ETH transfers so a native bonus pool can also be funded by
    ///      a direct send. Any stuck ETH remains recoverable via rescueExtraTokens.
    receive() external payable {}

    /**
     * @notice HAP the owner may currently withdraw: the contract balance minus the
     *         reserved refund pool. Never lets withdrawals eat into pending refunds.
     */
    function claimableFee() public view returns (uint256) {
        uint256 balance = HapToken.balanceOf(address(this));
        return balance > totalRefundable ? balance - totalRefundable : 0;
    }

    /**
     * Transfer earned HAP fees back to the owner.
     * @dev Capped at claimableFee() so the funds reserved for not-yet-settled
     *      refunds (totalRefundable) can never be withdrawn out from under players.
     *      Emits FeeClaimed so off-chain analytics can track admin withdrawals
     *      without parsing raw ERC20 transfer logs.
     */
    function claimFee(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount <= claimableFee(), "Exceeds claimable fees");
        // Transfer HAP tokens to owner
        HapToken.safeTransfer(msg.sender, _amount);
        emit FeeClaimed(msg.sender, _amount);
    }

    /**
     * @notice Rescue tokens that are NOT part of the protocol's reserved accounting.
     *         Use cases: leftover bonus tokens deposited via depositToken, earned HAP
     *         fees routed to a custom destination, or tokens (or ETH) accidentally
     *         transferred to this contract.
     * @param _token  Token address (address(0) = native ETH).
     * @param _to     Destination address.
     * @param _amount Amount to rescue.
     *
     * @dev Bounded by  balance − reserved, where `reserved` is totalRefundable for
     *      HAP and 0 for every other token (the winner bonus is best-effort and is
     *      never a reserved liability). Therefore this function CAN NEVER drain the
     *      HAP refund pool owed to registered, not-yet-settled players (use claimFee
     *      for the normal earned-fee path). Reverts if the rescue would exceed the
     *      available headroom.
     */
    function rescueExtraTokens(address _token, address _to, uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Amount must be > 0");

        uint256 totalBalance = (_token == address(0))
            ? address(this).balance
            : IERC20(_token).balanceOf(address(this));

        // Only HAP carries a reserved liability (the refund pool); any other token
        // held here — including the bonus token and ETH — is fully rescuable.
        uint256 reserved = (_token == address(HapToken)) ? totalRefundable : 0;
        require(totalBalance >= reserved, "Accounting underflow");
        uint256 available = totalBalance - reserved;
        require(_amount <= available, "Amount exceeds rescuable balance");

        if (_token == address(0)) {
            (bool ok, ) = _to.call{value: _amount}("");
            require(ok, "ETH transfer failed");
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }

        emit ExtraTokensRescued(msg.sender, _token, _to, _amount);
    }
}
