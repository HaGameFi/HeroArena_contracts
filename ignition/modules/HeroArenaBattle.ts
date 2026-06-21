import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaBattleModule", (m) => {
  const battle = m.contract("HeroArenaBattle", ["0x48B3f5Ea324d8e0AFaF63c8469f664Bc659B3bbc"]);

  m.call(battle, "updateAvailableCreateBattle", [true]);

//   m.call(battle, "grantRole", ["0x5e17fc5225d4a099df75359ce1f405503ca79498a8dc46a7d583235a0ee45c16", "0x9Fca6742F74Bc0A680fB32fB21579aE63b68D1d4"]);
//   m.call(battle, "updateBonusToken", ["0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f", 0]);
//   m.call(battle, "updateAllowedBetToken", ["0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f", true]);
//   m.call(battle, "updateAllowedBetToken", ["0x0000000000000000000000000000000000000000", true]);
  
  return { battle };
});