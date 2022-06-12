import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const fastLimit = 1000;
    const fastFee = 10;
    const neededConfirmations = 6;

    const ccTransferRouter = await deployments.get("CCTransferRouter")

    await deploy("FastRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            ccTransferRouter.address,
            fastLimit,
            fastFee,
            neededConfirmations
        ],
    });
};

export default func;
func.tags = ["FastRouter"];
