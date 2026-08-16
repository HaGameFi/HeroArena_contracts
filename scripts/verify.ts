// verify HapToken
pnpm hardhat verify etherscan --network bscTestnet 0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f 0x02334708a7069993fe7f14cdbfc9863acf3598c4
// verify HapTokenVesting
pnpm hardhat verify etherscan --network bscTestnet 0xf37781db20e502911eca166ad194628339da79e2 0x6df1e5f15d296bc9a1134a160c24eb9ec694e694 1782009000 0x02334708a7069993fe7f14cdbfc9863acf3598c4
// verify HapTokenTreasury
pnpm hardhat verify etherscan --network bscTestnet 0x67d7ad0fcd500a8aaaa8e448d69f22af0aa8e34e 0x02334708a7069993fe7f14cdbfc9863acf3598c4 0xd861Af70b9414762873Ad7387b95E96c6f6E8140


pnpm hardhat ignition deploy ignition/modules/HeroArenaProfile.ts --network bscTestnet --verify

pnpm hardhat ignition deploy ignition/modules/HeroArenaMiningFactoryV1.ts --network bscTestnet --verify

> pnpm hardhat verify --network bscTestnet 0x6047028E0e6346BC814b67b6650A0F032184B8B1

pnpm hardhat ignition deploy ignition/modules/HeroArenaSwap.ts --network bscTestnet --verify

pnpm hardhat ignition deploy ignition/modules/HeroArenaChallenges.ts --network bscTestnet --verify

pnpm hardhat ignition deploy ignition/modules/HeroArenaMeetTheCouncil.ts --network bscTestnet --verify

pnpm hardhat ignition deploy ignition/modules/HeroArenaBattle.ts --network bscTestnet --verify


Network: bscTestnet (97)
Deployer: 0x02334708A7069993fe7f14cdbfC9863AcF3598C4
Balance: 3.186588920039426634 native token
HAP: 0xA4082103A3Ccd5a0599e28F6E21c87A477F5E97F
HeroArenaProfile: 0x48B3f5Ea324d8e0AFaF63c8469f664Bc659B3bbc
Governance admin: 0x02334708A7069993fe7f14cdbfC9863AcF3598C4

[1/2] Deploying VotingEscrowHAP...
VotingEscrowHAP: 0x7F25A3B78DC4675360B73925e5CF3c523da6672F

[2/2] Deploying VoteEventFactory (creates VotingRewardVault internally)...
VoteEventFactory: 0x8651f2a6a7d90b32bfe64e9edccC0eaFB591c89f
VotingRewardVault: 0x30595a4Be9F70256A1FD78a81Af4aCe351b6c2A9

Deployment record: deployment-governance-bscTestnet-97.json

ACTION REQUIRED: the HAP admin multisig must execute these calls before use:
- HapToken.setProtected(0x7F25A3B78DC4675360B73925e5CF3c523da6672F, true) for VotingEscrowHAP
  target: 0xA4082103A3Ccd5a0599e28F6E21c87A477F5E97F
  data:   0x8a7f997c0000000000000000000000007f25a3b78dc4675360b73925e5cf3c523da6672f0000000000000000000000000000000000000000000000000000000000000001
- HapToken.setProtected(0x30595a4Be9F70256A1FD78a81Af4aCe351b6c2A9, true) for VotingRewardVault
  target: 0xA4082103A3Ccd5a0599e28F6E21c87A477F5E97F
  data:   0x8a7f997c00000000000000000000000030595a4be9f70256a1fd78a81af4ace351b6c2a90000000000000000000000000000000000000000000000000000000000000001

VoteEvent is intentionally not deployed here; each event is created by VoteEventFactory.


set -a
source .env
set +a

pnpm hardhat run scripts/verify-governance.ts --network bscTestnet