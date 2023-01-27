import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();
    let tx

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("add price proxies to price oracle...")

    const priceOracle = await deployments.get("PriceOracle")
    const priceOracleFactory = await ethers.getContractFactory("PriceOracle")
    const priceOracleInstance = await priceOracleFactory.attach(
        priceOracle.address
    )

    // TODO: get from config
    const wEth = await deployments.get("WETH")
    const maticUSDOracle = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";
    tx = await priceOracleInstance.setPriceProxy(
        wEth.address,
        maticUSDOracle
    )
    tx.wait(1)
    console.log("set matic/usd in pricie oracle: ", tx.hash)

    const oneAddress = "0x0000000000000000000000000000000000000001"
    tx = await priceOracleInstance.setPriceProxy(
        oneAddress,
        maticUSDOracle
    )
    tx.wait(1)
    console.log("set matic/usd in pricie oracle: ", tx.hash)

    // TODO: get from config
    const tBTC = await deployments.get("TeleBTC")
    const btcUSDOracle = "0x007A22900a3B98143368Bd5906f8E17e9867581b";
    tx = await priceOracleInstance.setPriceProxy(
        tBTC.address,
        btcUSDOracle
    )
    tx.wait(1)
    console.log("set btc/usd in pricie oracle: ", tx.hash)

    logger.color('blue').log("-------------------------------------------------")
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
