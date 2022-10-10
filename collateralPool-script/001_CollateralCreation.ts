import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("CreateCollateralPoolWithFactory...")

    const collateralPoolFactoryInstance = await deployments.get("CollateralPoolFactory")


    const erc20asDotInstance = await ethers.getContractFactory("ERC20AsDot");

    const isLockerMinter = await teleBTCInstance.minters(
        lockersProxy.address
    )

    if (!isLockerMinter) {
        const addLockerAsMinter = await teleBTCInstance.addMinter(
            lockersProxy.address
        )

        await addLockerAsMinter.wait(1)
    }

    const isLockerBurner = await teleBTCInstance.burners(
        lockersProxy.address
    )

    if (!isLockerBurner) {
        const addLockerAsBurner = await teleBTCInstance.addBurner(
            lockersProxy.address
        )

        await addLockerAsBurner.wait(1)
    }

    log("CreateCollateralPoolWithFactory...")
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
