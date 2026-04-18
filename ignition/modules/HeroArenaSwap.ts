import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaSwapModule", (m) => {
  const swap = m.contract("HeroArenaSwap", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 5000000000000000000000n]);

  return { swap };
});