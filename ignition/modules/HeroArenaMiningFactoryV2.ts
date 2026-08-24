import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaMiningFactoryV2Module", (m) => {
  // NOTICE: No need deploy HeroArenaAvatars independently
  const factory = m.contract("HeroArenaMiningFactoryV2", ["0xa4082103a3ccd5a0599e28f6e21c87a477f5e97f", "0x0F90da4384670ff8be95e7940B2A09846C9160f3", 10000000000000n]);

  m.call(factory, "updateNFTPrice", [50000000000000000000n]);

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