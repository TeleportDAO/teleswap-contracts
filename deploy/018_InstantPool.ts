import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const instantPercentageFee = config.get("instant_pool.instant_percentage_fee");

    const teleBTC = await deployments.get("TeleBTC")
    const instantRouter = await deployments.get("InstantRouter")

    const name = "TeleBTCInstantPoolToken"
    const symbol = "BTCIPT"

    const deployedContract = await deploy("InstantPool", {
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

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
            teleBTC.address,
            instantRouter.address,
            instantPercentageFee,
            name,
            symbol
        ], "contracts/pools/InstantPool.sol:InstantPool")
    }
};

export default func;
func.tags = ["InstantPool"];
