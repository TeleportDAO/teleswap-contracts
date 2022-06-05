import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const zeroAddress = "0x0000000000000000000000000000000000000000"

    await deploy("LiquidityPoolFactory", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            zeroAddress
        ],
    });
};

export default func;
func.tags = ["LiquidityPoolFactory"];
