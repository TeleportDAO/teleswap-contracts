import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const wavax = await deployments.get("WAVAX")
    const liquidityPoolFactory = await deployments.get("LiquidityPoolFactory")

    await deploy("ExchangeRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            liquidityPoolFactory.address,
            wavax.address
        ],
    });
};

export default func;
func.tags = ["ExchangeRouter"];
