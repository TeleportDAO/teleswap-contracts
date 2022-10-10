import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const weth = await deployments.get("WETH")
    const uniswapV2Factory = await deployments.get("UniswapV2Factory")

    const theArgs = [
        uniswapV2Factory.address,
        weth.address
    ]

    const uniswapRouter = await deploy("UniswapV2Router02", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    // log(`UniswapV2Router02 at ${uniswapRouter.address}`)
    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     await verify(
    //         uniswapRouter.address,
    //         theArgs
    //     )
    // }
};

export default func;
func.tags = ["UniswapV2Router02", "BitcoinTestnet"];
