import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const teleBTC = await deployments.get("TeleBTC")
    const lockersProxy = await deployments.get("LockersProxy")


    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    const isLockerMinter = await teleBTCInstance.isMinter(
        lockersProxy.address
    )

    if (!isLockerMinter) {
        const addLockerAsMinter = await teleBTCInstance.addMinter(
            lockersProxy.address
        )

        await addLockerAsMinter.wait(1)
    }

    const isLockerBurner = await teleBTCInstance.isBurner(
        lockersProxy.address
    )

    if (!isLockerBurner) {
        const addLockerAsBurner = await teleBTCInstance.addBurner(
            lockersProxy.address
        )

        await addLockerAsBurner.wait(1)
    }
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
