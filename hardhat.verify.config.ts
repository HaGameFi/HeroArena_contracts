import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    version: "0.8.29",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    bscTestnet: {
      type: "http",
      chainType: "l1",
      url: "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
      accounts: [],
    },
  },
  verify: {
    etherscan: {
      apiKey: "9PSZ4Y8K9NVFHRYS5HG7UA7VFGZNU5UCJV",
    },
  },
});
