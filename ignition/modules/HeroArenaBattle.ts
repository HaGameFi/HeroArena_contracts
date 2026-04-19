import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaBattleModule", (m) => {
  const battle = m.contract("HeroArenaBattle", ["0x922Ec303C910AA1797FDd7B855fCb608f195C0E4"]);

  m.call(battle, "updateAvailableCreateBattle", [true]);
//   m.call(battle, "updateFeeAndBounsTokenAddressWithAmount", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 0, "0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 0]);
//   m.call(battle, "updateAllowedBetToken", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", true]);
//   m.call(battle, "updateAllowedBetToken", ["0x0000000000000000000000000000000000000000", true]);
  
  return { battle };
});