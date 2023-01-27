import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const connectorName = "QuickswapV2"

    const uniswapV2Router02 = config.get("uniswap_v2_router_02")

    await deploy("UniswapV2Connector", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            connectorName,
            uniswapV2Router02
        ],
    });
};

export default func;
func.tags = ["UniswapV2Connector"];
