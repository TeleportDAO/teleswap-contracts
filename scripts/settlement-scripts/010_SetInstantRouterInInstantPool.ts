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

    const instantPool = await deployments.get("InstantPool")
    const instantRouter = await deployments.get("InstantRouter")

    const instantPoolFactory = await ethers.getContractFactory("InstantPool");
    const instantPoolInstance = await instantPoolFactory.attach(
        instantPool.address
    );

    const checkInstantRouterInInstantPool = await instantPoolInstance.instantRouter()

    if (checkInstantRouterInInstantPool != instantRouter.address) {
        const setInstantRouterTx = await instantPoolInstance.setInstantRouter(
            instantRouter.address
        )
    
        await setInstantRouterTx.wait(1)
        console.log("set instant router in instant pool: ", setInstantRouterTx.hash)
    } else {
        console.log("instant router is already settled in instant pool")
    }

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
