// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./HeroArenaAvatars.sol";

interface IHeroArenaMiningFactoryMigration {
    function HapToken() external view returns (IERC20);
    function HeroArenaAvatarsSC() external view returns (HeroArenaAvatars);
    function pendingNFTContractOwner() external view returns (address);
    function acceptNFTContractOwnership() external;
}

// Backward-compatible name retained for integrations that imported the V1
// migration interface from an earlier V2 build.
interface IHeroArenaMiningFactoryV1Migration is IHeroArenaMiningFactoryMigration {}

contract HeroArenaMiningFactoryV2 is Ownable {
    using SafeERC20 for IERC20;

    /// @dev HapToken is set once in the constructor and never mutated;
    ///      declared immutable for gas savings + safety against accidental writes.
    IERC20 public immutable HapToken;
    HeroArenaAvatars public immutable heroArenaAvatarsSC;

    bool public availableClaim;

    // Price of HAP that a user needs to pay to for a NFT
    uint256 public nftPrice;

    uint8 private constant MIN_AVATAR_ID = 0;
    uint8 private constant MAX_AVATAR_ID_EXCLUSIVE = 60;

    bool public avatarMetadataInitialized;

    // Pending owner for two-step NFT contract ownership transfer
    address public pendingNFTContractOwner;

    event AvatarMinted(address indexed user, uint256 indexed tokenId, uint8 indexed avatarId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event AvatarPriceUpdated(uint256 newPrice);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AvatarOwnershipAccepted(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when accumulated HAP is withdrawn by the owner.
    event FeeClaimed(address indexed owner, uint256 amount);

    constructor(IERC20 _HapToken, HeroArenaAvatars _avatarsSC, uint256 _price) Ownable(msg.sender) {
        // Reject the zero address so a misconfigured deployment cannot leave
        // the factory pointing at a non-token, which would make every mintNFT()
        // call revert in an opaque way.
        require(address(_HapToken) != address(0), "HapToken cannot be zero");
        require(address(_HapToken).code.length > 0, "HapToken must be a contract");
        HapToken = _HapToken;
        require(address(_avatarsSC) != address(0), "Avatars cannot be zero");
        require(address(_avatarsSC).code.length > 0, "Avatars must be a contract");
        nftPrice = _price;
        heroArenaAvatarsSC = _avatarsSC;
    }

    modifier onlyWhenAvatarOwner() {
        require(heroArenaAvatarsSC.owner() == address(this), "V2 does not own Avatars");
        _;
    }

    /**
     * @notice Canonical migration getter shared by V1, V2 and future factories.
     * @dev The lower-camel-case immutable getter remains available as
     *      heroArenaAvatarsSC(); this alias preserves V1's established ABI so
     *      future factories can use one migration interface for every version.
     */
    function HeroArenaAvatarsSC() external view returns (HeroArenaAvatars) {
        return heroArenaAvatarsSC;
    }

    /**
     * @dev A proposal created by the old factory owner must not remain valid
     *      after ownership of this factory changes.
     */
    function _transferOwnership(address newOwner) internal override {
        if (pendingNFTContractOwner != address(0)) {
            address currentAvatarOwner = address(heroArenaAvatarsSC) == address(0)
                ? address(0)
                : heroArenaAvatarsSC.owner();
            emit NFTContractOwnershipProposed(currentAvatarOwner, address(0));
            pendingNFTContractOwner = address(0);
        }
        super._transferOwnership(newOwner);
    }

    /**
     * @notice Accept ownership of the existing Avatar contract from V1.
     * @dev V1 is supplied only for this one-time migration and is not retained.
     */
    function acceptAvatarOwnershipFromV1(IHeroArenaMiningFactoryMigration _factoryV1) external onlyOwner {
        _acceptAvatarOwnershipFromFactory(_factoryV1);
    }

    /**
     * @notice Accept Avatar ownership from any previous factory implementing
     *         the stable migration interface.
     * @dev Use this entry point for V2 -> V3 and subsequent migrations.
     */
    function acceptAvatarOwnershipFromFactory(IHeroArenaMiningFactoryMigration _previousFactory)
        external
        onlyOwner
    {
        _acceptAvatarOwnershipFromFactory(_previousFactory);
    }

    function _acceptAvatarOwnershipFromFactory(IHeroArenaMiningFactoryMigration _previousFactory)
        internal
    {
        require(address(_previousFactory) != address(0), "Previous factory cannot be zero");
        require(address(_previousFactory.HapToken()) == address(HapToken), "HAP token mismatch");
        require(
            address(_previousFactory.HeroArenaAvatarsSC()) == address(heroArenaAvatarsSC),
            "Avatars mismatch"
        );
        require(
            heroArenaAvatarsSC.owner() == address(_previousFactory),
            "Previous factory does not own Avatars"
        );
        require(
            _previousFactory.pendingNFTContractOwner() == address(this),
            "Factory is not the pending Avatar owner"
        );

        address previousOwner = heroArenaAvatarsSC.owner();
        _previousFactory.acceptNFTContractOwnership();
        require(heroArenaAvatarsSC.owner() == address(this), "Avatar ownership transfer failed");

        emit AvatarOwnershipAccepted(previousOwner, address(this));
    }

    /**
     * Update the availableClaim to allow user mint NFT.
     */
    function updateAvailableClaim(bool _isAvailable) external onlyOwner {
        if (_isAvailable) {
            require(heroArenaAvatarsSC.owner() == address(this), "V2 does not own Avatars");
            require(avatarMetadataInitialized, "Avatar metadata not initialized");
        }
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
    function mintNFT(uint8 _avatarId, uint256 _maxPrice) external onlyWhenAvatarOwner {
        require(availableClaim, "Cannot claim");
        require(_avatarId >= MIN_AVATAR_ID, "Input avatarId too low");
        require(_avatarId < MAX_AVATAR_ID_EXCLUSIVE, "Input avatarId unavailable");

        uint256 _price = nftPrice;
        require(_price <= _maxPrice, "Price exceeds maximum");

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), _price);

        uint256 _tokenId = heroArenaAvatarsSC.mint(msg.sender, _avatarId);

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
    function proposeNFTContractOwnership(address _newOwner) external onlyOwner onlyWhenAvatarOwner {
        require(_newOwner != address(0), "New owner cannot be zero");
        pendingNFTContractOwner = _newOwner;
        emit NFTContractOwnershipProposed(heroArenaAvatarsSC.owner(), _newOwner);
    }

    /**
     * @notice Cancel any pending NFT-contract ownership proposal.
     * @dev    Required because proposeNFTContractOwnership() rejects
     *         address(0); this is the explicit cancellation entry point.
     */
    function cancelNFTContractOwnership() external onlyOwner {
        require(pendingNFTContractOwner != address(0), "No pending proposal");
        emit NFTContractOwnershipProposed(heroArenaAvatarsSC.owner(), address(0));
        pendingNFTContractOwner = address(0);
    }

    /**
     * Step 2: Accept the ownership of the NFT contract, only the pending owner can call it.
     */
    function acceptNFTContractOwnership() external onlyWhenAvatarOwner {
        require(msg.sender == pendingNFTContractOwner, "Not the pending owner");
        address _previousOwner = heroArenaAvatarsSC.owner();
        pendingNFTContractOwner = address(0);
        heroArenaAvatarsSC.transferOwnership(msg.sender);
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

    /**
     * @dev Set up json extensions for avatars 30-59
     * Assign tokenURI to look for each bunnyId in the mint function
     * Only the owner can set it.
     */
    function setAvatarJson() external onlyOwner onlyWhenAvatarOwner {
        require(!avatarMetadataInitialized, "Avatar metadata already initialized");
        avatarMetadataInitialized = true;

        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(30, "VoidMonk_v0");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(31, "VoidMonk_v1");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(32, "VoidMonk_v2");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(33, "VoidMonk_v3");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(34, "VoidMonk_v4");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(35, "VoidMonk_v5");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(36, "Impaler_v0");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(37, "Impaler_v1");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(38, "Impaler_v2");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(39, "Impaler_v3");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(40, "Impaler_v4");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(41, "Impaler_v5");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(42, "Priestess_v0");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(43, "Priestess_v1");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(44, "Priestess_v2");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(45, "Priestess_v3");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(46, "Priestess_v4");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(47, "Priestess_v5");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(48, "Necro_v0");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(49, "Necro_v1");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(50, "Necro_v2");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(51, "Necro_v3");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(52, "Necro_v4");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(53, "Necro_v5");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(54, "Wraith_v0");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(55, "Wraith_v1");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(56, "Wraith_v2");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(57, "Wraith_v3");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(58, "Wraith_v4");
        heroArenaAvatarsSC.setAvatarNameAndCreatedTimestamp(59, "Wraith_v5");
    }
}
