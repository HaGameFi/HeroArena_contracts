import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMeetTheCouncilModule", (m) => {
  const pve = m.contract("HeroArenaMeetTheCouncil", ["0x2bc8889987A7e5646bD37AFd94b4860c0D08Cf93", "0x922Ec303C910AA1797FDd7B855fCb608f195C0E4"]);

  m.call(pve, "updateAvailableSubmit", [true]);

  //m.call(pve, "initLevels", []); // 不能直接调用，需要先将此合约提升为CHALLENGE_ADMIN_ROLE

  return { pve };
});