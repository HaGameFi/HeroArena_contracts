import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningFactoryV1Module", (m) => {
  // NOTICE: No need deploy HeroArenaAvatars independently
  const factory = m.contract("HeroArenaMiningFactoryV1", ["0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f", 10000000000000n]);

  m.call(factory, "updateNFTPrice", [50000000000000000000n]);

  // m.call(factory, "updateAvailableClaim", [true]);
  
  return { factory };
});