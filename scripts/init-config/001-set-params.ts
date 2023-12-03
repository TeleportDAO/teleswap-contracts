import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;
    const ZERO_ADD = "0x0000000000000000000000000000000000000000";

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set LockersProxy as minter and burner in teleBTC ...")

    const teleBTC = await deployments.get("TeleBTCProxy")
    const lockersProxy = await deployments.get("LockersProxy")

    const teleBTCLogicFactory = await ethers.getContractFactory("TeleBTCLogic");
    const teleBTCInstance = await teleBTCLogicFactory.attach(
        teleBTC.address
    );

    const isLockersProxyMinter = await teleBTCInstance.minters(
        lockersProxy.address
    )

    if (!isLockersProxyMinter) {
        const addLockerAsMinter = await teleBTCInstance.addMinter(
            lockersProxy.address
        )
        await addLockerAsMinter.wait(1)
        console.log("Added LockersProxy as minter: ", addLockerAsMinter.hash)
    } else {
        console.log("LockersProxy is already minter")
    }

    const isLockersProxyBurner = await teleBTCInstance.burners(
        lockersProxy.address
    )

    if (!isLockersProxyBurner) {
        const addLockerAsBurner = await teleBTCInstance.addBurner(
            lockersProxy.address
        )

        await addLockerAsBurner.wait(1)
        console.log("Added LockersProxy as burner: ", addLockerAsBurner.hash)
    } else {
        console.log("LockersProxy is already burner")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set ExchangeRouter in ExchangeConnector ...")

    const uniswapV2Router02 = config.get("uniswap_v2_router_02")
    const uniswapV2Connector = await deployments.get("UniswapV2Connector")

    const uniswapV2ConnectorFactory = await ethers.getContractFactory("UniswapV2Connector");
    const uniswapV2ConnectorInstance = await uniswapV2ConnectorFactory.attach(
        uniswapV2Connector.address
    );

    const _exchangeRouter = await uniswapV2ConnectorInstance.exchangeRouter();
    if (uniswapV2Router02 != _exchangeRouter) {
        const setExchangeRouterTx = await uniswapV2ConnectorInstance.setExchangeRouter(
            uniswapV2Router02
        )
        await setExchangeRouterTx.wait(1)
        console.log("Set ExchangeRouter in ExchangeConnector", setExchangeRouterTx.hash)
    } else {
        console.log("ExchangeRouter is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set ExchangeRouter in PriceOracle ...")

    const priceOracle = await deployments.get("PriceOracle")
    const priceOracleFactory = await ethers.getContractFactory("PriceOracle");
    const priceOracleInstance = await priceOracleFactory.attach(
        priceOracle.address
    );

    const exchangeConnectorAddress = await priceOracleInstance.exchangeConnector(
        uniswapV2Router02
    )

    if (exchangeConnectorAddress == ZERO_ADD) {
        const addExchangeTx = await priceOracleInstance.addExchangeConnector(
            uniswapV2Router02,
            uniswapV2Connector.address
        );
        await addExchangeTx.wait(1)
        console.log("Set ExchangeRouter in PriceOracle: ", addExchangeTx.hash)
    } else {
        console.log("ExchangeRouter is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set PriceProxies to PriceOracle ...")

    const wrappedMatic = config.get("wrapped_native_token")
    const maticUSDOracle = config.get("chain_link_oracles.matic_usd");
    
    let tx;
    const checkMaticUSDTx = await priceOracleInstance.ChainlinkPriceProxy(
        wrappedMatic
    )

    if (checkMaticUSDTx != maticUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            wrappedMatic,
            maticUSDOracle
        )
        tx.wait(1)
        console.log("Set MATIC/USD in PriceOracle: ", tx.hash)
    } else {
        console.log("MATIC/USD is already set")
    }
    
    const ONE_ADD = "0x0000000000000000000000000000000000000001"
    const checkMaticUSDTx2 = await priceOracleInstance.ChainlinkPriceProxy(
        ONE_ADD
    )

    if (checkMaticUSDTx2 != maticUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            ONE_ADD,
            maticUSDOracle
        )
        tx.wait(1)
        console.log("Set MATIC/USD (ONE_ADD) in PriceOracle: ", tx.hash)
    } else {
        console.log("MATIC/USD (ONE_ADD) is already set")
    }

    // const tBTC = await deployments.get("TeleBTC")
    const tBTC = await deployments.get("TeleBTCProxy")
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
        console.log("Set BTC/USD in PriceOracle: ", tx.hash)
    } else {
        console.log("BTC/USD is already set")
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
        console.log("Set USDT/USD in PriceOracle: ", tx.hash)
    } else {
        console.log("USDT/USD is already set")
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
        console.log("Set USDC/USD in PriceOracle: ", tx.hash)
    } else {
        console.log("USDC/USD is already set")
    }
    
};

export default func;