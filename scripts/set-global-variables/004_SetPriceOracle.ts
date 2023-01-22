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
    logger.color('blue').bold().log("Set price oracle globally...")
    
    const priceOracle = await deployments.get("PriceOracle")


    // set relay in instant router
    const instantRouter = await deployments.get("InstantRouter")
    const instantRouterFactory = await ethers.getContractFactory("InstantRouter")
    const instantRouterInstance = await instantRouterFactory.attach(
        instantRouter.address
    )

    tx = await instantRouterInstance.setPriceOracle(
        priceOracle.address
    )
    tx.wait(1)
    
    console.log("set priceOracle in instant router: ", tx.hash)


};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
