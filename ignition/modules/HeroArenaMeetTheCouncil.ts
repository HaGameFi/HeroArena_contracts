import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMeetTheCouncilModule", (m) => {
  const pve = m.contract("HeroArenaMeetTheCouncil", ["0x3145C4A4bc473dfdE67B98E588e634b897Aa1697", "0x48B3f5Ea324d8e0AFaF63c8469f664Bc659B3bbc"]);

  m.call(pve, "updateAvailableSubmit", [true]);

  //m.call(challenge, "grantRole", ["0x417473bd65d0115cf4a47eff46577b922ecf48d2ed852e1f1a968d9c0f628c19", "0x59Fc35BF9AE78E7d7Be7Ccc6B45ab6A6dc5A5295"]);

  //m.call(pve, "initLevels", []); 

  return { pve };
});