import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();
    let tx
    
    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set instant router globally...")
    
    const instantRouter = await deployments.get("InstantRouter")

    // set instant router in cc transfer router
    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const ccTransferRouterFactory = await ethers.getContractFactory("CCTransferRouter")
    const ccTransferRouterInstance = await ccTransferRouterFactory.attach(
        ccTransferRouter.address
    )

    const checkInstantRouterInCCTransfer = await ccTransferRouterInstance.instantRouter()

    if (checkInstantRouterInCCTransfer != instantRouter.address) {
        tx = await ccTransferRouterInstance.setInstantRouter(
            instantRouter.address
        )
        tx.wait(1)
        console.log("set instant router in CCtransfer router: ", tx.hash)
    } else {
        console.log("instant router is already settled in CCtransfer router")
    }
    


    //  set instant router in cc instant pool
    const instantPool = await deployments.get("InstantPool")
    const instantPoolFactory = await ethers.getContractFactory("InstantPool")
    const instantPoolInstance = await instantPoolFactory.attach(
        instantPool.address
    )

    const checkInstantRouterInInstantPool = await instantPoolInstance.instantRouter()

    if (checkInstantRouterInInstantPool != instantRouter.address) {
        tx = await instantPoolInstance.setInstantRouter(
            instantRouter.address
        )
        tx.wait(1)
        console.log("set instant router in instant pool: ", tx.hash)
    }

    

    // set instant router in cc exchange router
    const ccExchangeRouter = await deployments.get("CCExchangeRouter")
    const ccExchangeRouterFactory = await ethers.getContractFactory("CCExchangeRouter")
    const ccExchangeRouterInstance = await ccExchangeRouterFactory.attach(
    ccExchangeRouter.address
    )

    const checkInstantRouterCCExchange = await ccExchangeRouterInstance.instantRouter()

    if (checkInstantRouterCCExchange != instantRouter.address) {
        tx = await ccExchangeRouterInstance.setInstantRouter(
            instantRouter.address
        )
        tx.wait(1)
        console.log("set instant router in CCexchange router: ", tx.hash)
    } else {
        console.log("instant router is already settled in CCexchange router")
    }

};

export default func;
