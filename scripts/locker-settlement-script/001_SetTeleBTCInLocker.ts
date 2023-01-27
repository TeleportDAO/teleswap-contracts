import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
import config from 'config'
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set teleBTC in Locker...")

    const one = BigNumber.from(10).pow(18).mul(1)

    const lockersLib = await deployments.get("LockersLib")
    const lockersProxy = await deployments.get("LockersProxy")

    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const ccExchangeRouter = await deployments.get("CCExchangeRouter")
    const ccBurnRouter = await deployments.get("CCBurnRouter")

    const teleDAOToken = await deployments.get("ERC20")
    const teleBTC = await deployments.get("TeleBTC")
    const exchangeConnector = await deployments.get("UniswapV2Connector")
    const priceOracle = await deployments.get("PriceOracle")
    const minTDTLockedAmount = 0;

    const minNativeLockedAmount = config.get("lockers_contract.minimum_native_locked_amount");
    const collateralRatio = config.get("lockers_contract.collateral_ratio");
    const liquidationRatio = config.get("lockers_contract.liquidation_ratio");
    const lockerPercentageFee = config.get("lockers_contract.locker_percentage_fee");
    const priceWithDiscountRatio = config.get("lockers_contract.price_with_discount_ratio");
    const minLeavingIntervalTime = config.get("lockers_contract.minimum_leaving_interval_time");

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


    const teleDAOTokenAddress = await lockersInstance.TeleportDAOToken()

    if (teleDAOTokenAddress == "0x0000000000000000000000000000000000000000") {
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
        console.log("initialize locker: ", initializeTx.hash)
    } else {
        console.log("locker is already initialized")
    }

    // const setTeleBTCTx = await lockersInstance.setTeleBTC(
    //     teleBTC.address
    // )

    // await setTeleBTCTx.wait(1)
    // console.log("set telebtc in locker: ", setTeleBTCTx.hash)


    const isCCTransferMinter = await lockersInstance.isMinter(
        ccTransferRouter.address
    )

    if (!isCCTransferMinter) {
        const addCCTransferAsMinter = await lockersInstance.addMinter(
            ccTransferRouter.address
        )

        await addCCTransferAsMinter.wait(1)
        console.log("add CC transfer router as minter: ", addCCTransferAsMinter.hash)
    } else {
        console.log("CC transfer router is already a minter")
    }

    const isCCExchangeMinter = await lockersInstance.isMinter(
        ccExchangeRouter.address
    )

    if (!isCCExchangeMinter) {
        const addCCExchangeAsMinter = await lockersInstance.addMinter(
            ccExchangeRouter.address
        )

        await addCCExchangeAsMinter.wait(1)
        console.log("add CC exchange router as minter: ", addCCExchangeAsMinter.hash)
    } else {
        console.log("CC exchange router is already a minter")
    }


    const isCCBurnerBurner = await lockersInstance.isBurner(
        ccBurnRouter.address
    )

    if (!isCCBurnerBurner) {
        const addCCBurnerAsBurner = await lockersInstance.addBurner(
            ccBurnRouter.address
        )

        await addCCBurnerAsBurner.wait(1)
        console.log("add CC burn router router as burner: ", addCCBurnerAsBurner.hash)
    } else {
        console.log("CC burn router router is already a burner: ")
    }


    // const ccBurnerRouterFromContract = await lockersInstance.ccBurnRouter()

    // if (ccBurnerRouterFromContract != ccBurnRouter.address) {
    //     const addCCBurnRouter = await lockersInstance.setCCBurnRouter(
    //         ccBurnRouter.address
    //     )

    //     await addCCBurnRouter.wait(1)
    //     console.log("add CC burn router in locker: ", addCCBurnRouter.hash)
    // }
    
    logger.color('blue').log("-------------------------------------------------")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
