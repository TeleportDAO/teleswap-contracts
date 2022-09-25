import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("Set teleBTC in Locker...")

    const one = BigNumber.from(10).pow(18).mul(1)

    const lockersLib = await deployments.get("LockersLib")
    const lockersProxy = await deployments.get("LockersProxy")

    const teleDAOToken = await deployments.get("ERC20")
    const teleBTC = await deployments.get("TeleBTC")
    const exchangeConnector = await deployments.get("UniswapV2Connector")
    const priceOracle = await deployments.get("PriceOracle")
    const minTDTLockedAmount = 0;
    const minNativeLockedAmount = one.mul(2);
    const collateralRatio = 20000;
    const liquidationRatio = 15000;
    const lockerPercentageFee = 50;
    const priceWithDiscountRatio = 9500;

    const lockersLogicFactory = await ethers.getContractFactory(
        "LockersLogicTestnet",
        {
            libraries: {
                LockersLib: lockersLib.address
            }
        }
    );
    const lockersInstance = await lockersLogicFactory.attach(
        lockersProxy.address
    );

    const setTeleBTCTx = await lockersInstance.setTeleBTC(
        teleBTC.address
    )

    await setTeleBTCTx.wait(1)

    log("...Set teleBTC in Locker")

    // const teleDAOTokenAddress = await lockersInstance.TeleportDAOToken()

    // if (teleDAOTokenAddress == "0x0000000000000000000000000000000000000000") {
    //     const initializeTx = await lockersInstance.initialize(
    //         teleDAOToken.address,
    //         exchangeConnector.address,
    //         priceOracle.address,
    //         minTDTLockedAmount,
    //         minNativeLockedAmount,
    //         collateralRatio,
    //         liquidationRatio,
    //         lockerPercentageFee,
    //         priceWithDiscountRatio
    //     )

    //     await initializeTx.wait(1)
    // }

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
