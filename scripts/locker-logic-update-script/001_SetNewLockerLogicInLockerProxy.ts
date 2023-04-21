import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set logic in lockers proxy...")

    const lockersProxy = await deployments.get("LockersProxy")
    const lockersLogic = await deployments.get("LockersLogic")

    const lockersProxyFactory = await ethers.getContractFactory("LockersProxy");
    const lockersProxyInstance = await lockersProxyFactory.attach(
        lockersProxy.address
    );

    const checkLogicInLockersProxy = await lockersProxyInstance.implementation()

    if (checkLogicInLockersProxy != lockersLogic.address) {
        const setLogicTx = await lockersProxyInstance.upgradeTo(
            lockersLogic.address
        )
    
        await setLogicTx.wait(1)
        console.log("set logic in lockers proxy: ", setLogicTx.hash)
    } else {
        console.log("logic is already settled in lockers proxy")
    }

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
