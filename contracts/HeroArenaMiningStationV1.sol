// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./HeroArenaFrames.sol";

contract HeroArenaMiningStationV1 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public HapToken;
    HeroArenaFrames public HeroArenaFramesSC;

    bool public availableClaim;

    // Price of HAP that a user needs to pay to for a NFT
    uint256 public nftPrice;

    // number of initial series (i.e. different visuals)
    uint8 private numberOfFrames;

    // Pending owner for two-step NFT contract ownership transfer
    address public pendingNFTContractOwner;

    event FrameMinted(address indexed user, uint256 indexed tokenId, uint8 indexed frameId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event FramePriceUpdated(uint256 newPrice);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(IERC20 _HapToken, uint256 _price) Ownable(msg.sender) {
        HapToken = _HapToken;
        nftPrice = _price;
        HeroArenaFramesSC = new HeroArenaFrames();

        HeroArenaFramesSC.setFrameNameAndCreatedTimestamp(1, "Sapphire_v0");
        HeroArenaFramesSC.setFrameNameAndCreatedTimestamp(2, "Lunar_v0");

        // Other parameters initialized
        numberOfFrames = 2;
    }

    /**
     * Update the availableClaim to allow user mint NFT.
     */
    function updateAvailableClaim(bool _isAvailable) external onlyOwner {
        availableClaim = _isAvailable;

        // emit event
        emit AvailableClaimUpdated(msg.sender, _isAvailable);
    }

    /**
     * Mint NFTs from the HeroArenaFrames contract.
     */
    function mintNFT(uint8 _frameId) external {
        require(availableClaim, "Cannot claim");
        require(_frameId < numberOfFrames, "Input frameId unavailable");

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), nftPrice);

        uint256 _tokenId = HeroArenaFramesSC.mint(msg.sender, _frameId);

        // emit event
        emit FrameMinted(msg.sender, _tokenId, _frameId);
    }

    /**
     * Update NFT's price.
     */
    function updateNFTPrice(uint256 _newPrice) external onlyOwner {
        nftPrice = _newPrice;

        // emit event
        emit FramePriceUpdated(_newPrice);
    }

    /**
     * Step 1: Propose a new owner for the NFT contract, only the owner can call it.
     * The proposed owner must call acceptNFTContractOwnership() to complete the transfer.
     * Call with address(0) to cancel a pending proposal.
     */
    function proposeNFTContractOwnership(address _newOwner) external onlyOwner {
        pendingNFTContractOwner = _newOwner;
        emit NFTContractOwnershipProposed(HeroArenaFramesSC.owner(), _newOwner);
    }

    /**
     * Step 2: Accept the ownership of the NFT contract, only the pending owner can call it.
     */
    function acceptNFTContractOwnership() external {
        require(msg.sender == pendingNFTContractOwner, "Not the pending owner");
        address _previousOwner = HeroArenaFramesSC.owner();
        pendingNFTContractOwner = address(0);
        HeroArenaFramesSC.transferOwnership(msg.sender);
        emit NFTContractOwnershipTransferred(_previousOwner, msg.sender);
    }

    /**
     * Transfer the HAP tokens back to the owner.
     */
    function claimFee(uint256 _amount) external onlyOwner {
        // Transfer HAP tokens to owner
        HapToken.safeTransfer(msg.sender, _amount);
    }
}   