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
    logger.color('blue').bold().log("Initialize Lockers ...")

    const lockersLogicFactory = await ethers.getContractFactory(
        "LockersLogic",
        {
            libraries: {
                LockersLib: lockersLib.address
            }
        }
    );
    const lockersProxyInstance = await lockersLogicFactory.attach(
        lockersProxy.address
    );
    const lockersLogicInstance = await lockersLogicFactory.attach(
        lockersLogic.address
    );

    let _teleBtcProxy = await lockersProxyInstance.teleBTC();
    if (_teleBtcProxy == ZERO_ADD) {
        const initializeTx = await lockersProxyInstance.initialize(
            teleBTC.address,
            teleDAOToken.address,
            exchangeConnector.address,
            priceOracle.address,
            burnRouterProxy.address,
            minTDTLockedAmount,
            minNativeLockedAmount,
            collateralRatio,
            liquidationRatio,
            lockerPercentageFee,
            priceWithDiscountRatio
        )
        await initializeTx.wait(1)
        console.log("Initialized lockersProxy: ", initializeTx.hash)
    } else {
        console.log("lockersProxy is already initialized")
    }

    let _teleBtcLogic = await lockersLogicInstance.teleBTC()
    if (_teleBtcLogic == ZERO_ADD) {
        const initializeTx = await lockersLogicInstance.initialize(
            teleBTC.address,
            teleDAOToken.address,
            exchangeConnector.address,
            priceOracle.address,
            burnRouterProxy.address,
            minTDTLockedAmount,
            minNativeLockedAmount,
            collateralRatio,
            liquidationRatio,
            lockerPercentageFee,
            priceWithDiscountRatio
        )
        await initializeTx.wait(1)
        console.log("Initialized lockersLogic: ", initializeTx.hash)
    } else {
        console.log("lockersLogic is already initialized")
    }

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Initialize CcTransferRouter ...")

    const ccTransferRouterLogicFactory = await ethers.getContractFactory(
        "CcTransferRouterLogic"
    );
    const ccTransferRouterProxyInstance = await ccTransferRouterLogicFactory.attach(
        ccTransferRouterProxy.address
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
    const burnRouterProxyInstance = await burnRouterLogicFactory.attach(
        burnRouterProxy.address
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
    if (_relayLogic == ZERO_ADD) {
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
    const ccExchangeRouterProxyInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterProxy.address
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