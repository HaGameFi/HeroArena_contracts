// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./HeroArenaProfile.sol";

contract HeroArenaBattle is AccessControl, Ownable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    HeroArenaProfile public HeroArenaProfileSC;

    bool public availableCreateBattle;

    // Mapping which address has been forbidden to play
    mapping(address => bool) public forbiddenToPlay;

    // [0]=feeToken, [1]=bonusToken
    address[2] public tokenAddresses;

    // [0]=feeTokenAmount, [1]=bonusTokenAmount
    uint256[2] public tokenAmounts;

    // Minimum bet amount: [0]=ETH (native), [1]=ERC20
    uint256[2] public minBetAmount;

    // Whitelist of tokens allowed as betToken (including address(0) for native ETH)
    mapping(address => bool) public allowedBetTokens;

    // Struct that contains pvp game's information
    struct BattleInfo {
        address selfAddress;     // battle creator
        address targetAddress;   // invited opponent (address(0) = open to anyone); set to actual joiner after join
        address betTokenAddress; // address(0) = native ETH bet; any other address = ERC20 bet token
        uint256 betAmount;       // amount each side bets
        uint256 createdAt;       // creation timestamp
        address winner;          // set after settlement
        bool isStarted;          // true once an opponent has joined
        bool isEnded;            // true after settlement
    }

    // Mapping battleId => BattleInfo
    mapping(uint256 => BattleInfo) private _battles;

    // Used for generating sequential battleIds
    uint256 private _battleCounter;

    event AvailableCreateBattleUpdated(address indexed owner, bool isAvail);
    event ForbiddenToPlayUpdated(address indexed owner, address indexed userAddress, bool isForbidden);
    event MinimumBetTokenAmountUpdated(address indexed owner, uint256 amount0, uint256 amount1);
    event FeeTokenAndBounsTokenUpdated(
        address indexed owner,
        address feeToken, uint256 feeTokenAmount,
        address bounsToken, uint256 bounsTokenAmount
    );
    event BattleCreated(
        uint256 indexed battleId,
        address indexed creator,
        address targetAddress,
        address betTokenAddress,
        uint256 betAmount
    );
    event BattleJoined(uint256 indexed battleId, address indexed joiner);
    event BattleEnded(uint256 indexed battleId, address indexed winner, uint256 totalReward);
    event AllowedBetTokenUpdated(address indexed owner, address indexed token, bool allowed);
    event TokenDeposited(address indexed depositor, address indexed tokenAddress, uint256 amount);
    event TokensClaimed(address indexed to);

    modifier onlyLiquidator() {
        require(hasRole(LIQUIDATOR_ROLE, msg.sender), "Not an liquidator role");
        _;
    }

    modifier whoCanPlay() {
        require(HeroArenaProfileSC.hasRegistered(msg.sender), "Profile not registered");
        require(!forbiddenToPlay[msg.sender], "Forbidden to play");
        _;
    }

    constructor(HeroArenaProfile _HeroArenaProfileSC) Ownable(msg.sender) {
        HeroArenaProfileSC = _HeroArenaProfileSC;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Admin configuration
    // ═══════════════════════════════════════════════════════════════════════════

    function updateAvailableCreateBattle(bool _isAvailable) external onlyOwner {
        availableCreateBattle = _isAvailable;
        emit AvailableCreateBattleUpdated(msg.sender, _isAvailable);
    }

    function updateForbiddenToPlay(address _user, bool _isForbidden) external onlyOwner {
        forbiddenToPlay[_user] = _isForbidden;
        emit ForbiddenToPlayUpdated(msg.sender, _user, _isForbidden);
    }

    function updateFeeAndBounsTokenAddressWithAmount(
        address _feeToken,   uint256 _feeTokenAmount,
        address _bounsToken, uint256 _bounsTokenAmount
    ) external onlyOwner {
        tokenAddresses[0] = _feeToken;
        tokenAddresses[1] = _bounsToken;
        tokenAmounts[0]   = _feeTokenAmount;
        tokenAmounts[1]   = _bounsTokenAmount;

        emit FeeTokenAndBounsTokenUpdated(
            msg.sender,
            _feeToken, _feeTokenAmount,
            _bounsToken, _bounsTokenAmount
        );
    }

    function updateAllowedBetToken(address _token, bool _allowed) external onlyOwner {
        allowedBetTokens[_token] = _allowed;
        emit AllowedBetTokenUpdated(msg.sender, _token, _allowed);
    }

    function updateMinimunBetTokenAmount(uint256 _amount0, uint256 _amount1) external onlyOwner {
        minBetAmount[0] = _amount0;
        minBetAmount[1] = _amount1;
        emit MinimumBetTokenAmountUpdated(msg.sender, _amount0, _amount1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Battle actions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Create a new battle.
     * @param _betTokenAddress address(0) = bet with native ETH; any other address = bet with that ERC20
     * @param _betAmount       amount each participant puts up
     * @param _targetAddress   specific opponent address, or address(0) for an open battle
     */
    function createBattle(
        address _betTokenAddress,
        uint256 _betAmount,
        address _targetAddress
    ) external payable whoCanPlay nonReentrant {
        require(availableCreateBattle, "Cannot create battle");
        require(_targetAddress != msg.sender, "Cannot target yourself");

        _collectBet(_betTokenAddress, _betAmount, msg.sender);
        _collectFee(msg.sender);

        uint256 battleId = ++_battleCounter;
        _battles[battleId] = BattleInfo({
            selfAddress:     msg.sender,
            targetAddress:   _targetAddress,
            betTokenAddress: _betTokenAddress,
            betAmount:       _betAmount,
            createdAt:       block.timestamp,
            winner:          address(0),
            isStarted:       false,
            isEnded:         false
        });

        emit BattleCreated(battleId, msg.sender, _targetAddress, _betTokenAddress, _betAmount);
    }

    /**
     * Join an existing open battle (targetAddress == 0) or one that specifically
     * targets the caller.
     */
    function joinExistBattle(uint256 _battleId) external payable whoCanPlay nonReentrant {
        BattleInfo storage battle = _battles[_battleId];
        require(battle.selfAddress != address(0), "Battle does not exist");
        require(!battle.isStarted, "Battle already has an opponent");
        require(!battle.isEnded, "Battle already ended");
        require(battle.selfAddress != msg.sender, "Cannot join own battle");
        require(
            battle.targetAddress == address(0) || battle.targetAddress == msg.sender,
            "Not invited to this battle"
        );

        _collectBet(battle.betTokenAddress, battle.betAmount, msg.sender);
        _collectFee(msg.sender);

        battle.isStarted     = true;
        battle.targetAddress = msg.sender;

        emit BattleJoined(_battleId, msg.sender);
    }

    /**
     * Settle a battle and send rewards to the winner.
     * @param _battleId battle to settle
     * @param _winner   must be one of the two participants
     */
    function settleBattle(uint256 _battleId, address _winner) external onlyLiquidator {
        BattleInfo storage battle = _battles[_battleId];
        require(battle.selfAddress != address(0), "Battle does not exist");
        require(!battle.isEnded, "Battle already ended");
        require(battle.isStarted, "Opponent has not joined");
        require(
            _winner == battle.selfAddress || _winner == battle.targetAddress,
            "Invalid winner address"
        );

        battle.isEnded = true;
        battle.winner  = _winner;

        uint256 totalBet = battle.betAmount * 2;

        if (battle.betTokenAddress == address(0)) {
            (bool ok,) = _winner.call{value: totalBet}("");
            require(ok, "ETH transfer failed");
        } else {
            IERC20(battle.betTokenAddress).safeTransfer(_winner, totalBet);
        }

        if (tokenAmounts[1] > 0 && tokenAddresses[1] != address(0)) {
            IERC20(tokenAddresses[1]).safeTransfer(_winner, tokenAmounts[1]);
        }

        emit BattleEnded(_battleId, _winner, totalBet);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Token management
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Deposit ERC20 tokens into the contract (e.g. to fund bonus/fee reserves).
     */
    function depositToken(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        emit TokenDeposited(msg.sender, _tokenAddress, _amount);
    }

    /**
     * Withdraw all ETH and specified ERC20 tokens to `_to`.
     * @param _to          destination address
     * @param _erc20Tokens list of ERC20 token addresses to sweep
     */
    function claimTokens(address _to, address[] calldata _erc20Tokens) external onlyOwner {
        require(_to != address(0), "Invalid destination");

        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) {
            (bool ok,) = _to.call{value: nativeBal}("");
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

    // ═══════════════════════════════════════════════════════════════════════════
    // View helpers
    // ═══════════════════════════════════════════════════════════════════════════

    function getBattleInfo(uint256 _battleId) external view returns (BattleInfo memory) {
        return _battles[_battleId];
    }

    function getBattleCount() external view returns (uint256) {
        return _battleCounter;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Internal helpers
    // ═══════════════════════════════════════════════════════════════════════════

    function _collectBet(address _betTokenAddress, uint256 _betAmount, address _from) internal {
        require(allowedBetTokens[_betTokenAddress], "BetToken not allowed");
        if (_betTokenAddress == address(0)) {
            require(_betAmount >= minBetAmount[0], "Bet amount below minimum");
            require(msg.value == _betAmount, "Incorrect ETH amount sent");
        } else {
            require(msg.value == 0, "ETH not accepted for ERC20 bet");
            require(_betAmount >= minBetAmount[1], "Bet amount below minimum");
            IERC20(_betTokenAddress).safeTransferFrom(_from, address(this), _betAmount);
        }
    }

    function _collectFee(address _from) internal {
        if (tokenAmounts[0] > 0) {
            require(tokenAddresses[0] != address(0), "FeeToken not configured");
            IERC20(tokenAddresses[0]).safeTransferFrom(_from, address(this), tokenAmounts[0]);
        }
    }

    receive() external payable {}
}
