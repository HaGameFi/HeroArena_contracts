import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaBattleModule", (m) => {
  const battle = m.contract("HeroArenaBattle", ["0x922Ec303C910AA1797FDd7B855fCb608f195C0E4"]);

  m.call(battle, "updateAvailableCreateBattle", [true]);

//   m.call(battle, "grantRole", ["0x5e17fc5225d4a099df75359ce1f405503ca79498a8dc46a7d583235a0ee45c16", "0x9Fca6742F74Bc0A680fB32fB21579aE63b68D1d4"]);
//   m.call(battle, "updateFeeAndBounsTokenAddressWithAmount", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 0, "0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 0]);
//   m.call(battle, "updateAllowedBetToken", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", true]);
//   m.call(battle, "updateAllowedBetToken", ["0x0000000000000000000000000000000000000000", true]);
  
  return { battle };
});