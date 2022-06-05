import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const exchangeRouter = await deployments.get("ExchangeRouter")
    const bitcoinTeleporter = await deployments.get("BitcoinTeleporter")
    const ccTransferRouter = await deployments.get("CCTransferRouter")

    await deploy("CCExchangeRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            exchangeRouter.address,
            bitcoinTeleporter.address,
            ccTransferRouter.address
        ],
    });
};

export default func;
func.tags = ["CCExchangeRouter"];
