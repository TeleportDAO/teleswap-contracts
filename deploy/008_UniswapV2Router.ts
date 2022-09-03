import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const weth = await deployments.get("WETH")
    const uniswapV2Factory = await deployments.get("UniswapV2Factory")

    await deploy("UniswapV2Router02", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            uniswapV2Factory.address,
            weth.address
        ],
    });
};

export default func;
func.tags = ["UniswapV2Router02", "BitcoinMainnet"];
