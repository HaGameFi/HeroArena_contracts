// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title HeroArenaSwap
 * @notice Users can swap ETH for HAP tokens at a rate set by the owner.
 *         Owner deposits HAP into this contract and can withdraw ETH / HAP at any time.
 */
contract HeroArenaSwap is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable HapToken;

    // How many HAP (in wei) per 1 ETH (in wei)
    // e.g. rate = 5000 * 1e18 means 1 ETH → 5000 HAP
    uint256 public rate;

    // Whether swapping is currently enabled
    bool public swapEnabled;

    event RateUpdated(uint256 oldRate, uint256 newRate);
    event SwapEnabledUpdated(bool enabled);
    event Swapped(address indexed user, uint256 ethIn, uint256 hapOut);
    event HapDeposited(address indexed from, uint256 amount);
    event HapWithdrawn(address indexed to, uint256 amount);
    event NativeTokenWithdrawn(address indexed to, uint256 amount);

    constructor(address _HapToken, uint256 _rate) Ownable(msg.sender) {
        require(_HapToken != address(0), "Invalid HAP token address");
        require(_rate > 0, "Rate must be > 0");
        HapToken = IERC20(_HapToken);
        rate = _rate;
        swapEnabled = true;
    }

    // ─────────────────────────────────────────────
    //  Owner functions
    // ─────────────────────────────────────────────

    /**
     * @notice Set a new ETH → HAP exchange rate.
     * @param _rate Amount of HAP (in wei) received per 1 ETH (in wei).
     */
    function setRate(uint256 _rate) external onlyOwner {
        require(_rate > 0, "Rate must be > 0");
        emit RateUpdated(rate, _rate);
        rate = _rate;
    }

    /**
     * @notice Enable or disable swapping.
     */
    function setSwapEnabled(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
        emit SwapEnabledUpdated(_enabled);
    }

    /**
     * @notice Deposit HAP into this contract so users can swap.
     *         Owner must approve this contract first.
     */
    function depositHap(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        HapToken.safeTransferFrom(msg.sender, address(this), amount);
        emit HapDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw HAP from this contract back to owner.
     */
    function withdrawHap(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(HapToken.balanceOf(address(this)) >= amount, "Insufficient HAP balance");
        HapToken.safeTransfer(msg.sender, amount);
        emit HapWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Withdraw Native Token collected from swaps.
     */
    function withdrawNativeToken(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient ETH balance");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Native token transfer failed");
        emit NativeTokenWithdrawn(msg.sender, amount);
    }

    // ─────────────────────────────────────────────
    //  User swap
    // ─────────────────────────────────────────────

    /**
     * @notice Swap Native token for HAP. Send Native token with this call.
     */
    function swap() external payable {
        require(swapEnabled, "Swap is disabled");
        require(msg.value > 0, "Must send Native token");

        uint256 hapOut = (msg.value * rate) / 1 ether;
        require(hapOut > 0, "HAP amount too small");
        require(HapToken.balanceOf(address(this)) >= hapOut, "Insufficient HAP in contract");

        HapToken.safeTransfer(msg.sender, hapOut);
        emit Swapped(msg.sender, msg.value, hapOut);
    }

    /**
     * @notice Preview how much HAP you would receive for a given native token amount.
     */
    function previewSwap(uint256 nativeTokenAmount) external view returns (uint256 hapOut) {
        hapOut = (nativeTokenAmount * rate) / 1 ether;
    }

    // Allow contract to receive plain native token transfers (e.g. owner topping up native token balance)
    receive() external payable {}
}
