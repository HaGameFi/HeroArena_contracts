### HapToken
0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f (BscTestnet) // TEST: 0xa18f344252aa87265acda1492277926eb47b8f5d
0x4d46228f72de5f3f02418af796d4ff2c1ea03f72 (BscMainnet)

### HapTokenVesting
0xf37781db20e502911eca166ad194628339da79e2 (BscTestnet) // TEST: 0x7e018f530c01b1dd6db6ea639e333f2d5347596c
0xac48740be3cb1f4800a3ea48473b8e8062b993dd (BscMainnet)

### HapTokenTreasury
0x67d7ad0fcd500a8aaaa8e448d69f22af0aa8e34e (BscTestnet) // TEST: 0xd4f088758044d772854f60cd0d3c14d682154bf5
0x60213db17e3648e648db11866cf97b3e29caa2ed (BscMainnet)

### HeroArenaProfile
0x48B3f5Ea324d8e0AFaF63c8469f664Bc659B3bbc (BscTestnet)
0xC9A37d565E6bb0F5EE5A5071F57F2f100D5dB621 (BscMainnet)

### HeroArenaMiningFactoryV1
0xb66fdf2923BCEd95bA6A7f9dbE2D24Ca9468D423 (BscTestnet)
0xA4082103A3Ccd5a0599e28F6E21c87A477F5E97F (BscMainnet)

### HeroArenaMiningFactoryV2
0xD4afBDc683406193680C89926FAA9CA4a4255559 (BscTestnet)
0x3145C4A4bc473dfdE67B98E588e634b897Aa1697 (BscMainnet)

### HeroArenaAvatars (NFT)
0x0F90da4384670ff8be95e7940B2A09846C9160f3 (BscTestnet)
0x15D1130F633eD5C3ae68F9EE7205B0573527e434 (BscMainnet)

### HeroArenaSwap
0x3e5457E132D0aA11771f8118854726dDfB29A787 (BscTestnet)
0x0c73468455A66737a57f578292DAA0fA1617a4fB (BscMainnet)

### HeroArenaChallenges
0x3145C4A4bc473dfdE67B98E588e634b897Aa1697 (BscTestnet)
0xd02172e12b9f2D5a0163F61b366EF195Bff32AeF (BscMainnet)

### HeroArenaMeetTheCouncil
0x59Fc35BF9AE78E7d7Be7Ccc6B45ab6A6dc5A5295 (BscTestnet)
0x59Afd58Ab4B4144927f8A4787a2F5252B8e739Cb (BscMainnet)

### HeroArenaMeetTheDarkElf
0xB30723d0751417b2997a1C742149BD888043d7B6 (BscTestnet)
0x8318d3D1670053Ed6E20A603e5146f7a62011c47 (BscMainnet)

### HeroArenaBattle
0x736BCa52Ccf97cA6f0b4947601C163cF87bC7C9F (BscTestnet)
0x2a75079e64214cFb65DaFbAb6aAE12f7f594BB9a (BscMainnet)

### VotingEscrowHAP
0x7F25A3B78DC4675360B73925e5CF3c523da6672F (BscTestnet)
0xa9A868125aca990B0f7Abb02fec1C567ABe0dF12 (BscMainnet)

### VoteEventFactory
0x8651f2a6a7d90b32bfe64e9edccC0eaFB591c89f (BscTestnet)
0x1118d23A61E724ddde95B77Ff2Ec741E906bA158 (BscMainnet)

### VotingRewardVault
0x30595a4Be9F70256A1FD78a81Af4aCe351b6c2A9 (BscTestnet)
0x6047028E0e6346BC814b67b6650A0F032184B8B1 (BscMainnet)

### HeroArenaFrames
0x44CE8a60fDd2c8cFAA32705dD0D3f2b8b567469f (BscMainnet)

### HeroArenaMiningStationV0
0xa28D126685F4cfeC2BB642E5f9bD01EDEED040f9 (BscMainnet)

### HeroArenaMiningStationV1
0x8f7a88cB86422e0b3842f4E45D8A2Be9D65F1639 (BscMainnet)

### HeroArenaBattleFields
0x86e42E79F0d34804b719bBDD46E02EcCe12827a3 (BscMainnet)

### HeroArenaMiningBattleFieldV0
0xcB52Fa3A8e0095B0B2019Aed5fa7A780B2C6E3F5 (BscMainnet)

### HeroArenaMiningBattleFieldV1
0xc8861833b0ca87c3f6d701ae6d2bdEE5FfAaf48F (BscMainnet)

### AVATAR_ROLE
0x4ad03022a30d74eec4387df6b3113797d5e272979263cc8e2f27b1c508217b6c

### POINT_ROLE
0x110b44e4bccdedbab0625f137765abddea8ae658791a82fff3fb5e80db2bad48

### SPECIAL_ROLE
0x3f12a51c1a5d4235e47a0365ddc220be1678ccffcdf71bfd6ee9c417f801e008

### CHALLENGE_ADMIN_ROLE
0x417473bd65d0115cf4a47eff46577b922ecf48d2ed852e1f1a968d9c0f628c19

### OPERATOR_ROLE (PvE)
0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929

### LIQUIDATOR_ROLE (PvP)
0x5e17fc5225d4a099df75359ce1f405503ca79498a8dc46a7d583235a0ee45c16


`VoteEventFactory` deliberately treats ownership and `EVENT_CREATOR_ROLE` as
separate authorities. Transferring factory ownership moves
`DEFAULT_ADMIN_ROLE`, but does not automatically remove existing event
creators. During every signer rotation or deployment handover, the new role
admin must explicitly remove every retired creator:

```solidity
bytes32 creatorRole = factory.EVENT_CREATOR_ROLE();
factory.revokeRole(creatorRole, oldCreator);
```

After handover, verify `hasRole(creatorRole, oldCreator) == false` for every
retired signer and grant the role only to the approved governance multisig.
The VotingEscrowHAP and VotingRewardVault addresses must also be protected in
HapToken with `setProtected` before users deposit funds.

## License
This project is licensed under the MIT License - see the 
[LICENSE](LICENSE) file for details.
