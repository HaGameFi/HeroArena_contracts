import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaProfileModule", (m) => {
  const profile = m.contract("HeroArenaProfile", ["0x4d46228f72de5f3f02418af796d4ff2c1ea03f72", 0, 0]);

  // AVATAR_ROLE
  //   m.call(profile, "grantRole", ["0x4ad03022a30d74eec4387df6b3113797d5e272979263cc8e2f27b1c508217b6c", "0x15D1130F633eD5C3ae68F9EE7205B0573527e434"]);
  // POINT_ROLE
  //   m.call(profile, "grantRole", ["0x110b44e4bccdedbab0625f137765abddea8ae658791a82fff3fb5e80db2bad48", "0x59Afd58Ab4B4144927f8A4787a2F5252B8e739Cb"]);
  //   m.call(profile, "grantRole", ["0x110b44e4bccdedbab0625f137765abddea8ae658791a82fff3fb5e80db2bad48", "0x8318d3D1670053Ed6E20A603e5146f7a62011c47"]);
  // SPECIAL_ROLE
  //   m.call(profile, "grantRole", ["0x3f12a51c1a5d4235e47a0365ddc220be1678ccffcdf71bfd6ee9c417f801e008", "0x49975b88ff9594d430c271F25F75462785Bd9fAE"]);
  //   m.call(profile, "addAvatarAddress", ["0x0F90da4384670ff8be95e7940B2A09846C9160f3"]);
  //   m.call(profile, "addFrameAddress", [""]); // 如果还没有部署则跳过

  // add avatar address
  // create 4 teams ！！！！！！！！

  return { profile };
});
