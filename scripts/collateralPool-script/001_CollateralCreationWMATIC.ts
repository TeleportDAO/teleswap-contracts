import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config'
import { BigNumber } from 'ethers';
const logger = require('node-color-log');
let bitcoinNetwork = config.get("bitcoin_network")

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Create collateral pool with factory and add liquidity to it...")

    const oneUnit8Decimal = BigNumber.from(10).pow(8).mul(1)

    const collateralPoolFactoryContract = await deployments.get("CollateralPoolFactory")
    const collateralPoolFactoryFactory = await ethers.getContractFactory("CollateralPoolFactory")
    const collateralPoolFactoryInstance = await collateralPoolFactoryFactory.attach(
        collateralPoolFactoryContract.address
    )

    const wrappedMatic = config.get("wrapped_matic") as string
    const erc20Factory = await ethers.getContractFactory("WETH")
    const erc20Instance = await erc20Factory.attach(
        wrappedMatic
    )

    const hasCollateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
        wrappedMatic
    )

    let collateralPoolAddress: any

    if (hasCollateralPoolAddress == "0x0000000000000000000000000000000000000000") {
        const createCollateralPoolTx = await collateralPoolFactoryInstance.createCollateralPool(
            wrappedMatic,
            20000
        )
    
        await createCollateralPoolTx.wait(1)
        console.log("create wmatic collateral pool: ", createCollateralPoolTx.hash)

        collateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
            wrappedMatic
        )
    
    } else {
        collateralPoolAddress = hasCollateralPoolAddress
    }
     
    if (bitcoinNetwork == "testnet") {
        const depositTx = await erc20Instance.deposit(
            {value: oneUnit8Decimal}
        );
        await depositTx.wait(1)

        const approveForCollateralPoolTx = await erc20Instance.approve(collateralPoolAddress, oneUnit8Decimal)
        await approveForCollateralPoolTx.wait(1)
        console.log("approve collateral pool to access to wrapped matic: ", approveForCollateralPoolTx.hash)

        const collateralPoolContract = await ethers.getContractFactory(
            "CollateralPool"
        );

        const collateralPoolInstance = await collateralPoolContract.attach(
            collateralPoolAddress
        );

        const addLiquidityTx = await collateralPoolInstance.addCollateral(
            deployer,
            oneUnit8Decimal
        )

        await addLiquidityTx.wait(1)
        console.log("add collateral to collateral pool: ", addLiquidityTx.hash)
    }

    logger.color('blue').log("-------------------------------------------------")
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
