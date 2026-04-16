// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./HeroArenaAvatars.sol";

contract HeroArenaMiningFactoryV1 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public HapToken;
    HeroArenaAvatars public HeroArenaAvatarsSC;

    bool public availableClaim;

    // Price of HAP that a user needs to pay to for a NFT
    uint256 public nftPrice;

    // number of initial series (i.e. different visuals)
    uint8 private numberOfAvatars;

    // Pending owner for two-step NFT contract ownership transfer
    address public pendingNFTContractOwner;

    event AvatarMinted(address indexed user, uint256 indexed tokenId, uint8 indexed avatarId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event AvatarPriceUpdated(uint256 newPrice);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(IERC20 _HapToken, uint256 _price) Ownable(msg.sender) {
        HapToken = _HapToken;
        nftPrice = _price;
        HeroArenaAvatarsSC = new HeroArenaAvatars();

        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(0, "Knight_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(1, "Knight_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(2, "Knight_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(3, "Knight_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(4, "Knight_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(5, "Wizard_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(6, "Wizard_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(7, "Wizard_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(8, "Wizard_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(9, "Archer_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(10, "Archer_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(11, "Archer_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(12, "Archer_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(13, "Cleric_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(14, "Cleric_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(15, "Cleric_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(16, "Cleric_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(17, "Ninja_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(18, "Ninja_v2");

        // Other parameters initialized
        numberOfAvatars = 19;
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
     * Mint NFTs from the HeroArenaAvatars contract.
     */
    function mintNFT(uint8 _avatarId) external {
        require(availableClaim, "Cannot claim");
        require(_avatarId < numberOfAvatars, "Input avatarId unavailable");

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), nftPrice);

        uint256 _tokenId = HeroArenaAvatarsSC.mint(msg.sender, _avatarId);

        // emit event
        emit AvatarMinted(msg.sender, _tokenId, _avatarId);
    }

    /**
     * Update NFT's price.
     */
    function updateNFTPrice(uint256 _newPrice) external onlyOwner {
        nftPrice = _newPrice;

        // emit event
        emit AvatarPriceUpdated(_newPrice);
    }

    /**
     * Step 1: Propose a new owner for the NFT contract, only the owner can call it.
     * The proposed owner must call acceptNFTContractOwnership() to complete the transfer.
     * Call with address(0) to cancel a pending proposal.
     */
    function proposeNFTContractOwnership(address _newOwner) external onlyOwner {
        pendingNFTContractOwner = _newOwner;
        emit NFTContractOwnershipProposed(HeroArenaAvatarsSC.owner(), _newOwner);
    }

    /**
     * Step 2: Accept the ownership of the NFT contract, only the pending owner can call it.
     */
    function acceptNFTContractOwnership() external {
        require(msg.sender == pendingNFTContractOwner, "Not the pending owner");
        address _previousOwner = HeroArenaAvatarsSC.owner();
        pendingNFTContractOwner = address(0);
        HeroArenaAvatarsSC.transferOwnership(msg.sender);
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