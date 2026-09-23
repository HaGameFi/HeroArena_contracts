import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningStationV0Module", (m) => {
  // NOTICE: No need deploy HeroArenaFrames independently
  const station = m.contract("HeroArenaMiningStationV0", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", 10000000000000n]);

  m.call(station, "updateNFTPrice", [2000000000000000000000n]);

  // m.call(station, "updateAvailableClaim", [true]);
  
  return { station };
});