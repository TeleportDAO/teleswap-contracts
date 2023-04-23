import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config'
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    let tx

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("add price proxies to price oracle...")

    const priceOracle = await deployments.get("PriceOracle")
    const priceOracleFactory = await ethers.getContractFactory("PriceOracle")
    const priceOracleInstance = await priceOracleFactory.attach(
        priceOracle.address
    )

    const wrappedMatic = config.get("wrapped_matic")
    const maticUSDOracle = config.get("chain_link_oracles.matic_usd");

    const checkMaticUSDTx = await priceOracleInstance.ChainlinkPriceProxy(
        wrappedMatic
    )

    if (checkMaticUSDTx != maticUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            wrappedMatic,
            maticUSDOracle
        )
        tx.wait(1)
        console.log("set matic/usd in pricie oracle: ", tx.hash)
    } else {
        console.log("matic/usd is already settled in price oracle")
    }
    

    const oneAddress = "0x0000000000000000000000000000000000000001"
    const checkMaticUSDTx2 = await priceOracleInstance.ChainlinkPriceProxy(
        oneAddress
    )

    if (checkMaticUSDTx2 != maticUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            oneAddress,
            maticUSDOracle
        )
        tx.wait(1)
        console.log("set matic/usd in pricie oracle: ", tx.hash)
    } else {
        console.log("matic/usd (one_address) is already settled in pricie oracle: ")
    }

    const tBTC = await deployments.get("TeleBTC")
    const btcUSDOracle = config.get("chain_link_oracles.btc_usd");

    const checkBitcoinUSDTx = await priceOracleInstance.ChainlinkPriceProxy(
        tBTC.address
    )

    if (checkBitcoinUSDTx != btcUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            tBTC.address,
            btcUSDOracle
        )
        tx.wait(1)
        console.log("set btc/usd in pricie oracle: ", tx.hash)
    } else {
        console.log("btc/usd is already settled in pricie oracle")
    }

    const usdt = config.get("usdt_token")
    const usdtUSDOracle = config.get("chain_link_oracles.usdt_usd");

    const checkUsdtUSDTx = await priceOracleInstance.ChainlinkPriceProxy(
        usdt
    )

    if (checkUsdtUSDTx != usdtUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            usdt,
            usdtUSDOracle
        )
        tx.wait(1)
        console.log("set usdt/usd in pricie oracle: ", tx.hash)
    } else {
        console.log("usdt/usd is already settled in pricie oracle")
    }

    const usdc = config.get("usdc_token")
    const usdcUSDOracle = config.get("chain_link_oracles.usdc_usd");

    const checkUsdcUSDTx = await priceOracleInstance.ChainlinkPriceProxy(
        usdc
    )

    if (checkUsdcUSDTx != usdcUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            usdc,
            usdcUSDOracle
        )
        tx.wait(1)
        console.log("set usdc/usd in pricie oracle: ", tx.hash)
    } else {
        console.log("usdc/usd is already settled in pricie oracle")
    }
    

    logger.color('blue').log("-------------------------------------------------")
};

export default func;
