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
    logger.color('blue').bold().log("Set instant router in CC transfer...")

    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const instantRouter = await deployments.get("InstantRouter")

    const ccTransferRouterFactory = await ethers.getContractFactory("CCTransferRouter");
    const ccTransferRouterInstance = await ccTransferRouterFactory.attach(
        ccTransferRouter.address
    );

    const checkInstantRouterInCCTransfer = await ccTransferRouterInstance.instantRouter()

    if (checkInstantRouterInCCTransfer != instantRouter.address) {
        const setInstantRouterTx = await ccTransferRouterInstance.setInstantRouter(
            instantRouter.address
        )
    
        await setInstantRouterTx.wait(1)
        console.log("set instant router in CC transfer: ", setInstantRouterTx.hash)
    } else {
        console.log("instant router is already settled in CC transfer")
    }

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
