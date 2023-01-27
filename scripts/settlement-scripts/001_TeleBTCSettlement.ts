import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("TeleBTC settlement...")

    const teleBTC = await deployments.get("TeleBTC")
    const lockersProxy = await deployments.get("LockersProxy")


    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    const isLockerMinter = await teleBTCInstance.minters(
        lockersProxy.address
    )

    if (!isLockerMinter) {
        const addLockerAsMinter = await teleBTCInstance.addMinter(
            lockersProxy.address
        )

        await addLockerAsMinter.wait(1)
        console.log("add locker as minter: ", addLockerAsMinter.hash)
    } else {
        console.log("locker is already a minter")
    }

    const isLockerBurner = await teleBTCInstance.burners(
        lockersProxy.address
    )

    if (!isLockerBurner) {
        const addLockerAsBurner = await teleBTCInstance.addBurner(
            lockersProxy.address
        )

        await addLockerAsBurner.wait(1)
        console.log("add locker as burner: ", addLockerAsBurner.hash)
    } else {
        console.log("locker is already a burner")
    }

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
