import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import config from 'config'
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();

    const one8Dec = BigNumber.from(10).pow(8).mul(1)
    const one18Dec = BigNumber.from(10).pow(18).mul(1)
    
    const bitcoinNetwork = config.get("bitcoin_network");
    const wrappedMatic = config.get("wrapped_matic") as string;
    const uniswapFactory = await config.get("uniswap_v2_factory") as string
    const uniswapRouter = await config.get("uniswap_v2_router_02") as string

    const teleBTC = await deployments.get("TeleBTC")
    const instantPool = await deployments.get("InstantPool")

    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    const uniswapFactoryFactory = await ethers.getContractFactory("UniswapV2Factory");
    const uniswapFactoryInstance = await uniswapFactoryFactory.attach(
        uniswapFactory
    );

    const uniswapRouterFactory = await ethers.getContractFactory("UniswapV2Router02");
    const uniswapRouterInstance = await uniswapRouterFactory.attach(
        uniswapRouter
    );

    const theLiquidityPair2 = await uniswapFactoryInstance.getPair(
        teleBTC.address,
        wrappedMatic
    )

    if (bitcoinNetwork == "testnet" && theLiquidityPair2 == "0x0000000000000000000000000000000000000000") {

        logger.color('blue').log("-------------------------------------------------")
        logger.color('blue').bold().log("Charge WMATIC-TELEBTC pool ...")

        const timeNow = Date.now()
        const unixTimeNow = (timeNow - (timeNow % 1000))/1000 + 1000

        const isMinterTeleBTCTx = await teleBTCInstance.minters(deployer)

        if(!isMinterTeleBTCTx) {
            const addMinterTeleBTCTx = await teleBTCInstance.addMinter(deployer)
            await addMinterTeleBTCTx.wait(1)
        }

        if ((await teleBTCInstance.totalSupply()) == 0) {
            const mintTeleBTCTx = await teleBTCInstance.mint(deployer, one8Dec.div(2))
            await mintTeleBTCTx.wait(1)
        }

        let approveTeleBTCTx = await teleBTCInstance.approve(
            uniswapRouter,
            one8Dec.div(2)
        )
        await approveTeleBTCTx.wait(1)


        const addLiquidityPairTx = await uniswapRouterInstance.addLiquidityETH(
            teleBTC.address,
            (one8Dec.div(1800)).toString(),
            0,
            0,
            deployer,
            unixTimeNow,
            {
                value: (one18Dec.mul(10)).toString()
            }
        )

        await addLiquidityPairTx.wait(1)
        console.log("Charged WMATIC-TELEBTC pool: ", addLiquidityPairTx.hash)

        logger.color('blue').log("-------------------------------------------------")
        logger.color('blue').bold().log("Add liquidity to InstantPool ...")

        const instantPoolFactory = await ethers.getContractFactory("InstantPool");
        const instantPoolInstance = await instantPoolFactory.attach(
            instantPool.address
        );

        if(!isMinterTeleBTCTx) {
            const addMinterTeleBTCTx = await teleBTCInstance.addMinter(deployer)
            await addMinterTeleBTCTx.wait(1)
        }

        const mintTeleBTCTx = await teleBTCInstance.mint(deployer, one8Dec.div(2))
        await mintTeleBTCTx.wait(1)
        console.log("mint telebtc: ", mintTeleBTCTx.hash)

        approveTeleBTCTx = await teleBTCInstance.approve(
            instantPool.address,
            one8Dec.div(2)
        )
        await approveTeleBTCTx.wait(1)

        const addLiquiditylTx = await instantPoolInstance.addLiquidity(
            deployer,
            one8Dec.div(2)
        )

        await addLiquiditylTx.wait(1)
        console.log("Added liquidity to InstantPool: ", addLiquiditylTx.hash)

        logger.color('blue').log("-------------------------------------------------")
        logger.color('blue').bold().log("Charge WMATIC collateral pool ...")

        const wrappedMatic = config.get("wrapped_matic") as string
        const erc20Factory = await ethers.getContractFactory("WETH")
        const erc20Instance = await erc20Factory.attach(
            wrappedMatic
        )

        const collateralPoolFactoryContract = await deployments.get("CollateralPoolFactory")
        const collateralPoolFactoryFactory = await ethers.getContractFactory("CollateralPoolFactory")
        const collateralPoolFactoryInstance = await collateralPoolFactoryFactory.attach(
            collateralPoolFactoryContract.address
        )
        const collateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
            wrappedMatic
        )

        const depositTx = await erc20Instance.deposit(
            { value: one8Dec }
        );
        await depositTx.wait(1)

        const approveForCollateralPoolTx = await erc20Instance.approve(
            collateralPoolAddress, 
            one8Dec
        );
        await approveForCollateralPoolTx.wait(1)
        console.log("Approved collateral pool to access to WMATIC: ", approveForCollateralPoolTx.hash)

        const collateralPoolContract = await ethers.getContractFactory(
            "CollateralPool"
        );

        const collateralPoolInstance = await collateralPoolContract.attach(
            collateralPoolAddress
        );

        const addLiquidityTx = await collateralPoolInstance.addCollateral(
            deployer,
            one8Dec
        )

        await addLiquidityTx.wait(1)
        console.log("Added WMATIC to collateral pool: ", addLiquidityTx.hash)
    }

};

export default func;
