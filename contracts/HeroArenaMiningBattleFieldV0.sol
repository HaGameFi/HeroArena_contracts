// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./HeroArenaBattleFields.sol";

contract HeroArenaMiningBattleFieldV0 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public HapToken;
    HeroArenaBattleFields public HeroArenaBattleFieldsSC;

    bool public availableClaim;

    // Price of HAP that a user needs to pay to for a NFT
    uint256 public nftPrice;

    // number of initial series (i.e. different visuals)
    uint8 private numberOfBattleFields;

    // Pending owner for two-step NFT contract ownership transfer
    address public pendingNFTContractOwner;

    event BattleFieldMinted(address indexed user, uint256 indexed tokenId, uint8 indexed battleFieldId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event BattleFieldPriceUpdated(uint256 newPrice);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(IERC20 _HapToken, uint256 _price) Ownable(msg.sender) {
        HapToken = _HapToken;
        nftPrice = _price;
        HeroArenaBattleFieldsSC = new HeroArenaBattleFields();

        HeroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(0, "Blank");
        HeroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(1, "Default");

        // Other parameters initialized
        numberOfBattleFields = 2;
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
     * Mint NFTs from the HeroArenaBattleFields contract.
     */
    function mintNFT(uint8 _battleFieldId) external {
        require(availableClaim, "Cannot claim");
        require(_battleFieldId < numberOfBattleFields, "Input battleFieldId unavailable");

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), nftPrice);

        uint256 _tokenId = HeroArenaBattleFieldsSC.mint(msg.sender, _battleFieldId);

        // emit event
        emit BattleFieldMinted(msg.sender, _tokenId, _battleFieldId);
    }

    /**
     * Update NFT's price.
     */
    function updateNFTPrice(uint256 _newPrice) external onlyOwner {
        nftPrice = _newPrice;

        // emit event
        emit BattleFieldPriceUpdated(_newPrice);
    }

    /**
     * Step 1: Propose a new owner for the NFT contract, only the owner can call it.
     * The proposed owner must call acceptNFTContractOwnership() to complete the transfer.
     * Call with address(0) to cancel a pending proposal.
     */
    function proposeNFTContractOwnership(address _newOwner) external onlyOwner {
        pendingNFTContractOwner = _newOwner;
        emit NFTContractOwnershipProposed(HeroArenaBattleFieldsSC.owner(), _newOwner);
    }

    /**
     * Step 2: Accept the ownership of the NFT contract, only the pending owner can call it.
     */
    function acceptNFTContractOwnership() external {
        require(msg.sender == pendingNFTContractOwner, "Not the pending owner");
        address _previousOwner = HeroArenaBattleFieldsSC.owner();
        pendingNFTContractOwner = address(0);
        HeroArenaBattleFieldsSC.transferOwnership(msg.sender);
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