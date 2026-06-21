// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./HeroArenaAvatars.sol";

contract HeroArenaMiningFactoryV1 is Ownable {
    using SafeERC20 for IERC20;

    /// @dev HapToken is set once in the constructor and never mutated;
    ///      declared immutable for gas savings + safety against accidental writes.
    IERC20 public immutable HapToken;
    HeroArenaAvatars public HeroArenaAvatarsSC;

    bool public availableClaim;

    // Price of HAP that a user needs to pay to for a NFT
    uint256 public nftPrice;

    /// @notice Number of initial avatar series (i.e. different visuals).
    /// @dev Set once in the constructor and never modified; declared immutable
    ///      so it stays in code rather than storage.
    uint8 private immutable numberOfAvatars;

    // Pending owner for two-step NFT contract ownership transfer
    address public pendingNFTContractOwner;

    event AvatarMinted(address indexed user, uint256 indexed tokenId, uint8 indexed avatarId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event AvatarPriceUpdated(uint256 newPrice);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when accumulated HAP is withdrawn by the owner.
    event FeeClaimed(address indexed owner, uint256 amount);

    constructor(IERC20 _HapToken, uint256 _price) Ownable(msg.sender) {
        // Reject the zero address so a misconfigured deployment cannot leave
        // the factory pointing at a non-token, which would make every mintNFT()
        // call revert in an opaque way.
        require(address(_HapToken) != address(0), "HapToken cannot be zero");
        HapToken = _HapToken;
        nftPrice = _price;
        HeroArenaAvatarsSC = new HeroArenaAvatars();

        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(0, "Archer_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(1, "Archer_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(2, "Archer_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(3, "Archer_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(4, "Archer_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(5, "Archer_v5");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(6, "Cleric_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(7, "Cleric_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(8, "Cleric_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(9, "Cleric_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(10, "Cleric_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(11, "Cleric_v5");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(12, "Knight_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(13, "Knight_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(14, "Knight_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(15, "Knight_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(16, "Knight_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(17, "Knight_v5");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(18, "Ninja_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(19, "Ninja_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(20, "Ninja_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(21, "Ninja_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(22, "Ninja_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(23, "Ninja_v5");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(24, "Wizard_v0");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(25, "Wizard_v1");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(26, "Wizard_v2");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(27, "Wizard_v3");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(28, "Wizard_v4");
        HeroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(29, "Wizard_v5");

        // Other parameters initialized
        numberOfAvatars = 30;

        // Transfer of MiningFactory ownership clears pendingNFTContractOwner via
        // the _transferOwnership override below.
    }

    /**
     * @dev When the factory owner changes, any pending NFT-contract ownership
     *      proposal made by the old owner must not survive into the new owner's
     *      authority. We clear it on every ownership transition, including the
     *      constructor (initial transfer from address(0) to deployer), where
     *      there is nothing to clear yet.
     */
    function _transferOwnership(address newOwner) internal override {
        if (pendingNFTContractOwner != address(0)) {
            address staleProposer = address(HeroArenaAvatarsSC) == address(0)
                ? address(0)
                : HeroArenaAvatarsSC.owner();
            emit NFTContractOwnershipProposed(staleProposer, address(0));
            pendingNFTContractOwner = address(0);
        }
        super._transferOwnership(newOwner);
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
     * @param _avatarId Avatar series ID.
     * @param _maxPrice Maximum HAP price the caller is willing to pay. Pass
     *                  `type(uint256).max` to opt out of slippage protection.
     * @dev The owner can change `nftPrice` at any time. Requiring a user-side
     *      cap prevents a front-run price bump from consuming the user's
     *      allowance at a higher rate than they intended.
     */
    function mintNFT(uint8 _avatarId, uint256 _maxPrice) external {
        require(availableClaim, "Cannot claim");
        require(_avatarId < numberOfAvatars, "Input avatarId unavailable");

        uint256 _price = nftPrice;
        require(_price <= _maxPrice, "Price exceeds maximum");

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), _price);

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
     * @dev Reject the zero address. Use cancelNFTContractOwnership() for
     *      explicit cancellation so the intent is unambiguous.
     */
    function proposeNFTContractOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "New owner cannot be zero");
        pendingNFTContractOwner = _newOwner;
        emit NFTContractOwnershipProposed(HeroArenaAvatarsSC.owner(), _newOwner);
    }

    /**
     * @notice Cancel any pending NFT-contract ownership proposal.
     * @dev    Required because proposeNFTContractOwnership() rejects
     *         address(0); this is the explicit cancellation entry point.
     */
    function cancelNFTContractOwnership() external onlyOwner {
        require(pendingNFTContractOwner != address(0), "No pending proposal");
        emit NFTContractOwnershipProposed(HeroArenaAvatarsSC.owner(), address(0));
        pendingNFTContractOwner = address(0);
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
     * @dev Emits FeeClaimed so off-chain analytics can track admin withdrawals
     *      without parsing raw ERC20 transfer logs.
     */
    function claimFee(uint256 _amount) external onlyOwner {
        // Transfer HAP tokens to owner
        HapToken.safeTransfer(msg.sender, _amount);
        emit FeeClaimed(msg.sender, _amount);
    }
}   