import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaBattleModule", (m) => {
  const battle = m.contract("HeroArenaBattle", ["0xC9A37d565E6bb0F5EE5A5071F57F2f100D5dB621"]);

  m.call(battle, "updateAvailableCreateBattle", [true]);

//   m.call(battle, "grantRole", ["0x5e17fc5225d4a099df75359ce1f405503ca79498a8dc46a7d583235a0ee45c16", "0x9Fca6742F74Bc0A680fB32fB21579aE63b68D1d4"]);
//   m.call(battle, "updateBonusToken", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", 0]);
//   m.call(battle, "updateAllowedBetToken", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", true]);
//   m.call(battle, "updateAllowedBetToken", ["0x0000000000000000000000000000000000000000", true]);
  
  return { battle };
});