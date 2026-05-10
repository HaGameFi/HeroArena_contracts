// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {HeroArenaProfileInterface} from "./interfaces/HeroArenaProfileInterface.sol";

/**
 * @title HeroArenaBattle
 */
contract HeroArenaBattle is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------- Roles ----------
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // ---------- External deps ----------
    HeroArenaProfileInterface public immutable HeroArenaProfileSC;

    // ---------- Structs ----------
    struct BattleInfo {
        address selfAddress;       // battle creator
        address targetAddress;     // designated opponent; address(0) = open match; overwritten with actual joiner on join
        address betTokenAddress;   // bet token (address(0) = native ETH)
        uint256 betAmount;
        uint256 createdAt;
        address winner;
        bool isStarted;            // opponent has joined
        bool isEnded;              // settled or closed
    }

    // ---------- State ----------
    mapping(address => bool) public allowedBetTokens;
    mapping(address => bool) public forbiddenToPlay;
    bool public availableCreateBattle;

    // minBetAmount[0] = min ETH bet, minBetAmount[1] = min ERC20 bet
    uint256[2] public minBetAmount;

    // tokenAddresses[0] = feeToken, tokenAddresses[1] = bonusToken
    // tokenAmounts[0]   = feeAmount, tokenAmounts[1]   = bonusAmount
    address[2] public tokenAddresses;
    uint256[2] public tokenAmounts;

    mapping(uint256 => BattleInfo) private _battles;
    uint256 private _battleCount;

    // ---------- Protocol fee ----------
    // Taken from totalReward (betAmount * 2) on settleBattle().
    // NOT taken on closeBattle() (that's a refund of the creator's own funds).
    //
    // The kill-switch is protocolFeeBps == 0.
    //
    // When protocolFeeBps > 0:
    //   - If protocolFeeRecipient != 0  → fee is pushed to recipient at settle time.
    //   - If protocolFeeRecipient == 0  → fee accumulates in accruedProtocolFees[token]
    //                                     for admin to withdraw later via
    //                                     withdrawProtocolFees().
    //
    // protocolFeeBps is capped at MAX_PROTOCOL_FEE_BPS to prevent admin abuse.

    /// @notice Protocol fee in basis points (1 bps = 0.01 %). 0 = disabled.
    uint256 public protocolFeeBps;

    /// @notice Optional auto-recipient of the protocol fee.
    /// @dev    address(0) means fees accumulate for later withdrawal instead of
    ///         being pushed on each settlement.
    address public protocolFeeRecipient;

    /// @notice Accumulated protocol fees per token (address(0) = native ETH).
    /// @dev    Only credited when protocolFeeRecipient == address(0).
    ///         Withdrawn via withdrawProtocolFees(). Decoupled from raw contract
    ///         balance so battle bets can never be touched by mistake.
    mapping(address => uint256) public accruedProtocolFees;

    /// @notice Total bets currently locked in unsettled battles, per token.
    /// @dev    Incremented on every _receiveBet, decremented on settleBattle
    ///         (by 2 × betAmount) and closeBattle (by 1 × betAmount).
    ///         Used by rescueExtraTokens() to enforce that locked battle funds
    ///         can never be swept.
    mapping(address => uint256) public outstandingBets;

    /// @notice Hard cap on protocolFeeBps (10 %). Cannot be exceeded by admin.
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1000;

    /// @notice Basis-points denominator (10000 = 100 %).
    uint256 public constant BPS_DENOMINATOR = 10000;

    // ---------- Events ----------
    event AllowedBetTokenUpdated(address indexed owner, address indexed token, bool allowed);
    event AvailableCreateBattleUpdated(address indexed owner, bool isAvail);
    event BattleCreated(
        uint256 indexed battleId,
        address indexed creator,
        address targetAddress,
        address betTokenAddress,
        uint256 betAmount
    );
    event BattleJoined(uint256 indexed battleId, address indexed joiner);
    event BattleEnded(uint256 indexed battleId, address indexed winner, uint256 totalReward);
    event BattleClosed(uint256 indexed battleId, address indexed closedBy, uint256 refundedAmount);
    event BattleConceded(uint256 indexed battleId, address indexed conceder, address indexed winner, uint256 totalReward);
    event FeeTokenAndBonusTokenUpdated(
        address indexed owner,
        address feeToken,
        uint256 feeTokenAmount,
        address bonusToken,
        uint256 bonusTokenAmount
    );
    event ForbiddenToPlayUpdated(address indexed owner, address indexed userAddress, bool isForbidden);
    event MinimumBetTokenAmountUpdated(address indexed owner, uint256 amount0, uint256 amount1);
    event TokenDeposited(address indexed depositor, address indexed tokenAddress, uint256 amount);
    event ExtraTokensRescued(address indexed admin, address indexed token, address indexed to, uint256 amount);
    event ProtocolFeeUpdated(address indexed admin, uint256 oldFeeBps, uint256 newFeeBps);
    event ProtocolFeeRecipientUpdated(address indexed admin, address oldRecipient, address newRecipient);
    /// @notice Emitted when fee is charged. recipient == address(0) means it was accrued, not pushed.
    event ProtocolFeeCharged(uint256 indexed battleId, address indexed token, address indexed recipient, uint256 amount);
    event ProtocolFeeWithdrawn(address indexed admin, address indexed token, address indexed to, uint256 amount);
    /// @notice Bonus payout result. success=false means bonus was skipped (e.g. pool empty
    ///         or token reverted). Settlement still went through and the winner got the main reward.
    event BonusPayout(uint256 indexed battleId, address indexed winner, address indexed token, uint256 amount, bool success);

    // ---------- Constructor ----------
    constructor(HeroArenaProfileInterface _HeroArenaProfileSC) Ownable(msg.sender) {
        HeroArenaProfileSC = _HeroArenaProfileSC;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    receive() external payable {}

    // ---------- Modifiers ----------
    modifier onlyRegisteredAndAllowed() {
        require(HeroArenaProfileSC.hasRegistered(msg.sender), "Profile not registered");
        require(!forbiddenToPlay[msg.sender], "Forbidden to play");
        _;
    }

    // =====================================================================
    //                          Battle lifecycle
    // =====================================================================

    /**
     * @notice Create a new battle.
     * @param _betTokenAddress Bet token; address(0) = native ETH.
     * @param _betAmount       Bet amount.
     * @param _targetAddress   Designated opponent; address(0) = open match.
     */
    function createBattle(
        address _betTokenAddress,
        uint256 _betAmount,
        address _targetAddress
    ) external payable nonReentrant onlyRegisteredAndAllowed {
        require(availableCreateBattle, "Cannot create battle");
        require(_targetAddress != msg.sender, "Cannot target yourself");
        require(allowedBetTokens[_betTokenAddress], "Token not allowed");

        _receiveBet(_betTokenAddress, _betAmount, msg.sender);
        _chargeFee(msg.sender);

        uint256 battleId = ++_battleCount;
        BattleInfo storage b = _battles[battleId];
        b.selfAddress = msg.sender;
        b.targetAddress = _targetAddress;
        b.betTokenAddress = _betTokenAddress;
        b.betAmount = _betAmount;
        b.createdAt = block.timestamp;

        emit BattleCreated(battleId, msg.sender, _targetAddress, _betTokenAddress, _betAmount);
    }

    /**
     * @notice Join an existing battle.
     */
    function joinExistBattle(uint256 _battleId)
        external
        payable
        nonReentrant
        onlyRegisteredAndAllowed
    {
        BattleInfo storage b = _battles[_battleId];
        require(b.selfAddress != address(0), "Battle does not exist");
        require(!b.isStarted, "Battle already has an opponent");
        require(!b.isEnded, "Battle already ended");
        require(b.selfAddress != msg.sender, "Cannot join own battle");
        require(
            b.targetAddress == address(0) || b.targetAddress == msg.sender,
            "Not invited to this battle"
        );

        _receiveBet(b.betTokenAddress, b.betAmount, msg.sender);
        _chargeFee(msg.sender);

        b.isStarted = true;
        b.targetAddress = msg.sender;

        emit BattleJoined(_battleId, msg.sender);
    }

    /**
     * @notice Settle a battle and pay out the reward to the winner.
     */
    function settleBattle(uint256 _battleId, address _winner)
        external
        nonReentrant
        onlyRole(LIQUIDATOR_ROLE)
    {
        BattleInfo storage b = _battles[_battleId];
        require(b.selfAddress != address(0), "Battle does not exist");
        require(!b.isEnded, "Battle already ended");
        require(b.isStarted, "Opponent has not joined");
        require(_winner == b.selfAddress || _winner == b.targetAddress, "Invalid winner address");

        b.winner = _winner;
        b.isEnded = true;

        uint256 totalReward = b.betAmount * 2;

        // Release the locked bets from the rescue accumulator. We subtract the
        // FULL gross amount (2 × betAmount) before fee/winner splitting because
        // any portion routed into accruedProtocolFees is tracked separately.
        outstandingBets[b.betTokenAddress] -= totalReward;

        // Charge protocol fee. Kill-switch: protocolFeeBps == 0.
        // - protocolFeeRecipient != 0 → try push to recipient.
        //   If the push reverts (bad recipient: non-payable contract, blacklisted, etc.)
        //   the fee falls back to accrual instead of failing the whole settlement.
        // - protocolFeeRecipient == 0 → accrue for later withdrawal via
        //   withdrawProtocolFees().
        uint256 feeBps = protocolFeeBps;
        if (feeBps > 0) {
            uint256 feeAmount = (totalReward * feeBps) / BPS_DENOMINATOR;
            if (feeAmount > 0) {
                totalReward -= feeAmount;
                address feeRecipient = protocolFeeRecipient;
                if (feeRecipient != address(0)) {
                    bool pushed = _tryPayout(b.betTokenAddress, feeRecipient, feeAmount);
                    if (!pushed) {
                        // Recipient unreachable — fall back to accrual instead of
                        // DoS'ing the entire settlement (M-2 fix).
                        accruedProtocolFees[b.betTokenAddress] += feeAmount;
                        feeRecipient = address(0); // event reflects what actually happened
                    }
                } else {
                    accruedProtocolFees[b.betTokenAddress] += feeAmount;
                }
                emit ProtocolFeeCharged(_battleId, b.betTokenAddress, feeRecipient, feeAmount);
            }
        }

        _payout(b.betTokenAddress, _winner, totalReward);

        // Optional bonus token reward.
        // M-1 fix: a bonus failure (empty pool, blacklist, weird token) MUST NOT
        // block the main settlement. Try the transfer; if it fails, just emit
        // BonusPayout(success=false) so off-chain knows it was skipped.
        address bonusToken = tokenAddresses[1];
        uint256 bonusAmount = tokenAmounts[1];
        if (bonusAmount > 0 && bonusToken != address(0)) {
            bool sent = _tryPayout(bonusToken, _winner, bonusAmount);
            emit BonusPayout(_battleId, _winner, bonusToken, bonusAmount, sent);
        }

        // totalReward in this event is the NET amount transferred to the winner
        // (gross reward minus protocol fee), which is what most consumers care about.
        emit BattleEnded(_battleId, _winner, totalReward);
    }

    /**
     * @notice Close a battle that has not yet been joined and refund the creator's bet.
     *         Use case: clean up battles that have been open too long or were created by mistake.
     */
    function closeBattle(uint256 _battleId) external nonReentrant onlyRole(LIQUIDATOR_ROLE) {
        BattleInfo storage b = _battles[_battleId];
        require(b.selfAddress != address(0), "Battle does not exist");
        require(!b.isEnded, "Battle already ended");
        require(!b.isStarted, "Battle already has an opponent");

        b.isEnded = true;

        uint256 refundAmount = b.betAmount;
        // Only the creator's bet was ever received — opponent never joined.
        outstandingBets[b.betTokenAddress] -= refundAmount;
        _payout(b.betTokenAddress, b.selfAddress, refundAmount);

        emit BattleClosed(_battleId, msg.sender, refundAmount);
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

    function updateAllowedBetToken(address _token, bool _allowed) external onlyOwner {
        allowedBetTokens[_token] = _allowed;
        emit AllowedBetTokenUpdated(msg.sender, _token, _allowed);
    }

    function updateAvailableCreateBattle(bool _isAvailable) external onlyOwner {
        availableCreateBattle = _isAvailable;
        emit AvailableCreateBattleUpdated(msg.sender, _isAvailable);
    }

    function updateForbiddenToPlay(address _user, bool _isForbidden) external onlyOwner {
        forbiddenToPlay[_user] = _isForbidden;
        emit ForbiddenToPlayUpdated(msg.sender, _user, _isForbidden);
    }

    /**
     * @param _amount0 Minimum ETH bet amount
     * @param _amount1 Minimum ERC20 bet amount
     */
    function updateMinimumBetTokenAmount(uint256 _amount0, uint256 _amount1) external onlyOwner {
        minBetAmount[0] = _amount0;
        minBetAmount[1] = _amount1;
        emit MinimumBetTokenAmountUpdated(msg.sender, _amount0, _amount1);
    }

    function updateFeeAndBonusTokenAddressWithAmount(
        address _feeToken,
        uint256 _feeTokenAmount,
        address _bonusToken,
        uint256 _bonusTokenAmount
    ) external onlyOwner {
        tokenAddresses[0] = _feeToken;
        tokenAddresses[1] = _bonusToken;
        tokenAmounts[0] = _feeTokenAmount;
        tokenAmounts[1] = _bonusTokenAmount;
        emit FeeTokenAndBonusTokenUpdated(
            msg.sender,
            _feeToken,
            _feeTokenAmount,
            _bonusToken,
            _bonusTokenAmount
        );
    }

    /**
     * @notice Set the protocol fee in basis points. 0 disables fee charging.
     * @param _bps New fee value (1 = 0.01 %, 100 = 1 %, max MAX_PROTOCOL_FEE_BPS = 10 %).
     * @dev    No fee is taken if protocolFeeRecipient is address(0), even if _bps > 0.
     */
    function setProtocolFee(uint256 _bps) external onlyOwner {
        require(_bps <= MAX_PROTOCOL_FEE_BPS, "Fee exceeds cap");
        uint256 old = protocolFeeBps;
        protocolFeeBps = _bps;
        emit ProtocolFeeUpdated(msg.sender, old, _bps);
    }

    /**
     * @notice Set the recipient of the protocol fee.
     * @param _recipient If non-zero, future fees are pushed to this address at
     *                   settle time. If zero, future fees accrue and must be
     *                   withdrawn via withdrawProtocolFees().
     * @dev   Does NOT affect already-accrued fees in accruedProtocolFees[].
     *        Those must still be withdrawn explicitly.
     */
    function setProtocolFeeRecipient(address _recipient) external onlyOwner {
        address old = protocolFeeRecipient;
        protocolFeeRecipient = _recipient;
        emit ProtocolFeeRecipientUpdated(msg.sender, old, _recipient);
    }

    /**
     * @notice Withdraw accrued protocol fees for a specific token.
     * @param _token  Token to withdraw (address(0) = native ETH).
     * @param _to     Recipient address.
     * @param _amount Amount to withdraw. Must be ≤ accruedProtocolFees[_token].
     *
     * @dev Bounded by the accumulator — battle bets can never be drained by this
     *      function, even if the contract holds a larger raw balance.
     *      For ETH, the contract must hold at least _amount in balance (it always
     *      should, since accrual increments the accumulator at the same time
     *      ETH stays in the contract).
     */
    function withdrawProtocolFees(address _token, address _to, uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Amount must be > 0");
        uint256 accrued = accruedProtocolFees[_token];
        require(_amount <= accrued, "Amount exceeds accrued fees");

        accruedProtocolFees[_token] = accrued - _amount;
        _payout(_token, _to, _amount);

        emit ProtocolFeeWithdrawn(msg.sender, _token, _to, _amount);
    }

    function depositToken(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        emit TokenDeposited(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @notice Rescue tokens that are NOT part of the protocol's locked accounting.
     *         Use cases: unused bonus tokens previously deposited via depositToken,
     *         or tokens accidentally transferred to this contract.
     * @param _token  Token address (address(0) = native ETH).
     * @param _to     Destination address.
     * @param _amount Amount to rescue.
     *
     * @dev Bounded by  balance − outstandingBets[token] − accruedProtocolFees[token].
     *      Therefore this function CAN NEVER drain:
     *        • bets locked in unsettled battles, nor
     *        • accrued protocol fees (use withdrawProtocolFees() for those).
     *      The function reverts if the rescue would exceed the available headroom.
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

        uint256 reserved = outstandingBets[_token] + accruedProtocolFees[_token];
        require(totalBalance >= reserved, "Accounting underflow");
        uint256 available = totalBalance - reserved;
        require(_amount <= available, "Amount exceeds rescuable balance");

        _payout(_token, _to, _amount);
        emit ExtraTokensRescued(msg.sender, _token, _to, _amount);
    }

    // =====================================================================
    //                          Internals
    // =====================================================================

    function _receiveBet(address token, uint256 amount, address from) internal {
        if (token == address(0)) {
            require(amount >= minBetAmount[0], "Bet amount below minimum");
            require(msg.value == amount, "Incorrect ETH amount sent");
        } else {
            require(msg.value == 0, "ETH not accepted for ERC20 bet");
            require(amount >= minBetAmount[1], "Bet amount below minimum");
            // M-3 fix: detect fee-on-transfer / rebasing tokens via balance delta.
            // If the token siphons part of the transfer (USDT-fee, PAXG, stETH, etc.)
            // the contract would receive less than `amount` while outstandingBets
            // would be credited the full `amount`, breaking the accumulator invariant
            // and causing later settlements to revert with insufficient balance.
            // Rejecting at receive-time keeps state clean — the failed tx is fully
            // rolled back, so the player loses nothing.
            uint256 balBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(from, address(this), amount);
            uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;
            require(received == amount, "Token not supported (fee-on-transfer)");
        }
        outstandingBets[token] += amount;
    }

    function _chargeFee(address from) internal {
        uint256 feeAmount = tokenAmounts[0];
        if (feeAmount == 0) return;
        address feeToken = tokenAddresses[0];
        require(feeToken != address(0), "FeeToken not configured");
        IERC20(feeToken).safeTransferFrom(from, address(this), feeAmount);
    }

    function _payout(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /**
     * @dev Non-reverting variant of _payout. Returns true on success, false on failure
     *      (instead of reverting). Used in settleBattle to make optional payouts
     *      (bonus, push-mode protocol fee) survive recipient misconfiguration so the
     *      mandatory winner payout still goes through.
     *
     *      Uses a low-level call for ERC20 to handle both standard tokens (return bool)
     *      and non-standard ones (like USDT that return nothing).
     */
    function _tryPayout(address token, address to, uint256 amount) internal returns (bool ok) {
        if (token == address(0)) {
            (ok, ) = to.call{value: amount}("");
        } else {
            bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
            (bool success, bytes memory ret) = token.call(data);
            if (!success) return false;
            ok = (ret.length == 0) || abi.decode(ret, (bool));
        }
    }
}
