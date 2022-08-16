import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const connectorName = "TheConnector"
    const weth = await deployments.get("WETH")
    const uniswapV2Router02 = await deployments.get("UniswapV2Router02")

    await deploy("UniswapV2Connector", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            connectorName,
            uniswapV2Router02.address,
            weth.address
        ],
    });
};

export default func;
func.tags = ["UniswapV2Connector"];
