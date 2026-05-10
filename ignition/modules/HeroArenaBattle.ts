import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaBattleModule", (m) => {
  const battle = m.contract("HeroArenaBattle", ["0x89673B08c6c28916141538aae6fE2ecF41bea105"]);

  m.call(battle, "updateAvailableCreateBattle", [true]);

//   m.call(battle, "grantRole", ["0x5e17fc5225d4a099df75359ce1f405503ca79498a8dc46a7d583235a0ee45c16", "0x9Fca6742F74Bc0A680fB32fB21579aE63b68D1d4"]);
//   m.call(battle, "updateBonusToken", ["0x6df1e5f15d296bc9a1134a160c24eb9ec694e694", 0]);
//   m.call(battle, "updateAllowedBetToken", ["0x6df1e5f15d296bc9a1134a160c24eb9ec694e694", true]);
//   m.call(battle, "updateAllowedBetToken", ["0x0000000000000000000000000000000000000000", true]);
  
  return { battle };
});