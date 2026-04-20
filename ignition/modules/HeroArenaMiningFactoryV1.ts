import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningFactoryV1Module", (m) => {
  // NOTICE: No need deploy HeroArenaAvatars independently
  const factory = m.contract("HeroArenaMiningFactoryV1", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 10000000000000n]);

  m.call(factory, "updateAvailableClaim", [true]);

  
  return { factory };
});