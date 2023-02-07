import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set teleBTC in Locker...")

    const one = BigNumber.from(10).pow(18).mul(1)

    const lockersLib = await deployments.get("LockersLib")
    const lockersProxy = await deployments.get("LockersProxy")

    const ccBurnRouter = await deployments.get("CCBurnRouter")

    const lockersLogicFactory = await ethers.getContractFactory(
        "LockersLogic",
        {
            libraries: {
                LockersLib: lockersLib.address
            }
        }
    );
    const lockersInstance = await lockersLogicFactory.attach(
        lockersProxy.address
    );


    const ccBurnRouterAddress = await lockersInstance.ccBurnRouter()

    if (ccBurnRouterAddress != ccBurnRouter.address) {
        const addCCBurnRouter = await lockersInstance.setCCBurnRouter(
            ccBurnRouter.address
        )

        await addCCBurnRouter.wait(1)
        console.log("add cc burn router in lockers proxy contract: ", addCCBurnRouter.hash)
    } else {
        console.log("cc burn router is already settled in lockers proxy contract")
    }
    
    logger.color('blue').log("-------------------------------------------------")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
