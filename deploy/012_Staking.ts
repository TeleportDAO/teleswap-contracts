import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const tbtToken = await deployments.get("ERC20")

    await deploy("Staking", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tbtToken.address
        ],
    });
};

export default func;
func.tags = ["Staking"];
