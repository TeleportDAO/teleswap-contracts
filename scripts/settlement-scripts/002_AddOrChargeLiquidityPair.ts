import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config'
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');
let bitcoinNetwork = config.get("bitcoin_network")

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Add and charge liquidity pool if not exists...")

    const one8Dec = BigNumber.from(10).pow(8).mul(1)
    const one18Dec = BigNumber.from(10).pow(18).mul(1)

    const wrappedMatic = config.get("wrapped_matic") as string
    const teleBTC = await deployments.get("TeleBTC")
    const uniswapFactory = await config.get("uniswap_v2_factory") as string
    const uniswapRouter = await config.get("uniswap_v2_router_02") as string

    const wETHFactory = await ethers.getContractFactory("WETH");
    const wETHInstance = await wETHFactory.attach(
        wrappedMatic
    );

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

        const timeNow = Date.now()
        const unixTimeNow = (timeNow - (timeNow % 1000))/1000 + 1000

        const isMinterTeleBTCTx = await teleBTCInstance.minters(deployer)

        // TODO: in main net the following code can not be ran 
        if(!isMinterTeleBTCTx) {
            const addMinterTeleBTCTx = await teleBTCInstance.addMinter(deployer)
            await addMinterTeleBTCTx.wait(1)
        }

        const mintTeleBTCTx = await teleBTCInstance.mint(deployer, one8Dec.div(2))
        await mintTeleBTCTx.wait(1)

        const approveTeleBTCTx = await teleBTCInstance.approve(
            uniswapRouter,
            one8Dec.div(2)
        )
        await approveTeleBTCTx.wait(1)


        const addLiquidityPairTx = await uniswapRouterInstance.addLiquidityETH(
            teleBTC.address,
            one8Dec.div(2300),
            one8Dec.div(2500),
            one18Dec.div(12),
            deployer,
            unixTimeNow,
            {
                value: one18Dec.mul(10)
            }
        )

        await addLiquidityPairTx.wait(1)
        console.log("add or charge telebtc-eth liquidity pair: ", addLiquidityPairTx.hash)
    }


};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
