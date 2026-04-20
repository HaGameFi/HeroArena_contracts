// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

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
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(17, "Cleric_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(18, "Ninja_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(19, "Ninja_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(20, "VoidMonk_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(21, "VoidMonk_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(22, "VoidMonk_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(23, "VoidMonk_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(24, "Impaler_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(25, "Impaler_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(26, "Impaler_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(27, "Impaler_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(28, "Necro_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(29, "Necro_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(30, "Necro_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(31, "Necro_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(32, "Necro_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(33, "Priestess_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(34, "Priestess_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(35, "Priestess_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(36, "Priestess_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(37, "Priestess_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(38, "Phantom_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(39, "Phantom_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(40, "Phantom_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(41, "Wraith_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(42, "Wraith_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(43, "Gunner_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(44, "Gunner_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(45, "Gunner_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(46, "Gunner_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(47, "Grenadier_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(48, "Grenadier_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(49, "Engineer_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(50, "Engineer_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(51, "Engineer_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(52, "Engineer_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(53, "Paladin_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(54, "Paladin_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(55, "Paladin_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(56, "Paladin_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(57, "Annihilator_v5");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(58, "Warrior_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(59, "Warrior_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(60, "Warrior_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(61, "Warrior_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(62, "AxeThrower_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(63, "AxeThrower_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(64, "Witch_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(65, "Witch_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(66, "Witch_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(67, "Witch_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(68, "Shaman_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(69, "Shaman_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(70, "Shaman_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(71, "Shaman_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(72, "Chieftain_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(73, "Chieftain_v5");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(74, "Soldier_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(75, "Soldier_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(76, "Spy_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(77, "Spy_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(78, "Sniper_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(79, "Sniper_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(80, "Scout_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(81, "Scout_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(82, "Pyro_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(83, "Pyro_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(84, "Heavy_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(85, "Heavy_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(86, "Demo_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(87, "Engie_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(88, "Medic_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(89, "Medic_v1");

        // Other parameters initialized
        numberOfAvatars = 90;
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