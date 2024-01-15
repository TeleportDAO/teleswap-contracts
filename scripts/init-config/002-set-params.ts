import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;

    const ZERO_ADD = "0x0000000000000000000000000000000000000000";

    const lockersLib = await deployments.get("LockersLib");
    const lockersProxy = await deployments.get("LockersProxy");
    const teleBTC = await deployments.get("TeleBTCProxy");
    const priceOracle = await deployments.get("PriceOracle");
    const ccTransferRouterProxy = await deployments.get("CcTransferRouterProxy");
    const burnRouterProxy = await deployments.get("BurnRouterProxy");
    const burnRouterLib = await deployments.get("BurnRouterLib");
    const ccExchangeRouterProxy = await deployments.get("CcExchangeRouterProxy");
    const exchangeConnector = await deployments.get("UniswapV2Connector");

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set teleBTC in BurnRouter ...")

    const burnRouterLogicFactory = await ethers.getContractFactory(
        "BurnRouterLogic",
        {
            libraries: {
                BurnRouterLib: burnRouterLib.address
            }
        }
    );
    const burnRouterProxyInstance = await burnRouterLogicFactory.attach(
        burnRouterProxy.address
    );

    const _teleBTC = await burnRouterProxyInstance.teleBTC()

    if (_teleBTC != teleBTC.address) {
        const setTeleBTCTx = await burnRouterProxyInstance.setTeleBTC(
            teleBTC.address
        )
        await setTeleBTCTx.wait(1)
        console.log("Set teleBTC in BurnRouter: ", setTeleBTCTx.hash)
    } else {
        console.log("teleBTC is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set ExchangeConnector in CcExchangeRouterProxy ...")

    const ccExchangeRouterLogicFactory = await ethers.getContractFactory("CcExchangeRouterLogic");
    const ccExchangeRouterProxyInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterProxy.address
    );
    const exchangeAppId = config.get("cc_exchange.app_id")

    const _exchangeConnector = await ccExchangeRouterProxyInstance.exchangeConnector(exchangeAppId)

    if (_exchangeConnector != exchangeConnector.address) {
        const setConnectorAndAppIdTx = await ccExchangeRouterProxyInstance.setExchangeConnector(
            exchangeAppId,
            exchangeConnector.address
        )
        await setConnectorAndAppIdTx.wait(1)
        console.log("Set ExchangeConnector in CcExchangeRouterProxy: ", setConnectorAndAppIdTx.hash)
    } else {
        console.log("ExchangeConnector is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set teleBTC in Locker...")

    const lockersLogicFactory = await ethers.getContractFactory(
        "LockersLogic",
        {
            libraries: {
                LockersLib: lockersLib.address
            }
        }
    );
    const lockersInstance = await lockersLogicFactory.attach(
        lockersProxy.address
    );

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set teleBTC in Lockers ...")

    if (await lockersInstance.teleBTC() != teleBTC.address) {
        const setTeleBTCTx = await lockersInstance.setTeleBTC(
            teleBTC.address
        )
        await setTeleBTCTx.wait(1)
        console.log("Set teleBTC in locker: ", setTeleBTCTx.hash)
    } else {
        console.log("teleBTC is already set")
    }

    const isCCTransferMinter = await lockersInstance.isMinter(
        ccTransferRouterProxy.address
    )

    if (!isCCTransferMinter) {
        const addCCTransferAsMinter = await lockersInstance.addMinter(
            ccTransferRouterProxy.address
        )
        await addCCTransferAsMinter.wait(1)
        console.log("Added CcTransferRouterProxy as minter: ", addCCTransferAsMinter.hash)
    } else {
        console.log("CcTransferRouterProxy is already minter")
    }

    const isCCExchangeMinter = await lockersInstance.isMinter(
        ccExchangeRouterProxy.address
    )

    if (!isCCExchangeMinter) {
        const addCCExchangeAsMinter = await lockersInstance.addMinter(
            ccExchangeRouterProxy.address
        )

        await addCCExchangeAsMinter.wait(1)
        console.log("Added CcExchangeRouterProxy as minter: ", addCCExchangeAsMinter.hash)
    } else {
        console.log("CcExchangeRouterProxy is already minter")
    }

    const isCCBurnerBurner = await lockersInstance.isBurner(
        burnRouterProxy.address
    )

    if (!isCCBurnerBurner) {
        const addCCBurnerAsBurner = await lockersInstance.addBurner(
            burnRouterProxy.address
        )

        await addCCBurnerAsBurner.wait(1)
        console.log("Added BurnRouterProxy as burner: ", addCCBurnerAsBurner.hash)
    } else {
        console.log("BurnRouterProxy is already burner")
    }
    
    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set PriceOracle in Lockers ...")

    const _priceOracleAddress = await lockersInstance.priceOracle()

    if (_priceOracleAddress.toLowerCase() != priceOracle.address.toLowerCase()) {
        const addPriceOracle = await lockersInstance.setPriceOracle(
            priceOracle.address
        )
        await addPriceOracle.wait(1)
        console.log("Set PriceOracle in Lockers: ", addPriceOracle.hash)
    } else {
        console.log("PriceOracle is already set")
    }
    
    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set BurnRouterProxy in Lockers ...")

    const burnRouterProxyAddress = await lockersInstance.ccBurnRouter()

    if (burnRouterProxyAddress != burnRouterProxy.address) {
        const addCCBurnRouter = await lockersInstance.setCCBurnRouter(
            burnRouterProxy.address
        )

        await addCCBurnRouter.wait(1)
        console.log("Set BurnRouterProxy in Lockers: ", addCCBurnRouter.hash)
    } else {
        console.log("BurnRouterProxy is already set")
    }
    
    logger.color('blue').log("-------------------------------------------------")

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set LockersProxy as minter and burner in teleBTC ...")

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

    const wrappedNativeToken = config.get("wrapped_native_token")
    const nativeTokenUSDOracle = config.get("chain_link_oracles.native_token_usd");
    
    let tx;
    const checkNativeTokenUSDTx = await priceOracleInstance.ChainlinkPriceProxy(
        wrappedNativeToken
    )

    if (checkNativeTokenUSDTx != nativeTokenUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            wrappedNativeToken,
            nativeTokenUSDOracle
        )
        tx.wait(1)
        console.log("Set NativeToken/USD in PriceOracle: ", tx.hash)
    } else {
        console.log("NativeToken/USD is already set")
    }
    
    const ONE_ADD = "0x0000000000000000000000000000000000000001"
    const checkNativeTokenUSDTx2 = await priceOracleInstance.ChainlinkPriceProxy(
        ONE_ADD
    )

    if (checkNativeTokenUSDTx2 != nativeTokenUSDOracle) {
        tx = await priceOracleInstance.setPriceProxy(
            ONE_ADD,
            nativeTokenUSDOracle
        )
        tx.wait(1)
        console.log("Set NativeToken/USD (ONE_ADD) in PriceOracle: ", tx.hash)
    } else {
        console.log("NativeToken/USD (ONE_ADD) is already set")
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
