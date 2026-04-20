import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaProfileModule", (m) => {
  const profile = m.contract("HeroArenaProfile", ["0xf4b7de083a0b02a339d9bc066098ed2b0a227018", 0, 0]);

//   m.call(profile, "grantRole", ["0x4ad03022a30d74eec4387df6b3113797d5e272979263cc8e2f27b1c508217b6c", "0xd7eC8fbb16DBbA6Cd3134Bc3fEA05Da0883AE07D"]);
//   m.call(profile, "grantRole", ["0x110b44e4bccdedbab0625f137765abddea8ae658791a82fff3fb5e80db2bad48", "0xD93084746202c4cF4a2b5C53247206a9C6C19154"]);
//   m.call(profile, "grantRole", ["0x3f12a51c1a5d4235e47a0365ddc220be1678ccffcdf71bfd6ee9c417f801e008", "0x49975b88ff9594d430c271F25F75462785Bd9fAE"]);


  return { profile };
});
