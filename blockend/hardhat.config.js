require("@nomicfoundation/hardhat-toolbox");
require("hardhat-dependency-compiler");
require("hardhat-contract-sizer");
require("./tasks");
const { networks } = require("./networks");

const REPORT_GAS =
  process.env.REPORT_GAS?.toLowerCase() === "true" ? true : false;

const SOLC_SETTINGS = {
  optimizer: {
    enabled: true,
    runs: 1_000,
  },
};
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: SOLC_SETTINGS,
      },
      {
        version: "0.8.7",
        settings: SOLC_SETTINGS,
      },
      {
        version: "0.7.0",
        settings: SOLC_SETTINGS,
      },
      {
        version: "0.6.6",
        settings: SOLC_SETTINGS,
      },
      {
        version: "0.4.24",
        settings: SOLC_SETTINGS,
      },
    ],
  },

  networks: {
    ...networks,
  },
  etherscan: {
    apiKey: {
      baseSepolia: networks.baseSepolia.verifyApiKey,
      arbitrumSepolia: networks.arbitrumSepolia.verifyApiKey,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: networks.baseSepolia.chainId,
        urls: {
          apiURL: "https://base-sepolia.blockscout.com/api",
          browserURL: "https://base-sepolia.blockscout.com/",
        },
      },
      {
        network: "arbitrumSepolia",
        chainId: networks.arbitrumSepolia.chainId,
        urls: {
          apiURL: "https://sepolia-explorer.arbitrum.io/api",
          browserURL: "https://sepolia-explorer.arbitrum.io/",
        },
      },
    ],
  },
  gasReporter: {
    enabled: REPORT_GAS,
    currency: "USD",
    outputFile: "gas-report.txt",
    noColors: true,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./build/cache",
    artifacts: "./build/artifacts",
  },
  mocha: {
    timeout: 200000,
  },
};
