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

    const priceOracle = await deployments.get("PriceOracle")

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


    const priceOracleAddress = await lockersInstance.priceOracle()

    if (priceOracleAddress != priceOracle.address) {
        const addPriceOracle = await lockersInstance.setPriceOracle(
            priceOracle.address
        )

        await addPriceOracle.wait(1)
        console.log("add price oracle in lockers proxy contract: ", addPriceOracle.hash)
    } else {
        console.log("price oracle is already settled in lockers proxy contract")
    }
    
    logger.color('blue').log("-------------------------------------------------")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
