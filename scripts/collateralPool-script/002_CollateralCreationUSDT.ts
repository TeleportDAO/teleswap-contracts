import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config'
import { BigNumber } from 'ethers';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Create collateral pool with factory and add liquidity to it...")

    const collateralPoolFactoryContract = await deployments.get("CollateralPoolFactory")
    const collateralPoolFactoryFactory = await ethers.getContractFactory("CollateralPoolFactory")
    const collateralPoolFactoryInstance = await collateralPoolFactoryFactory.attach(
        collateralPoolFactoryContract.address
    )

    const usdt = config.get("usdt_token") as string

    const hasCollateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
        usdt
    )

    if (hasCollateralPoolAddress == "0x0000000000000000000000000000000000000000") {
        const createCollateralPoolTx = await collateralPoolFactoryInstance.createCollateralPool(
            usdt,
            15000
        )
    
        await createCollateralPoolTx.wait(1)
        console.log("create usdt collateral pool: ", createCollateralPoolTx.hash)
    
    } else {
        console.log("usdt collateral pool already exists: ")
    }

    logger.color('blue').log("-------------------------------------------------")
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
