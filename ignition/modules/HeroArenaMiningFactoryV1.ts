import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningFactoryV1Module", (m) => {
  // NOTICE: No need deploy HeroArenaAvatars independently
  const factory = m.contract("HeroArenaMiningFactoryV1", ["0x6df1e5f15d296bc9a1134a160c24eb9ec694e694", 10000000000000n]);

  m.call(factory, "updateAvailableClaim", [true]);

  
  return { factory };
});