import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const lockersLib = await deploy("LockersLib", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
    })

    const lockerLogicTest = await deploy("LockersLogicTestnet", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        libraries: {
            "LockersLib": lockersLib.address
        },
    });

    // log(`LockersLogicTestnet at ${lockerLogicTest.address}`)
    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     await verify(
    //         lockerLogicTest.address,
    //         []
    //     )
    // }
};

export default func;
func.tags = ["LockersLogic", "BitcoinTestnet"];
