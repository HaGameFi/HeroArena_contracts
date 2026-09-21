import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMeetTheDarkElfModule", (m) => {
  const pve = m.contract("HeroArenaMeetTheDarkElf", ["0xd02172e12b9f2D5a0163F61b366EF195Bff32AeF", "0xC9A37d565E6bb0F5EE5A5071F57F2f100D5dB621"]);

  m.call(pve, "updateAvailableSubmit", [true]);

  //m.call(challenge, "grantRole", ["0x0000000000000000000000000000000000000000000000000000000000000000", "0x02334708A7069993fe7f14cdbfC9863AcF3598C4"]); // grant myself to be admin
  // 对着HeroArenaChallenges合约调用
  //m.call(challenge, "grantRole", ["0x417473bd65d0115cf4a47eff46577b922ecf48d2ed852e1f1a968d9c0f628c19", "0x59Fc35BF9AE78E7d7Be7Ccc6B45ab6A6dc5A5295"]);
  //m.call(challenge, "grantRole", ["0x417473bd65d0115cf4a47eff46577b922ecf48d2ed852e1f1a968d9c0f628c19", "0xB30723d0751417b2997a1C742149BD888043d7B6"]);

  //m.call(pve, "initLevels", []); 

  return { pve };
});