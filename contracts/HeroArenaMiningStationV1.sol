// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./HeroArenaFrames.sol";

contract HeroArenaMiningStationV1 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public HapToken;
    HeroArenaFrames public immutable heroArenaFramesSC;

    bool public availableClaim;
    bool public framesInitialized;
    uint256 public nftPrice;

    uint8 private constant MIN_FRAME_ID = 1;
    uint8 private constant MAX_FRAME_ID_EXCLUSIVE = 2;

    address public pendingNFTContractOwner;

    event FrameMinted(address indexed user, uint256 indexed tokenId, uint8 indexed frameId);
    event AvailableClaimUpdated(address indexed owner, bool isAvail);
    event FramePriceUpdated(uint256 newPrice);
    event FramesInitialized(address indexed framesContract);
    event NFTContractOwnershipProposed(address indexed previousOwner, address indexed pendingOwner);
    event NFTContractOwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(IERC20 _HapToken, HeroArenaFrames _framesSC, uint256 _price) Ownable(msg.sender) {
        require(address(_HapToken) != address(0), "HapToken cannot be zero");
        require(address(_HapToken).code.length > 0, "HapToken must be a contract");
        require(address(_framesSC) != address(0), "Frames cannot be zero");
        require(address(_framesSC).code.length > 0, "Frames must be a contract");

        HapToken = _HapToken;
        heroArenaFramesSC = _framesSC;
        nftPrice = _price;
    }

    /**
     * Initialize V1 metadata after the existing Frames contract ownership has
     * been transferred to this contract. This can only be performed once.
     */
    function initializeFrames() external onlyOwner {
        require(!framesInitialized, "Frames already initialized");
        require(heroArenaFramesSC.owner() == address(this), "V1 is not Frames owner");

        framesInitialized = true;
        heroArenaFramesSC.setFrameNameAndCreatedTimestamp(1, "Sapphire_v0");

        emit FramesInitialized(address(heroArenaFramesSC));
    }

    function updateAvailableClaim(bool _isAvailable) external onlyOwner {
        availableClaim = _isAvailable;
        emit AvailableClaimUpdated(msg.sender, _isAvailable);
    }

    function mintNFT(uint8 _frameId) external {
        require(availableClaim, "Cannot claim");
        require(framesInitialized, "Frames not initialized");
        require(_frameId >= MIN_FRAME_ID, "Input frameId too low");
        require(_frameId < MAX_FRAME_ID_EXCLUSIVE, "Input frameId unavailable");
        require(!heroArenaFramesSC.hasFrame(msg.sender, _frameId), "Frame already owned");

        HapToken.safeTransferFrom(msg.sender, address(this), nftPrice);
        uint256 _tokenId = heroArenaFramesSC.mint(msg.sender, _frameId);

        emit FrameMinted(msg.sender, _tokenId, _frameId);
    }

    function updateNFTPrice(uint256 _newPrice) external onlyOwner {
        nftPrice = _newPrice;
        emit FramePriceUpdated(_newPrice);
    }

    function proposeNFTContractOwnership(address _newOwner) external onlyOwner {
        pendingNFTContractOwner = _newOwner;
        emit NFTContractOwnershipProposed(heroArenaFramesSC.owner(), _newOwner);
    }

    function acceptNFTContractOwnership() external {
        require(msg.sender == pendingNFTContractOwner, "Not the pending owner");
        address _previousOwner = heroArenaFramesSC.owner();
        pendingNFTContractOwner = address(0);
        heroArenaFramesSC.transferOwnership(msg.sender);
        emit NFTContractOwnershipTransferred(_previousOwner, msg.sender);
    }

    function claimFee(uint256 _amount) external onlyOwner {
        HapToken.safeTransfer(msg.sender, _amount);
    }
}
