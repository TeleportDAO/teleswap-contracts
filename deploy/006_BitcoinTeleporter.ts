import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const unlockFee = 0;
    const unlockPeriod = 0;
    const requiredLockedAmount = 0;

    const tbtToken = await deployments.get("ERC20")
    const exchangeRouter = await deployments.get("ExchangeRouter")

    await deploy("BitcoinTeleporter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tbtToken.address,
            exchangeRouter.address,
            unlockFee,
            unlockPeriod,
            requiredLockedAmount
        ],
    });
};

export default func;
func.tags = ["BitcoinTeleporter"];
