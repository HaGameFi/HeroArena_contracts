import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaSwapModule", (m) => {
  const swap = m.contract("HeroArenaSwap", ["0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f", 5000000000000000000000n]);

  // transfer some HAP into SC !!!

  return { swap };
});