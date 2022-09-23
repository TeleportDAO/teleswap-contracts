import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("Set instant pool in instant router...")

    const instantRouter = await deployments.get("InstantRouter")
    const instantPool = await deployments.get("InstantPool")

    const instantRouterFactory = await ethers.getContractFactory("InstantRouter");
    const instantRouterInstance = await instantRouterFactory.attach(
        instantRouter.address
    );

    const setInstantPoolTx = await instantRouterInstance.setTeleBTCInstantPool(
        instantPool.address
    )

    await setInstantPoolTx.wait(1)

    log("...Set instant pool in instant router")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
