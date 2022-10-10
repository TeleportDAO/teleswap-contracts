import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const acceptableDelay = 1000;
    const tdtToken = await deployments.get("ERC20")

    const uniswapV2Router02 = await deployments.get("UniswapV2Router02")
    const uniswapV2Connector = await deployments.get("UniswapV2Connector")

    const theArgs = [
        acceptableDelay,
        tdtToken.address
    ]

    const priceOracle = await deploy("PriceOracle", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    // log(`PriceOracle at ${priceOracle.address}`)
    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     await verify(
    //         priceOracle.address,
    //         theArgs
    //     )
    // }
};

export default func;
func.tags = ["PriceOracle", "BitcoinTestnet"];
