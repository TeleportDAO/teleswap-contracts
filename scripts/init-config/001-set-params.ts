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

    const teleBTC = await deployments.get("TeleBTC")
    const lockersProxy = await deployments.get("LockersProxy")

    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
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
    logger.color('blue').bold().log("Set Exchange Router in price oracle...")

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
    logger.color('blue').bold().log("Set teleBTC in BurnRouter ...")

    const burnRouterProxy = await deployments.get("BurnRouterProxy")

    const burnRouterLib = await deployments.get("BurnRouterLib")
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
    logger.color('blue').bold().log("Set InstantRouter in CcTransferRouterProxy ...")

    const ccTransferRouterProxy = await deployments.get("CcTransferRouterProxy")
    const instantRouter = await deployments.get("InstantRouter")

    const ccTransferRouterLogicFactory = await ethers.getContractFactory("CcTransferRouterLogic");
    const ccTransferRouterProxyInstance = await ccTransferRouterLogicFactory.attach(
        ccTransferRouterProxy.address
    );

    const _instantRouter = await ccTransferRouterProxyInstance.instantRouter()

    if (_instantRouter != instantRouter.address) {
        const setInstantRouterTx = await ccTransferRouterProxyInstance.setInstantRouter(
            instantRouter.address
        )
        await setInstantRouterTx.wait(1)
        console.log("Set InstantRouter in CcTransferRouterProxy: ", setInstantRouterTx.hash)
    } else {
        console.log("InstantRouter is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set InstantRouter in CcExchangeRouterProxy ...")

    const ccExchangeRouterProxy = await deployments.get("CCExchangeRouter")
    const exchangeConnector = await deployments.get("UniswapV2Connector")

    const ccExchangeRouterLogicFactory = await ethers.getContractFactory("CcExchangeRouterLogic");
    const ccExchangeRouterProxyInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterProxy.address
    );
    
    if (_instantRouter != instantRouter.address) {
        const setInstantRouterTx = await ccExchangeRouterProxyInstance.setInstantRouter(
            instantRouter.address
        )
        await setInstantRouterTx.wait(1)
        console.log("Set InstantRouter in CcExchangeRouterProxy: ", setInstantRouterTx.hash)
    } else {
        console.log("InstantRouter is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set ExchangeConnector in CcExchangeRouterProxy ...")

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
    logger.color('blue').bold().log("Set InstantPool in InstantRouter ...")

    const instantPool = await deployments.get("InstantPool")

    const instantRouterFactory = await ethers.getContractFactory("InstantRouter");
    const instantRouterInstance = await instantRouterFactory.attach(
        instantRouter.address
    );

    const _instantPool = await instantRouterInstance.teleBTCInstantPool()

    if (_instantPool != instantPool.address) {
        const setInstantPoolTx = await instantRouterInstance.setTeleBTCInstantPool(
            instantPool.address
        )
        await setInstantPoolTx.wait(1)
        console.log("Set InstantPool in InstantRouter: ", setInstantPoolTx.hash)
    } else {
        console.log("InstantPool is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set InstantRouter in InstantPool ...")

    const instantPoolFactory = await ethers.getContractFactory("InstantPool");
    const instantPoolInstance = await instantPoolFactory.attach(
        instantPool.address
    );
    
    if (_instantRouter != instantRouter.address) {
        const setInstantRouterTx = await instantPoolInstance.setInstantRouter(
            instantRouter.address
        )
        await setInstantRouterTx.wait(1)
        console.log("Set InstantRouter in InstantPool: ", setInstantRouterTx.hash)
    } else {
        console.log("InstantRouter is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("ADD PriceProxies to PriceOracle ...")

    const wrappedMatic = config.get("wrapped_matic")
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
    
    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Create USDC collateral pool ...")

    const collateralPoolFactoryContract = await deployments.get("CollateralPoolFactory")
    const collateralPoolFactoryFactory = await ethers.getContractFactory("CollateralPoolFactory")
    const collateralPoolFactoryInstance = await collateralPoolFactoryFactory.attach(
        collateralPoolFactoryContract.address
    )
    const usdcCollateralRatio = config.get("collateral_pools.usdc_collateral_ratio");

    let hasCollateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
        usdc
    )

    if (hasCollateralPoolAddress == ZERO_ADD) {
        const createCollateralPoolTx = await collateralPoolFactoryInstance.createCollateralPool(
            usdc,
            usdcCollateralRatio
        )
        await createCollateralPoolTx.wait(1)
        console.log("Created USDC collateral pool: ", createCollateralPoolTx.hash)
    
    } else {
        console.log("USDC collateral pool already exists")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Create USDtT collateral pool ...")

    hasCollateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
        usdt
    )
    const usdtCollateralRatio = config.get("collateral_pools.usdt_collateral_ratio");

    if (hasCollateralPoolAddress == ZERO_ADD) {
        const createCollateralPoolTx = await collateralPoolFactoryInstance.createCollateralPool(
            usdt,
            usdtCollateralRatio
        )
        await createCollateralPoolTx.wait(1)
        console.log("Created USDT collateral pool: ", createCollateralPoolTx.hash)
    
    } else {
        console.log("USDT collateral pool already exists")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Create WMATIC collateral pool")

    hasCollateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
        wrappedMatic
    )
    const wmaticCollateralRatio = config.get("collateral_pools.wmatic_collateral_ratio");

    if (hasCollateralPoolAddress == "0x0000000000000000000000000000000000000000") {
        const createCollateralPoolTx = await collateralPoolFactoryInstance.createCollateralPool(
            wrappedMatic,
            wmaticCollateralRatio
        )
        await createCollateralPoolTx.wait(1)
        console.log("Created WMATIC collateral pool: ", createCollateralPoolTx.hash)
    
    } else {
        console.log("WMATIC collateral pool already exists")
    }

};

export default func;