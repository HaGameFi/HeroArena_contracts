import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningBattleFieldV1Module", (m) => {
  // Reuse the existing HeroArenaBattleFields contract. After deploying V1,
  // transfer that contract's ownership to V1 and call initializeBattleFields()
  // before enabling claims.
  const factory = m.contract("HeroArenaMiningBattleFieldV1", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", "0x189570aBd1886112Ed21029e10504d4EBbA49FAC", 10000000000000n]);

  m.call(factory, "updateNFTPrice", [200000000000000000000000n]);

  // m.call(factory, "updateAvailableClaim", [true]);
  
  return { factory };
});
