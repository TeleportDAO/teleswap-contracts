import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const connectorName = "TheConnector"
    const weth = await deployments.get("WETH")
    const uniswapV2Router02 = await deployments.get("UniswapV2Router02")

    const theArgs = [
        connectorName,
        uniswapV2Router02.address
    ]

    const uniswapConnector = await deploy("UniswapV2Connector", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    // log(`UniswapV2Connector at ${uniswapConnector.address}`)
    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     await verify(
    //         uniswapConnector.address,
    //         theArgs
    //     )
    // }
};

export default func;
func.tags = ["UniswapV2Connector", "BitcoinTestnet"];
