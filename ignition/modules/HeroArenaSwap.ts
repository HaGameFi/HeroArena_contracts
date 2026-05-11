import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaSwapModule", (m) => {
  const swap = m.contract("HeroArenaSwap", ["0x6df1e5f15d296bc9a1134a160c24eb9ec694e694", 5000000000000000000000n]);

  // transfer some HAP into SC

  return { swap };
});