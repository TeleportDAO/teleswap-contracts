import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("Set instant router in cc transfer...")

    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const instantRouter = await deployments.get("InstantRouter")

    const ccTransferRouterFactory = await ethers.getContractFactory("CCTransferRouter");
    const ccTransferRouterInstance = await ccTransferRouterFactory.attach(
        ccTransferRouter.address
    );

    const setInstantRouterTx = await ccTransferRouterInstance.setInstantRouter(
        instantRouter.address
    )

    await setInstantRouterTx.wait(1)

    log("...Set instant router in cc transfer")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];