import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const normalConfirmationParameter = 3;
    const transferDeadline = 100;
    const burningFee = 0;

    const tbtToken = await deployments.get("ERC20")
    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const bitcoinTeleporter = await deployments.get("BitcoinTeleporter")

    await deploy("CCBurnRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            bitcoinRelay.address,
            bitcoinTeleporter.address,
            tbtToken.address,
            normalConfirmationParameter,
            transferDeadline,
            burningFee
        ],
    });
};

export default func;
func.tags = ["CCBurnRouter"];
