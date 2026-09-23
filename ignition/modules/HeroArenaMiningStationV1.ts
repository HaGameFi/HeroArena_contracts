import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningStationV1Module", (m) => {
  // Reuse the existing HeroArenaFrames contract. After deploying V1,
  // transfer that contract's ownership to V1 and call initializeBattleFields()
  // before enabling claims.
  const station = m.contract("HeroArenaMiningStationV1", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", "0x44CE8a60fDd2c8cFAA32705dD0D3f2b8b567469f", 10000000000000n]);

  m.call(station, "updateNFTPrice", [200000000000000000000000n]);

  // m.call(station, "updateAvailableClaim", [true]);
  
  return { station };
});
