import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const feeToSetterAddress = config.get("fee_to_setter")

    const theArgs = [
        feeToSetterAddress
    ]

    const uniswapFactory = await deploy("UniswapV2Factory", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    log(`UniswapV2Factory at ${uniswapFactory.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        await verify(
            uniswapFactory.address,
            theArgs
        )
    }

};

export default func;
func.tags = ["UniswapV2Factory", "BitcoinTestnet"];
