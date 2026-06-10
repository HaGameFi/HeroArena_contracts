// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IProfileReentryTarget {
    function detachAvatar() external;
    function detachFrame() external;
    function updateAvatar(address _avatarAddress, uint256 _tokenId, uint256 _maxFee) external;
}

/**
 * @notice Mock ERC721 whose safeTransferFrom callback into the recipient (or
 *         the sender, depending on direction) triggers a re-entry into the
 *         HeroArenaProfile contract. Used to verify that detachAvatar() /
 *         detachFrame() / updateAvatar() / updateFrame() are guarded by
 *         nonReentrant against malicious or buggy whitelisted NFT collections.
 *
 *         Two attack shapes are supported, selected via reentryMode:
 *           0 = no reentry (control)
 *           1 = reenter detachAvatar()
 *           2 = reenter detachFrame()
 *           3 = reenter updateAvatar()
 *
 *         The mock implements both the OZ ERC721 transfer hook
 *         _update (called on both directions) so reentry can be triggered when
 *         the contract sends the token back to the user during detach.
 */
contract MockReentrantERC721 is ERC721 {
    address public profileTarget;
    uint8 public reentryMode;
    address public reentryAttackerAddr;
    uint256 public reentryAttackerTokenId;
    uint256 public _nextTokenId = 1;

    constructor() ERC721("MockReentrant", "MRE") {}

    function setProfileTarget(address p) external {
        profileTarget = p;
    }

    function setReentryMode(uint8 mode, address attacker, uint256 tokenId) external {
        reentryMode = mode;
        reentryAttackerAddr = attacker;
        reentryAttackerTokenId = tokenId;
    }

    function mint(address to) external returns (uint256) {
        uint256 id = _nextTokenId++;
        _mint(to, id);
        return id;
    }

    /**
     * @dev Hook fires on every transfer including safeTransferFrom from the
     *      profile contract back to the user (detach path). We fire the reentry
     *      ONLY when the sender is the profile contract returning the NFT,
     *      so the original setup transfer (user → profile) is not affected.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);

        if (reentryMode != 0 && from == profileTarget && to == reentryAttackerAddr) {
            if (reentryMode == 1) {
                IProfileReentryTarget(profileTarget).detachAvatar();
            } else if (reentryMode == 2) {
                IProfileReentryTarget(profileTarget).detachFrame();
            } else if (reentryMode == 3) {
                IProfileReentryTarget(profileTarget).updateAvatar(
                    address(this),
                    reentryAttackerTokenId,
                    type(uint256).max
                );
            }
        }
    }
}
