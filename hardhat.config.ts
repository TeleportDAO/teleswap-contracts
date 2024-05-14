import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";
import '@openzeppelin/hardhat-upgrades';
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-deploy-tenderly";
import "hardhat-contract-sizer";

dotenv.config();

const config: HardhatUserConfig = {
	solidity: {
		compilers: [
			{
				version: "0.5.16",
				settings: {
					optimizer: {
						enabled: true
					},
				},
			},
			{
				version: "0.6.6",
				settings: {
					optimizer: {
						enabled: true
					},
				},
			},
			{
				version: "0.8.4",
				settings: {
					optimizer: {
						enabled: true,
						runs: 200,
					},
				},
			}
		],
	},
	networks: {
		mainnet: {
			url: "https://eth.llamarpc.com",
			chainId: 1,
			accounts: [process.env.PRIVATE_KEY ?? ""]
		},
		polygon: {
			url: "https://rpc-mainnet.maticvigil.com/",
			chainId: 137,
			accounts: [process.env.PRIVATE_KEY ?? ""]
		},
		mumbai: {
			url: "https://polygon-mumbai.g.alchemy.com/v2/249SGZUqU12h4C4rAtPnb39FsJ09XMA9",
			chainId: 80001,
			accounts: [process.env.PRIVATE_KEY ?? ""]
		},
		amoy: {
			url: "https://rpc-amoy.polygon.technology",
			chainId: 80002,
			accounts: [process.env.PRIVATE_KEY ?? ""]
		},
		bsc: {
			url: "https://bsc-dataseed.binance.org/",
			chainId: 56,
			accounts: [process.env.PRIVATE_KEY ?? ""]
		},
		bsc_testnet: {
			url: "https://bsc-testnet.publicnode.com",
			chainId: 97,
			accounts: [process.env.PRIVATE_KEY ?? ""]
		},
		hardhat: {
			allowUnlimitedContractSize: true,
		},
	},	
  	paths: {
		artifacts: "artifacts",
		deploy: "deploy",
		deployments: "deployments",
  	},
  	typechain: {
		outDir: "src/types",
		target: "ethers-v5",
  	},
  	namedAccounts: {
		deployer: {
			default: 0,
		},
  	},
  	gasReporter: {
		// enabled: process.env.REPORT_GAS !== undefined,
		enabled: true,
		currency: "USD",
  	},
  	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY,
  	},
};

export default config;
