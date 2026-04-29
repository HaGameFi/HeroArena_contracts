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
    event TokensClaimed(address indexed to);

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
        _payout(b.betTokenAddress, _winner, totalReward);

        // Optional bonus token reward
        address bonusToken = tokenAddresses[1];
        uint256 bonusAmount = tokenAmounts[1];
        if (bonusAmount > 0 && bonusToken != address(0)) {
            IERC20(bonusToken).safeTransfer(_winner, bonusAmount);
        }

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

    function depositToken(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        emit TokenDeposited(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @notice Withdraw all ETH and specified ERC20 token balances from the contract.
     * @dev    Warning: this sweeps the entire balance, including funds locked in unsettled battles.
     *         In production, consider restricting withdrawals to unlocked funds only.
     */
    function claimTokens(address _to, address[] calldata _erc20Tokens)
        external
        onlyOwner
        nonReentrant
    {
        require(_to != address(0), "Invalid address");

        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool ok, ) = _to.call{value: ethBal}("");
            require(ok, "ETH transfer failed");
        }

        for (uint256 i = 0; i < _erc20Tokens.length; i++) {
            address token = _erc20Tokens[i];
            if (token == address(0)) continue;
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal > 0) {
                IERC20(token).safeTransfer(_to, bal);
            }
        }

        emit TokensClaimed(_to);
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
            IERC20(token).safeTransferFrom(from, address(this), amount);
        }
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
}
