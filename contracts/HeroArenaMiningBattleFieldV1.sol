// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./HeroArenaBattleFields.sol";

contract HeroArenaMiningBattleFieldV1 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public HapToken;
    HeroArenaBattleFields public immutable heroArenaBattleFieldsSC;

    bool public availableClaim;
    bool public battleFieldsInitialized;

    // Price of HAP that a user needs to pay to for a NFT
    uint256 public nftPrice;

    uint8 private constant MIN_BATTLEFIELD_ID = 2;
    uint8 private constant MAX_BATTLEFIELD_ID_EXCLUSIVE = 10;

    // Pending owner for two-step NFT contract ownership transfer
    address public pendingNFTContractOwner;

    event BattleFieldMinted(address indexed user, uint256 indexed tokenId, uint8 indexed battleFieldId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event BattleFieldPriceUpdated(uint256 newPrice);
    event BattleFieldsInitialized(address indexed battleFieldsContract);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(IERC20 _HapToken, HeroArenaBattleFields _battleFieldsSC, uint256 _price) Ownable(msg.sender) {
        require(address(_HapToken) != address(0), "HapToken cannot be zero");
        require(address(_HapToken).code.length > 0, "HapToken must be a contract");
        HapToken = _HapToken;
        require(address(_battleFieldsSC) != address(0), "BattleFields cannot be zero");
        require(address(_battleFieldsSC).code.length > 0, "BattleFields must be a contract");
        nftPrice = _price;
        heroArenaBattleFieldsSC = _battleFieldsSC;
    }

    /**
     * Initialize V1 metadata after the existing BattleFields contract ownership
     * has been transferred to this contract. This can only be performed once.
     */
    function initializeBattleFields() external onlyOwner {
        require(!battleFieldsInitialized, "BattleFields already initialized");
        require(heroArenaBattleFieldsSC.owner() == address(this), "V1 is not BattleFields owner");

        battleFieldsInitialized = true;
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(2, "MapId002");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(3, "MapId003");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(4, "MapId004");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(5, "MapId005");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(6, "MapId006");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(7, "MapId007");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(8, "MapId008");
        heroArenaBattleFieldsSC.setBattleFieldNameAndCreatedTimestamp(9, "MapId009");

        emit BattleFieldsInitialized(address(heroArenaBattleFieldsSC));
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
        require(battleFieldsInitialized, "BattleFields not initialized");
        require(_battleFieldId >= MIN_BATTLEFIELD_ID, "Input battleFieldId too low");
        require(_battleFieldId < MAX_BATTLEFIELD_ID_EXCLUSIVE, "Input battleFieldId unavailable");
        require(
            !heroArenaBattleFieldsSC.hasBattleField(msg.sender, _battleFieldId),
            "BattleField already owned"
        );

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), nftPrice);

        uint256 _tokenId = heroArenaBattleFieldsSC.mint(msg.sender, _battleFieldId);

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
        emit NFTContractOwnershipProposed(heroArenaBattleFieldsSC.owner(), _newOwner);
    }

    /**
     * Step 2: Accept the ownership of the NFT contract, only the pending owner can call it.
     */
    function acceptNFTContractOwnership() external {
        require(msg.sender == pendingNFTContractOwner, "Not the pending owner");
        address _previousOwner = heroArenaBattleFieldsSC.owner();
        pendingNFTContractOwner = address(0);
        heroArenaBattleFieldsSC.transferOwnership(msg.sender);
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
