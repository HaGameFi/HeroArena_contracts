// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {HeroArenaProfileInterface} from "./interfaces/HeroArenaProfileInterface.sol";

import "./HeroArenaWorldCupInitializable.sol";

/**
 * @title HeroArenaWorldCupDeployer
 */
contract HeroArenaWorldCupDeployer is Ownable {
    using SafeERC20 for IERC20;

    // ---------- External deps ----------
    /// @dev HapToken is set once in the constructor and never mutated;
    IERC20 public immutable HapToken;
    HeroArenaProfileInterface public immutable HeroArenaProfileSC;

    // Fee of HAP that a user needs to pay to for registration
    uint256 public registrationFee;

    // display current WorldCup smart contract address
    address public currentWCAddress;

    // Monotonically increasing salt nonce so repeat deployments with the same
    // (admin, bonusToken, amount) triple cannot collide / brick createWC.
    uint256 public deployNonce;

    event AdminTokenRecovery(address indexed tokenRecovered, uint256 amount);
    event NewWCContract(address indexed idoAddress);

    constructor(IERC20 _HapToken, uint256 _registrationFee, HeroArenaProfileInterface _HeroArenaProfileSC) Ownable(msg.sender) {
        require(address(_HapToken) != address(0), "HapToken cannot be zero");
        require(address(_HeroArenaProfileSC) != address(0), "Profile SC cannot be zero");
        HapToken = _HapToken;
        registrationFee = _registrationFee;
        HeroArenaProfileSC = _HeroArenaProfileSC;
    }

    function createWC(address _adminAddress, address _bonusToken, uint256 _bonusAmount)
        external
        onlyOwner
    {
        require(_adminAddress != address(0), "admin cannot be zero");

        // a non-zero bonus token must actually be a contract (real ERC20),
        // not an arbitrary EOA. address(0) is the valid native-ETH bonus sentinel.
        if (_bonusToken != address(0)) {
            require(_bonusToken.code.length > 0, "Bonus token must be a contract");
        }

        bytes memory bytecode = type(HeroArenaWorldCupInitializable).creationCode;
        // include deployNonce so the same params can be deployed more than
        // once and a salt collision can never silently return address(0).
        bytes32 salt =
            keccak256(abi.encodePacked(_adminAddress, _bonusToken, _bonusAmount, deployNonce));
        unchecked { ++deployNonce; }

        address wcAddress;
        assembly {
            wcAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // create2 returns 0 on failure (e.g. salt collision); fail loudly
        // instead of calling initialize() on the zero address.
        require(wcAddress != address(0), "CREATE2 deployment failed");

        HeroArenaWorldCupInitializable(payable(wcAddress)).initialize(_adminAddress, address(HapToken), registrationFee, address(HeroArenaProfileSC), _bonusToken, _bonusAmount);

        if (currentWCAddress != wcAddress) {
            currentWCAddress = wcAddress;
        }

        emit NewWCContract(wcAddress);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress) external onlyOwner {
        uint256 balanceToRecover = IERC20(_tokenAddress).balanceOf(address(this));
        require(balanceToRecover > 0, "Operations: Balance must be > 0");
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), balanceToRecover);

        emit AdminTokenRecovery(_tokenAddress, balanceToRecover);
    }
}