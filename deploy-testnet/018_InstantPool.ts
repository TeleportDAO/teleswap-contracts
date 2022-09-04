import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();


    const instantPercentageFee = 50;

    const teleBTC = await deployments.get("TeleBTC")
    const instantRouter = await deployments.get("InstantRouter")

    const name = "InstantPoolToken"
    const symbol = "IPT"

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
func.tags = ["InstantPool", "BitcoinTestnet"];
