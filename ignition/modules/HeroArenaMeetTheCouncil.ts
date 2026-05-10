import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMeetTheCouncilModule", (m) => {
  const pve = m.contract("HeroArenaMeetTheCouncil", ["0x328428273295714A9907040D0C337a2BaAfF7623", "0x89673B08c6c28916141538aae6fE2ecF41bea105"]);

  m.call(pve, "updateAvailableSubmit", [true]);

  //m.call(pve, "initLevels", []); // 不能直接调用，需要先将此合约提升为CHALLENGE_ADMIN_ROLE

  return { pve };
});