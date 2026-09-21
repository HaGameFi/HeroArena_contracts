import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningFactoryV1Module", (m) => {
  // NOTICE: No need deploy HeroArenaAvatars independently
  const factory = m.contract("HeroArenaMiningFactoryV1", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", 10000000000000n]);

  m.call(factory, "updateNFTPrice", [2000000000000000000000n]);

  // m.call(factory, "updateAvailableClaim", [true]);
  
  return { factory };
});