import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMeetTheCouncilModule", (m) => {
  const pve = m.contract("HeroArenaMeetTheCouncil", ["0xd02172e12b9f2D5a0163F61b366EF195Bff32AeF", "0xC9A37d565E6bb0F5EE5A5071F57F2f100D5dB621"]);

  m.call(pve, "updateAvailableSubmit", [true]);

  //m.call(challenge, "grantRole", ["0x0000000000000000000000000000000000000000000000000000000000000000", "0x02334708A7069993fe7f14cdbfC9863AcF3598C4"]); // grant myself to be admin
  //m.call(challenge, "grantRole", ["0x417473bd65d0115cf4a47eff46577b922ecf48d2ed852e1f1a968d9c0f628c19", "0x59Fc35BF9AE78E7d7Be7Ccc6B45ab6A6dc5A5295"]);

  //m.call(pve, "initLevels", []); 

  return { pve };
});