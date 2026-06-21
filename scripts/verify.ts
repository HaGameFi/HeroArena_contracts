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