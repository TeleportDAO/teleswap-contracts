import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
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

    // TODO: get from config
    const minNativeLockedAmount = one.mul(6);
    const collateralRatio = 13000;
    const liquidationRatio = 10500;
    const lockerPercentageFee = 15;
    const priceWithDiscountRatio = 9000;
    const minLeavinngIntervalTime = 1000;

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
