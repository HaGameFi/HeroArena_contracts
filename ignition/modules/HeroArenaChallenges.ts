import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("HeroArenaChallengesModule", (m) => {
  const challenges = m.contract("HeroArenaChallenges", []);

  return { challenges };
});