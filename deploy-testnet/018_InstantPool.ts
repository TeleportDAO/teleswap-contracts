import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();


    const instantPercentageFee = 50;

    const teleBTC = await deployments.get("TeleBTC")
    const instantRouter = await deployments.get("InstantRouter")

    const name = "InstantPoolToken"
    const symbol = "IPT"

    const theArgs = [
        teleBTC.address,
        instantRouter.address,
        instantPercentageFee,
        name,
        symbol
    ]

    const instantPool = await deploy("InstantPool", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    log(`InstantPool at ${instantPool.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        verify(
            instantPool.address,
            theArgs
        )
    }
};

export default func;
func.tags = ["InstantPool", "BitcoinTestnet"];
