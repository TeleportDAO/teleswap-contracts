import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "TeleportDAOBitcoin"
    const tokenSymbol = "TBTC"

    const ccTransferRouter = await deployments.get("CCTransferRouter")

    await deploy("WrappedToken", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tokenName,
            tokenSymbol,
            ccTransferRouter.address
        ],
    });
};

export default func;
func.tags = ["WrappedToken"];
