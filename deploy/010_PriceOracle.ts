import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    // TODO: change for deploying on mainnet
    const acceptableDelay = 1000;
    const tntToken = await deployments.get("WETH")

    await deploy("PriceOracle", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            acceptableDelay,
            tntToken.address
        ],
    });
};

export default func;
func.tags = ["PriceOracle"];
