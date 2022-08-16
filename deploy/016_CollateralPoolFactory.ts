import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const zero_address = "0x0000000000000000000000000000000000000000";

    await deploy("CollateralPoolFactory", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            zero_address
        ],
    });
};

export default func;
func.tags = ["CollateralPoolFactory"];
