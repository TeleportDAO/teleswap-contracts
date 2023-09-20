import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;

    const lockersLib = await deployments.get("LockersLib")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")
    const priceOracle = await deployments.get("PriceOracle")
    const ccTransferRouterProxy = await deployments.get("CcTransferRouterProxy")
    const instantRouter = await deployments.get("InstantRouter")
    const burnRouterProxy = await deployments.get("BurnRouterProxy")
    const burnRouterLib = await deployments.get("BurnRouterLib")
    const ccExchangeRouterProxy = await deployments.get("CcExchangeRouterProxy")
    const exchangeConnector = await deployments.get("UniswapV2Connector")

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
    logger.color('blue').bold().log("Set InstantRouter in CcTransferRouterProxy ...")

    const ccTransferRouterLogicFactory = await ethers.getContractFactory("CcTransferRouterLogic");
    const ccTransferRouterProxyInstance = await ccTransferRouterLogicFactory.attach(
        ccTransferRouterProxy.address
    );

    const _instantRouter = await ccTransferRouterProxyInstance.instantRouter()

    if (_instantRouter.toLowerCase() != instantRouter.address) {
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

    const ccExchangeRouterLogicFactory = await ethers.getContractFactory("CcExchangeRouterLogic");
    const ccExchangeRouterProxyInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterProxy.address
    );
    
    if (_instantRouter.toLowerCase() != instantRouter.address) {
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

    if (_priceOracleAddress.toLowerCase() != priceOracle.address) {
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

};

export default func;
