import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const one = BigNumber.from(10).pow(18).mul(1)

    log("Add liquidity to instant pool...")

    const teleBTC = await deployments.get("TeleBTC")
    const instantPool = await deployments.get("InstantPool")

    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    const instantPoolFactory = await ethers.getContractFactory("InstantPool");
    const instantPoolInstance = await instantPoolFactory.attach(
        instantPool.address
    );

    const mintTeleBTCTx = await teleBTCInstance.mintTestToken()
    await mintTeleBTCTx.wait(1)

    const approveTeleBTCTx = await teleBTCInstance.approve(
        instantPool.address,
        one.mul(50)
    )
    await approveTeleBTCTx.wait(1)

    const addLiquiditylTx = await instantPoolInstance.addLiquidity(
        deployer,
        one.mul(50)
    )

    await addLiquiditylTx.wait(1)

    log("...Add liquidity to instant pool")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
