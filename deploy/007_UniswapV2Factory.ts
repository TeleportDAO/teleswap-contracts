import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    let feeToSetter = 0;

    await deploy("UniswapV2Factory", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            feeToSetter
        ],
    });
};

export default func;
func.tags = ["UniswapV2Factory"];
