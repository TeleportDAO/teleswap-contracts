import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const feeToSetterAddress = config.get("fee_to_setter")

    await deploy("UniswapV2Factory", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            feeToSetterAddress
        ],
    });
};

export default func;
func.tags = ["UniswapV2Factory"];
