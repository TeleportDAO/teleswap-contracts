import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;
    let tx;
    
    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set telebtc globally...")
    
    // const telebtc = await deployments.get("TeleBTC")
    const telebtc = await deployments.get("TeleBTCProxy")

    // set relay in cc transfer router
    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const ccTransferRouterFactory = await ethers.getContractFactory("CCTransferRouter")
    const ccTransferRouterInstance = await ccTransferRouterFactory.attach(
        ccTransferRouter.address
    )

    const checkTeleBTCInCCTransfer = await ccTransferRouterInstance.teleBTC()

    if (checkTeleBTCInCCTransfer != telebtc.address) {
        tx = await ccTransferRouterInstance.setTeleBTC(
            telebtc.address
        )
        tx.wait(1)
        console.log("set teleBTC in CCtransfer router: ", tx.hash)
    } else {
        console.log("teleBTC is already settled in CCtransfer router")
    }

    // set relay in cc burn router
    const relayHelper = await deployments.get("RelayHelper")
    const ccBurnRouter = await deployments.get("CCBurnRouter")
    const ccBurnRouterFactory = await ethers.getContractFactory(
        "CCBurnRouter",
        {
            libraries: {
                RelayHelper: relayHelper.address
            }
        }
    )
    const ccBurnRouterInstance = await ccBurnRouterFactory.attach(
        ccBurnRouter.address
    )

    const checkTeleBTCInCCBurn = await ccBurnRouterInstance.teleBTC() 

    if (checkTeleBTCInCCBurn != telebtc.address) {
        tx = await ccBurnRouterInstance.setTeleBTC(
            telebtc.address
        )
        tx.wait(1)
        console.log("set telebtc in CCburn router: ", tx.hash)
    } else {
        console.log("telebtc is already settled in CCburn router")
    }

    // set telebtc in cc exchange router
    const ccExchangeRouter = await deployments.get("CCExchangeRouter")
    const ccExchangeRouterFactory = await ethers.getContractFactory("CCExchangeRouter")
    const ccExchangeRouterInstance = await ccExchangeRouterFactory.attach(
    ccExchangeRouter.address
    )

    const checkTeleBTCInCCExchange = await ccExchangeRouterInstance.teleBTC() 

    if (checkTeleBTCInCCExchange != telebtc.address) {
        tx = await ccExchangeRouterInstance.setTeleBTC(
            telebtc.address
        )
        tx.wait(1)
        console.log("set telebtc in CCexchange router: ", tx.hash)
    } else {
        console.log("telebtc is already settled in CCexchange router")
    }

    // set telebtc in locker
    // const lockers = await deployments.get("LockersProxy")
    // const lockersLib = await deployments.get("LockersLib")
    // const lockersFactory = await ethers.getContractFactory(
    //     "LockersLogicTestnet",
    //     {
    //         libraries: {
    //             LockersLib: lockersLib.address
    //         }
    //     }
    // );
    // const lockersInstance = await lockersFactory.attach(
    //     lockers.address
    // )

    // tx = await lockersInstance.setTeleBTC(
    //     telebtc.address
    // )
    // tx.wait(1)
    // console.log("set telebtc in lockers: ", tx.hash)

    logger.color('blue').log("-------------------------------------------------")

};

export default func;
