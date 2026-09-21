import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningFactoryV2Module", (m) => {
  // NOTICE: No need deploy HeroArenaAvatars independently
  const factory = m.contract("HeroArenaMiningFactoryV2", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", "0x15D1130F633eD5C3ae68F9EE7205B0573527e434", 10000000000000n]);

  m.call(factory, "updateNFTPrice", [2000000000000000000000n]);

  // m.call(factory, "updateAvailableClaim", [true]);
  
  return { factory };
});

// 部署 V2，传入现有 HAP、Avatar 地址和价格。
// V1 owner 调用 proposeNFTContractOwnership(V2)。
// V2 owner 调用 acceptAvatarOwnershipFromV1(V1)。
// 确认 Avatar owner 已变成 V2。
// 调用 setAvatarJson()。
// 检查 30–59 元数据。
// 小额测试铸造。
// 最后调用 updateAvailableClaim(true)。