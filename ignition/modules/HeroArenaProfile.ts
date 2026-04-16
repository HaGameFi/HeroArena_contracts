import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaProfileModule", (m) => {
  const profile = m.contract("HeroArenaProfile", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 0, 0]);

  return { profile };
});
