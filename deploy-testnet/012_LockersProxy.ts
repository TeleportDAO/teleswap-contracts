import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from 'hardhat';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const lockersLogicTestnet = await deployments.get("LockersLogicTestnet")

    const theArgs = [
        lockersLogicTestnet.address,
        deployer,
        "0x"
    ]

    const lockerProxy = await deploy("LockersProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    log(`LockersProxy at ${lockerProxy.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        await verify(
            lockerProxy.address,
            theArgs
        )
    }
};

export default func;
func.tags = ["LockersProxy", "BitcoinTestnet"];
