import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const acceptableDelay = config.get("acceptable_delay");
    const tntToken = config.get("wrapped_matic")

    await deploy("PriceOracle", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            acceptableDelay,
            tntToken
        ],
    });
};

export default func;
func.tags = ["PriceOracle"];
