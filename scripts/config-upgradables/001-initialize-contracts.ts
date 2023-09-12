import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;
    const ZERO_ADD = "0x0000000000000000000000000000000000000000";

    const lockersLib = await deployments.get("LockersLib")
    const lockersLogic = await deployments.get("LockersLogic")
    const ccBurnRouter = await deployments.get("CCBurnRouter")
    const teleDAOToken = await deployments.get("ERC20");
    const teleBTC = await deployments.get("TeleBTC");
    const exchangeConnector = await deployments.get("UniswapV2Connector");
    const priceOracle = await deployments.get("PriceOracle");
    const ccTransferRouterLogic = await deployments.get("CcTransferRouterLogic");
    const ccTransferRouterProxy = await deployments.get("CcTransferRouterProxy");
    const lockersProxy = await deployments.get("LockersProxy");
    const burnRouterLib = await deployments.get("BurnRouterLib");
    const burnRouterLogic = await deployments.get("BurnRouterLogic");
    const burnRouterProxy = await deployments.get("BurnRouterProxy");
    const ccExchangeRouterLogic = await deployments.get("CcExchangeRouterLogic");
    const ccExchangeRouterProxy = await deployments.get("CcExchangeRouterProxy");

    const minTDTLockedAmount = 0;
    const startingBlockHeight = config.get("starting_block_height");
    const protocolPercentageFee = config.get("cc_transfer.protocol_percentage_fee");
    const chainId = config.get("chain_id");
    const appId = config.get("cc_transfer.app_id");
    const treasuryAddress = config.get("treasury");
    const bitcoinRelay = config.get("bitcoin_relay");
    const minNativeLockedAmount = config.get("lockers_contract.minimum_native_locked_amount");
    const collateralRatio = config.get("lockers_contract.collateral_ratio");
    const liquidationRatio = config.get("lockers_contract.liquidation_ratio");
    const lockerPercentageFee = config.get("lockers_contract.locker_percentage_fee");
    const priceWithDiscountRatio = config.get("lockers_contract.price_with_discount_ratio");
    const slasherPercentageReward = config.get("cc_burn.slasher_percentage_reward");
    const bitcoinFee = config.get("cc_burn.bitcoin_fee");
    const transferDeadLine = config.get("cc_burn.transfer_deadLine");
    const chainID = config.get("chain_id");

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set LockersLogic in LockersProxy ...")

    const lockersProxyFactory = await ethers.getContractFactory("LockersProxy");
    const lockersProxyInstance = await lockersProxyFactory.attach(
        lockersProxy.address
    );

    const _lockersLogic = await lockersProxyInstance.implementation()

    if (_lockersLogic != lockersLogic.address) {
        const setLogicTx = await lockersProxyInstance.upgradeTo(
            lockersLogic.address
        )
        await setLogicTx.wait(1)
        console.log("Set LockersLogic in LockersProxy: ", setLogicTx.hash)
    } else {
        console.log("LockersLogic is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set CcTransferRouterLogic in CcTransferRouterProxy ...")

    const ccTransferRouterProxyFactory = await ethers.getContractFactory("CcTransferRouterProxy");
    const ccTransferRouterProxyInstance = await ccTransferRouterProxyFactory.attach(
        ccTransferRouterProxy.address
    );

    const _ccTransferRouterLogic = await lockersProxyInstance.implementation()

    if (_ccTransferRouterLogic != ccTransferRouterProxy.address) {
        const setTx = await ccTransferRouterProxyInstance.upgradeTo(
            ccTransferRouterProxy.address
        )
        await setTx.wait(1)
        console.log("Set CcTransferRouterLogic in CcTransferRouterProxy: ", setTx.hash)
    } else {
        console.log("CcTransferRouterLogic is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set CcExchangeRouterLogic in CcExchangeRouterProxy ...")

    const ccExchangeRouterProxyFactory = await ethers.getContractFactory("CcExchangeRouterProxy");
    const ccExchangeRouterProxyInstance = await ccExchangeRouterProxyFactory.attach(
        ccExchangeRouterProxy.address
    );

    const _ccExchangeRouterLogic = await lockersProxyInstance.implementation()

    if (_ccExchangeRouterLogic != ccExchangeRouterProxy.address) {
        const setTx = await ccExchangeRouterProxyInstance.upgradeTo(
            ccExchangeRouterProxy.address
        )
        await setTx.wait(1)
        console.log("Set CcExchangeRouterLogic in CcExchangeRouterProxy: ", setTx.hash)
    } else {
        console.log("CcExchangeRouterLogic is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set BurnRouterLogic in BurnRouterProxy ...")

    const burnRouterProxyFactory = await ethers.getContractFactory("burnRouterProxy");
    const burnRouterProxyInstance = await burnRouterProxyFactory.attach(
        burnRouterProxy.address
    );

    const _burnRouterLogic = await lockersProxyInstance.implementation()

    if (_burnRouterLogic != ccExchangeRouterProxy.address) {
        const setTx = await burnRouterProxyInstance.upgradeTo(
            burnRouterProxy.address
        )
        await setTx.wait(1)
        console.log("Set BurnRouterLogic in BurnRouterProxy: ", setTx.hash)
    } else {
        console.log("BurnRouterLogic is already set")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Initialize Lockers ...")

    const lockersLogicFactory = await ethers.getContractFactory(
        "LockersLogic",
        {
            libraries: {
                LockersLib: lockersLib.address
            }
        }
    );
    const lockersInstance = await lockersLogicFactory.attach(
        lockersLogic.address
    );

    const teleDAOTokenAddress = await lockersInstance.TeleportDAOToken()

    if (teleDAOTokenAddress == ZERO_ADD) {
        const initializeTx = await lockersInstance.initialize(
            teleBTC.address,
            teleDAOToken.address,
            exchangeConnector.address,
            priceOracle.address,
            ccBurnRouter.address,
            minTDTLockedAmount,
            minNativeLockedAmount,
            collateralRatio,
            liquidationRatio,
            lockerPercentageFee,
            priceWithDiscountRatio
        )
        await initializeTx.wait(1)
        console.log("Initialized LockersLogic: ", initializeTx.hash)
    } else {
        console.log("LockersLogic is already initialized")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Initialize CcTransferRouter ...")

    const ccTransferRouterLogicFactory = await ethers.getContractFactory(
        "CcTransferRouterLogic"
    );
    const ccTransferRouterLogicInstance = await ccTransferRouterLogicFactory.attach(
        ccTransferRouterLogic.address
    );

    let _relayProxy = await ccTransferRouterProxyInstance.relay();
    if (_relayProxy == ZERO_ADD) {
        const initializeTxProxy = await ccTransferRouterProxyInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainId,
            appId,
            bitcoinRelay,
            lockersProxy.address,
            teleBTC.address,
            treasuryAddress
        );
        await initializeTxProxy.wait(1);
        console.log("Initialized CcTransferRouterProxy: ", initializeTxProxy.hash);
    }

    let _relayLogic = await ccTransferRouterLogicInstance.relay();
    if (_relayLogic == ZERO_ADD) {
        const initializeTxLogic = await ccTransferRouterLogicInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainId,
            appId,
            bitcoinRelay,
            lockersProxy.address,
            teleBTC.address,
            treasuryAddress
        )
        await initializeTxLogic.wait(1);
        console.log("Initialized CcTransferRouterLogic: ", initializeTxLogic.hash);
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Initialize BurnRouter ...")

    const burnRouterLogicFactory = await ethers.getContractFactory(
        "BurnRouterLogic",
        {
            libraries: {
                BurnRouterLib: burnRouterLib.address
            }
        }
    );
    const burnRouterLogicInstance = await burnRouterLogicFactory.attach(
        burnRouterLogic.address
    );

    _relayProxy = await burnRouterProxyInstance.relay();
    if (_relayProxy == ZERO_ADD) {
        const initializeTxProxy = await burnRouterProxyInstance.initialize(
            startingBlockHeight,
            bitcoinRelay,
            lockersProxy.address,
            treasuryAddress,
            teleBTC.address,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        )
        await initializeTxProxy.wait(1);
        console.log("Initialized BurnRouterProxy: ", initializeTxProxy.hash);
    }

    _relayLogic = await burnRouterLogicInstance.relay();
    if (_relayLogic == ) {
        const initializeTxLogic = await burnRouterLogicInstance.initialize(
            startingBlockHeight,
            bitcoinRelay,
            lockersProxy.address,
            treasuryAddress,
            teleBTC.address,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        )
        await initializeTxLogic.wait(1);
        console.log("Initialized BurnRouterLogic: ", initializeTxLogic.hash);
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Initialize CcExchangeRouter ...")

    const ccExchangeRouterLogicFactory = await ethers.getContractFactory(
        "CcExchangeRouterLogic"
    );
    const ccExchangeRouterLogicInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterLogic.address
    );

    _relayProxy = await ccExchangeRouterProxyInstance.relay();
    if (_relayProxy == ZERO_ADD) {
        const initializeTxProxy = await ccExchangeRouterProxyInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainID,
            lockersProxy.address,
            bitcoinRelay,
            teleBTC.address,
            treasuryAddress
        );
        await initializeTxProxy.wait(1);
        console.log("Initialize CcExchangeRouterProxy: ", initializeTxProxy.hash);
    }

    _relayLogic = await ccExchangeRouterLogicInstance.relay();
    if (_relayLogic == ZERO_ADD) {
        const initializeTxLogic = await ccExchangeRouterLogicInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainID,
            lockersProxy.address,
            bitcoinRelay,
            teleBTC.address,
            treasuryAddress
        )
        await initializeTxLogic.wait(1);
        console.log("Initialize CcExchangeRouterLogic: ", initializeTxLogic.hash);
    }

};

export default func;