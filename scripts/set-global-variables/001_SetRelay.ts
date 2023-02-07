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
    logger.color('blue').bold().log("Set relay globally...")
    
    const relay = await deployments.get("BitcoinRelay")

    // set relay in cc transfer router
    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const ccTransferRouterFactory = await ethers.getContractFactory("CCTransferRouter")
    const ccTransferRouterInstance = await ccTransferRouterFactory.attach(
        ccTransferRouter.address
    )

    const checkRelayInCCTransfer = await ccTransferRouterInstance.relay()

    if (checkRelayInCCTransfer != relay.address) {
        tx = await ccTransferRouterInstance.setRelay(
            relay.address
        )
        tx.wait(1)
        console.log("set relay in CCtransfer router: ", tx.hash)
    } else {
        console.log("relay is already settled in CCtransfer router")
    }
    


    // set relay in cc burn router
    const ccBurnRouter = await deployments.get("CCBurnRouter")
    const ccBurnRouterFactory = await ethers.getContractFactory("CCBurnRouter")
    const ccBurnRouterInstance = await ccBurnRouterFactory.attach(
        ccBurnRouter.address
    )

    const checkRelayInCCBurn = await ccBurnRouterInstance.relay()

    if (checkRelayInCCBurn != relay.address) {
        tx = await ccBurnRouterInstance.setRelay(
            relay.address
        )
        tx.wait(1)
        console.log("set relay in CCburn router: ", tx.hash)
    } else {
        console.log("relay is already settled in CCburn router")
    }

    

    // set relay in cc exchange router
    const ccExchangeRouter = await deployments.get("CCExchangeRouter")
    const ccExchangeRouterFactory = await ethers.getContractFactory("CCExchangeRouter")
    const ccExchangeRouterInstance = await ccExchangeRouterFactory.attach(
    ccExchangeRouter.address
    )

    const checkRelayInCCExchange = await ccExchangeRouterInstance.relay()

    if (checkRelayInCCExchange != relay.address) {
        tx = await ccExchangeRouterInstance.setRelay(
            relay.address
        )
        tx.wait(1)
        console.log("set relay in CCexchange router: ", tx.hash)
    } else {
        console.log("relay is already settled in CCexchange router: ")
    }

    

    // set relay in instant router
    const instantRouter = await deployments.get("InstantRouter")
    const instantRouterFactory = await ethers.getContractFactory("InstantRouter")
    const instantRouterInstance = await instantRouterFactory.attach(
        instantRouter.address
    )

    const checkRelayInInstantRouter = await instantRouterInstance.relay()

    if (checkRelayInInstantRouter != relay.address) {
        tx = await instantRouterInstance.setRelay(
            relay.address
        )
        tx.wait(1)
        console.log("set relay in instant router: ", tx.hash)
    } else {
        console.log("relay is already settled in instant router")
    }


};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
