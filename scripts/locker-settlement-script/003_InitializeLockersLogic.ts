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
    logger.color('blue').bold().log("Initialize lockers logic...")

    const lockersLib = await deployments.get("LockersLib")
    const lockersLogic = await deployments.get("LockersLogic")

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
        console.log("initialize lockers logic: ", initializeTx.hash)
    } else {
        console.log("lockers logic is already initialized")
    }

    logger.color('blue').log("-------------------------------------------------")

};

export default func;
