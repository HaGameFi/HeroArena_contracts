import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HapTokenModule", (m) => {
  const token = m.contract("HapToken");

   m.call(token, "setMainPool", ["0xd861Af70b9414762873Ad7387b95E96c6f6E8140"]);

  return { token };
});
