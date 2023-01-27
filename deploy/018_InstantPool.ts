import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const instantPercentageFee = config.get("instant_pool.instant_percentage_fee");

    const teleBTC = await deployments.get("TeleBTC")
    const instantRouter = await deployments.get("InstantRouter")

    const name = "TeleBTCInstantPoolToken"
    const symbol = "BTCIPT"

    await deploy("InstantPool", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            teleBTC.address,
            instantRouter.address,
            instantPercentageFee,
            name,
            symbol
        ],
    });
};

export default func;
func.tags = ["InstantPool"];
