import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaProfileModule", (m) => {
  const profile = m.contract("HeroArenaProfile", ["0x6df1e5f15d296bc9a1134a160c24eb9ec694e694", 0, 0]);

//   m.call(profile, "grantRole", ["0x4ad03022a30d74eec4387df6b3113797d5e272979263cc8e2f27b1c508217b6c", "0x7dee245a65533AA80a634c65c34DF83775Bc9746"]);
//   m.call(profile, "grantRole", ["0x110b44e4bccdedbab0625f137765abddea8ae658791a82fff3fb5e80db2bad48", "0xdB581a164eF1148E851d18E04c37104E045041c3"]);
//   m.call(profile, "grantRole", ["0x3f12a51c1a5d4235e47a0365ddc220be1678ccffcdf71bfd6ee9c417f801e008", "0x49975b88ff9594d430c271F25F75462785Bd9fAE"]);


  return { profile };
});
