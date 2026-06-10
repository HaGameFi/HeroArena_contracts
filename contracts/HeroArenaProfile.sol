// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title HeroArenaProfile
 * @notice This is a contract for users to bind their address to
 * a customizable profile by choosing a team.
 *
 * @dev Avatar and frame NFT contracts are whitelisted by the owner via
 *      addAvatarAddress / addFrameAddress. The whitelist is security-critical
 *      because updateAvatar / updateFrame call ownerOf() and safeTransferFrom()
 *      on those contracts; non-standard or malicious ERC721 implementations
 *      can revert profile flows, mis-report ownership, or interfere with NFT
 *      custody. Only approve collections that have been reviewed for ERC721
 *      compliance and predictable transfer behavior. The supportsInterface
 *      check in the add*Address admin functions is necessary but NOT sufficient.
 */
contract HeroArenaProfile is AccessControl, ERC721Holder, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public HapToken;

    bytes32 public constant AVATAR_ROLE = keccak256("AVATAR_ROLE");
    bytes32 public constant FRAME_ROLE = keccak256("FRAME_ROLE");
    bytes32 public constant POINT_ROLE = keccak256("POINT_ROLE");
    bytes32 public constant SPECIAL_ROLE = keccak256("SPECIAL_ROLE");

    uint256 public numberOfActiveProfiles;
    uint256 public numberOfTeams;
    uint256 public feeToRegister;
    uint256 public feeToUpdate;

    mapping(address => bool) public hasRegistered;

    struct Team {
        string teamTitle;
        string teamDescription;
        uint256 numberOfUsers;
        uint256 totalPoints;
        bool isJoinable;
    }

    struct User {
        uint256 id;
        uint256 selfPoints;
        uint256 teamId;
        address avatarAddress;
        uint256 tokenId;
        address frameAddress;
        uint256 frameTokenId;
    }

    mapping(uint256 => Team) private _teamMapping;
    mapping(address => User) private _userMapping;

    uint256 private _teamCounter;
    uint256 private _userCounter;

    event TeamAdded(uint256 indexed teamId, string teamTitle);
    event TeamRenamed(uint256 indexed teamId, string teamTitle);
    event TeamTotalPointIncrease(uint256 indexed teamId, uint256 numberOfPoints, uint256 indexed campaignId);
    event UpdateFeeCost(address indexed owner, uint256 newFeeToRegister, uint256 newFeeToUpdate);
    event UserChangeTeam(address indexed user, uint256 previousTeamId, uint256 newTeamId);
    event UserNew(address indexed user, uint256 teamId);
    event UserAvatarUpdate(address indexed user, address avatarAddress, uint256 tokenId);
    event UserFrameUpdate(address indexed user, address frameAddress, uint256 frameTokenId);
    event UserPointIncrease(address indexed user, uint256 numberOfPoints, uint256 indexed campaignId);
    event UserPointIncreaseBatch(address[] users, uint256 numberOfPoints, uint256 indexed campaignId);

    event TeamJoinableUpdated(uint256 indexed teamId, bool isJoinable);
    event FeeClaimed(address indexed owner, uint256 amount);
    event AvatarAddressAdded(address indexed avatarAddress);
    event FrameAddressAdded(address indexed frameAddress);
    event UserPointDecrease(address indexed user, uint256 numberOfPoints);
    event UserPointDecreaseBatch(address[] users, uint256 numberOfPoints);
    event TeamTotalPointDecrease(uint256 indexed teamId, uint256 numberOfPoints);

    /// @notice Emitted when a user detaches their currently-assigned avatar
    ///         or frame NFT without supplying a replacement.
    event UserAvatarDetached(address indexed user, address avatarAddress, uint256 tokenId);
    event UserFrameDetached(address indexed user, address frameAddress, uint256 frameTokenId);

    modifier onlyPoint() {
        require(hasRole(POINT_ROLE, msg.sender), "Not a point role");
        _;
    }

    modifier onlySpecial() {
        require(hasRole(SPECIAL_ROLE, msg.sender), "Not a special role");
        _;
    }

    constructor(IERC20 _HapToken, uint256 _feeToRegister, uint256 _feeToUpdate) Ownable(msg.sender) {
        HapToken = _HapToken;
        feeToRegister = _feeToRegister;
        feeToUpdate = _feeToUpdate;

        // _grantRole here is now redundant with the _transferOwnership override
        // that fires from Ownable's constructor, but kept for explicitness — it
        // is idempotent (already-granted role is a no-op for state semantics).
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Keep Ownable and AccessControl authorities aligned. When the owner
     *      changes (including renounceOwnership which transfers to address(0)),
     *      grant DEFAULT_ADMIN_ROLE to the new owner and revoke it from the
     *      previous owner. Without this, transferOwnership would leave the
     *      original deployer with role-management power even after they're no
     *      longer Ownable.owner().
     *
     *      Fires from Ownable's constructor too (previousOwner = address(0)),
     *      so the initial DEFAULT_ADMIN_ROLE grant is handled here. The
     *      _grantRole call in the constructor body is a redundant no-op kept
     *      for documentation.
     */
    function _transferOwnership(address newOwner) internal override {
        address previousOwner = owner();
        super._transferOwnership(newOwner);
        if (previousOwner != address(0) && previousOwner != newOwner) {
            _revokeRole(DEFAULT_ADMIN_ROLE, previousOwner);
        }
        if (newOwner != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        }
    }

    /**
     * Add a new team
     */
    function addTeam(string calldata _teamTitle, string calldata _teamDescription) external onlyOwner {
        // Verify the length of team's title
        bytes memory strBytes = bytes(_teamTitle);
        require(strBytes.length > 5 && strBytes.length < 20, "Team title length should > 5 and < 20 bytes");

        // Increment the _teamCounter and get teamId
        _teamCounter += 1;
        uint256 _newTeamId = _teamCounter;

        // Add new data into the team struct
        _teamMapping[_newTeamId] = Team({
            teamTitle: _teamTitle,
            teamDescription: _teamDescription,
            numberOfUsers: 0,
            totalPoints: 0,
            isJoinable: true
        });

        numberOfTeams = _newTeamId;

        // emit event
        emit TeamAdded(_newTeamId, _teamTitle);
    }

    /**
     * Get an exist team
     */
    function getTeam(uint256 _teamId) external view returns (string memory, string memory, uint256, uint256, bool) {
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");
        return (
            _teamMapping[_teamId].teamTitle,
            _teamMapping[_teamId].teamDescription,
            _teamMapping[_teamId].numberOfUsers,
            _teamMapping[_teamId].totalPoints,
            _teamMapping[_teamId].isJoinable
        );
    }

    /**
     * Rename an exist team
     */
    function renameTeam(uint256 _teamId, string calldata _teamTitle, string calldata _teamDescription) external onlyOwner {
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");
        
        // Verify the length of team's title
        bytes memory strBytes = bytes(_teamTitle);
        require(strBytes.length > 5 && strBytes.length < 20, "Team title length should > 5 and < 20 bytes");

        _teamMapping[_teamId].teamTitle = _teamTitle;
        _teamMapping[_teamId].teamDescription = _teamDescription;

        // emit event
        emit TeamRenamed(_teamId, _teamTitle);
    }

    /**
     * Make an exist team joinable
     */
    function makeTeamJoinable(uint256 _teamId) external onlyOwner {
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");
        _teamMapping[_teamId].isJoinable = true;
        emit TeamJoinableUpdated(_teamId, true);
    }

    /**
     * Make an exist team not joinable
     */
    function makeTeamNotJoinable(uint256 _teamId) external onlyOwner {
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");
        _teamMapping[_teamId].isJoinable = false;
        emit TeamJoinableUpdated(_teamId, false);
    }

    /**
     * Claim fee to the admin
     */
    function claimFee(uint256 _amount) external onlyOwner {
        HapToken.safeTransfer(msg.sender, _amount);
        emit FeeClaimed(msg.sender, _amount);
    }

    /**
     * Update fee cost for register and update user's profile
     */
    function updateFeeCost(uint256 _feeToRegister, uint256 _feeToUpdate) external onlyOwner {
        feeToRegister = _feeToRegister;
        feeToUpdate = _feeToUpdate;

        // emit event
        emit UpdateFeeCost(msg.sender, _feeToRegister, _feeToUpdate);
    }

    /**
     * To create a user profile. It sends the HAP to this address.
     * @param _teamId  Team to join.
     * @param _maxFee  Maximum HAP the caller is willing to pay as registration
     *                 fee. Pass `type(uint256).max` to opt out of slippage
     *                 protection.
     * @dev The owner can change `feeToRegister` at any time. Requiring a
     *      user-supplied cap prevents an admin front-run from charging more
     *      than the user intended at submission time.
     */
    function createProfile(uint256 _teamId, uint256 _maxFee) external {
        require(!hasRegistered[msg.sender], "User is registered");
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");
        require(_teamMapping[_teamId].isJoinable, "The team currently is not joinable");

        uint256 _fee = feeToRegister;
        require(_fee <= _maxFee, "Fee exceeds maximum");

        // Increment the _userCounter and get user's id
        _userCounter += 1;
        uint256 _newUserId = _userCounter;

        // Add new data into the user struct
        _userMapping[msg.sender] = User({
            id: _newUserId,
            selfPoints: 0,
            teamId: _teamId,
            avatarAddress: address(0),
            tokenId: 0,
            frameAddress: address(0),
            frameTokenId: 0
        });

        // Update user's registration status
        hasRegistered[msg.sender] = true;

        // Update the number of active profiles
        numberOfActiveProfiles += 1;

        // Increase the number of Users for the team
        _teamMapping[_teamId].numberOfUsers += 1;

        // Transfer HAP tokens to this contract
        HapToken.safeTransferFrom(msg.sender, address(this), _fee);

        // emit event
        emit UserNew(msg.sender, _teamId);
    }

    /**
     * To update a user's avatar. It sends the HAP to this address.
     * @param _maxFee Maximum HAP fee the caller is willing to pay. Pass
     *                `type(uint256).max` to opt out of slippage protection.
     * @dev See createProfile for the slippage rationale.
     */
    function updateAvatar(address _avatarAddress, uint256 _tokenId, uint256 _maxFee) external nonReentrant {
        // Checks
        require(hasRegistered[msg.sender], "User not registered");
        require(hasRole(AVATAR_ROLE, _avatarAddress), "Avatar address invalid");

        uint256 _fee = feeToUpdate;
        require(_fee <= _maxFee, "Fee exceeds maximum");

        address _previousAvatarAddress = _userMapping[msg.sender].avatarAddress;
        uint256 _previousTokenId = _userMapping[msg.sender].tokenId;

        IERC721 _avatarToken = IERC721(_avatarAddress);
        require(msg.sender == _avatarToken.ownerOf(_tokenId), "Only owner can transfer his/her NFT");

        // Effects（先更新状态，防止重入）
        _userMapping[msg.sender].avatarAddress = _avatarAddress;
        _userMapping[msg.sender].tokenId = _tokenId;

        // Interactions（后执行外部调用）
        _avatarToken.safeTransferFrom(msg.sender, address(this), _tokenId);
        HapToken.safeTransferFrom(msg.sender, address(this), _fee);

        if (_previousAvatarAddress != address(0)) {
            IERC721(_previousAvatarAddress).safeTransferFrom(address(this), msg.sender, _previousTokenId);
        }

        emit UserAvatarUpdate(msg.sender, _avatarAddress, _tokenId);
    }

    /**
     * To update a user's frame. It sends the HAP to this address.
     * @param _maxFee Maximum HAP fee the caller is willing to pay. Pass
     *                `type(uint256).max` to opt out of slippage protection.
     * @dev See createProfile for the slippage rationale.
     */
    function updateFrame(address _frameAddress, uint256 _frameTokenId, uint256 _maxFee) external nonReentrant {
        // Checks
        require(hasRegistered[msg.sender], "User not registered");
        require(hasRole(FRAME_ROLE, _frameAddress), "Frame address invalid");

        uint256 _fee = feeToUpdate;
        require(_fee <= _maxFee, "Fee exceeds maximum");

        address _previousFrameAddress = _userMapping[msg.sender].frameAddress;
        uint256 _previousFrameTokenId = _userMapping[msg.sender].frameTokenId;

        IERC721 _frameToken = IERC721(_frameAddress);
        require(msg.sender == _frameToken.ownerOf(_frameTokenId), "Only owner can transfer his/her NFT");

        // Effects（先更新状态，防止重入）
        _userMapping[msg.sender].frameAddress = _frameAddress;
        _userMapping[msg.sender].frameTokenId = _frameTokenId;

        // Interactions（后执行外部调用）
        _frameToken.safeTransferFrom(msg.sender, address(this), _frameTokenId);
        HapToken.safeTransferFrom(msg.sender, address(this), _fee);

        if (_previousFrameAddress != address(0)) {
            IERC721(_previousFrameAddress).safeTransferFrom(address(this), msg.sender, _previousFrameTokenId);
        }

        emit UserFrameUpdate(msg.sender, _frameAddress, _frameTokenId);
    }

    /**
     * @notice Detach (return) the user's currently-assigned avatar NFT without
     *         supplying a replacement and without paying the update fee.
     * @dev Returns the NFT to the user and clears the slot, without requiring
     *      a replacement NFT or charging feeToUpdate. AVATAR_ROLE on the
     *      previous address is NOT required so the user can still recover their
     *      NFT even if the project later revokes the role from a stale
     *      collection.
     */
    function detachAvatar() external nonReentrant {
        require(hasRegistered[msg.sender], "User not registered");

        address _previousAvatarAddress = _userMapping[msg.sender].avatarAddress;
        uint256 _previousTokenId = _userMapping[msg.sender].tokenId;
        require(_previousAvatarAddress != address(0), "No avatar attached");

        // Effects first.
        _userMapping[msg.sender].avatarAddress = address(0);
        _userMapping[msg.sender].tokenId = 0;

        IERC721(_previousAvatarAddress).safeTransferFrom(address(this), msg.sender, _previousTokenId);

        emit UserAvatarDetached(msg.sender, _previousAvatarAddress, _previousTokenId);
    }

    /**
     * @notice Detach (return) the user's currently-assigned frame NFT.
     * @dev Companion to detachAvatar(). Same rationale.
     */
    function detachFrame() external nonReentrant {
        require(hasRegistered[msg.sender], "User not registered");

        address _previousFrameAddress = _userMapping[msg.sender].frameAddress;
        uint256 _previousFrameTokenId = _userMapping[msg.sender].frameTokenId;
        require(_previousFrameAddress != address(0), "No frame attached");

        _userMapping[msg.sender].frameAddress = address(0);
        _userMapping[msg.sender].frameTokenId = 0;

        IERC721(_previousFrameAddress).safeTransferFrom(address(this), msg.sender, _previousFrameTokenId);

        emit UserFrameDetached(msg.sender, _previousFrameAddress, _previousFrameTokenId);
    }

    /**
     * To add a avatar NFT address for users to set their profile.
     * @dev AccessControl emits RoleGranted; we additionally emit a
     *      domain-specific event for easier off-chain indexing.
     */
    function addAvatarAddress(address _avatarAddress) external onlyOwner {
        require(IERC721(_avatarAddress).supportsInterface(0x80ac58cd), "Not ERC721");
        _grantRole(AVATAR_ROLE, _avatarAddress);
        emit AvatarAddressAdded(_avatarAddress);
    }

    /**
     * To add a frame NFT address for users to set their profile.
     */
    function addFrameAddress(address _frameAddress) external onlyOwner {
        require(IERC721(_frameAddress).supportsInterface(0x80ac58cd), "Not ERC721");
        _grantRole(FRAME_ROLE, _frameAddress);
        emit FrameAddressAdded(_frameAddress);
    }

    /**
     * To change to another team.
     */
    function changeTeam(address _userAddress, uint256 _newTeamId) external onlySpecial {
        require(hasRegistered[_userAddress], "User not registered");
        require(_userMapping[_userAddress].teamId != _newTeamId, "User is already in the team");
        require(_newTeamId > 0 && _newTeamId <= numberOfTeams, "TeamId invalid");
        require(_teamMapping[_newTeamId].isJoinable, "The team currently is not joinable");

        // Save previous teamId
        uint256 _previousTeamId = _userMapping[_userAddress].teamId;

        // Decrease the number of Users in previous team
        _teamMapping[_previousTeamId].numberOfUsers -= 1;

        // Update the teamId of user
        _userMapping[_userAddress].teamId = _newTeamId;

        // Increase the number of Users in new team
        _teamMapping[_newTeamId].numberOfUsers += 1;

        // emit event
        emit UserChangeTeam(_userAddress, _previousTeamId, _newTeamId);
    }

    /**
     * To increase the number of points for a user.
     */
    function increaseUserPoints(address _userAddress, uint256 _numberOfPoints, uint256 _campaignId) external onlyPoint {
        require(hasRegistered[_userAddress], "User not registered");
        
        _userMapping[_userAddress].selfPoints += _numberOfPoints;

        // emit event
        emit UserPointIncrease(_userAddress, _numberOfPoints, _campaignId);
    }

    /**
     * To increase the number of points for a group of user.
     */
    function increaseUserPointsBatch(address[] calldata _userAddresses, uint256 _numberOfPoints, uint256 _campaignId) external onlyPoint {
        require(_userAddresses.length < 1001, "Group size must be < 1001");

        for (uint256 i = 0; i < _userAddresses.length; i++) {
            if (!hasRegistered[_userAddresses[i]]) continue;

            _userMapping[_userAddresses[i]].selfPoints += _numberOfPoints;
        }

        // emit event
        emit UserPointIncreaseBatch(_userAddresses, _numberOfPoints, _campaignId);
    }

    /**
     * To increase the number of points for a team.
     */
    function increaseTeamPoints(uint256 _teamId, uint256 _numberOfPoints, uint256 _campaignId) external onlyPoint {
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");
        
        _teamMapping[_teamId].totalPoints += _numberOfPoints;

        // emit event
        emit TeamTotalPointIncrease(_teamId, _numberOfPoints, _campaignId);
    }

    /**
     * To decrease the number of points for a user.
     */
    function decreaseUserPoints(address _userAddress, uint256 _numberOfPoints) external onlyPoint {
        require(hasRegistered[_userAddress], "User not registered");

        _userMapping[_userAddress].selfPoints -= _numberOfPoints;
        emit UserPointDecrease(_userAddress, _numberOfPoints);
    }

    /**
     * To decrease the number of points for a group of user.
     */
    function decreaseUserPointsBatch(address[] calldata _userAddresses, uint256 _numberOfPoints) external onlyPoint {
        require(_userAddresses.length < 1001, "Group size must be < 1001");

        for (uint256 i = 0; i < _userAddresses.length; i++) {
            if (!hasRegistered[_userAddresses[i]]) continue;

            _userMapping[_userAddresses[i]].selfPoints -= _numberOfPoints;
        }
        emit UserPointDecreaseBatch(_userAddresses, _numberOfPoints);
    }

    /**
     * To decrease the number of points for a team.
     */
    function decreaseTeamPoints(uint256 _teamId, uint256 _numberOfPoints) external onlyPoint {
        require(_teamId > 0 && _teamId <= numberOfTeams, "TeamId invalid");

        _teamMapping[_teamId].totalPoints -= _numberOfPoints;
        emit TeamTotalPointDecrease(_teamId, _numberOfPoints);
    }

    /**
     * To get a user's profile.
     */
    function getUserProfile(address _userAddress) external view returns (uint256, uint256, uint256, address, uint256) {
        require(hasRegistered[_userAddress], "User not registered");
        
        return (
            _userMapping[_userAddress].id,
            _userMapping[_userAddress].selfPoints,
            _userMapping[_userAddress].teamId,
            _userMapping[_userAddress].avatarAddress,
            _userMapping[_userAddress].tokenId
        );
    }
}