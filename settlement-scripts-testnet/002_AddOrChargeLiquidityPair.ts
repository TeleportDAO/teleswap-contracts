import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("Add or charge liquidity pool...")

    const one = BigNumber.from(10).pow(18).mul(1)

    const teleBTC = await deployments.get("TeleBTC")
    const linkToken = await deployments.get("ERC20AsLink")
    const uniswapFactory = await deployments.get("UniswapV2Factory")
    const uniswapRouter = await deployments.get("UniswapV2Router02")

    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    const linkTokenFactory = await ethers.getContractFactory("ERC20AsLink");
    const linkTokenInstance = await linkTokenFactory.attach(
        linkToken.address
    );

    const uniswapFactoryFactory = await ethers.getContractFactory("UniswapV2Factory");
    const uniswapFactoryInstance = await uniswapFactoryFactory.attach(
        uniswapFactory.address
    );

    const uniswapRouterFactory = await ethers.getContractFactory("UniswapV2Router02");
    const uniswapRouterInstance = await uniswapRouterFactory.attach(
        uniswapRouter.address
    );

    const theLiquidityPair = await uniswapFactoryInstance.getPair(
        teleBTC.address,
        linkToken.address
    )


    // if (theLiquidityPair == "0x0000000000000000000000000000000000000000") {
    //     const timeNow = Date.now()
    //     const unixTimeNow = (timeNow - (timeNow % 1000))/1000 + 1000


    //     const mintTeleBTCTx = await teleBTCInstance.mintTestToken()
    //     await mintTeleBTCTx.wait(1)

    //     const approveTeleBTCTx = await teleBTCInstance.approve(
    //         uniswapRouter.address,
    //         one
    //     )
    //     await approveTeleBTCTx.wait(1)

    //     const approveLinkTokenTx = await linkTokenInstance.approve(
    //         uniswapRouter.address,
    //         one.mul(500)
    //     )
    //     await approveLinkTokenTx.wait(1)

    //     const addLiquidityPairTx = await uniswapRouterInstance.addLiquidity(
    //         teleBTC.address,
    //         linkToken.address,
    //         one,
    //         one.mul(500),
    //         one.div(5),
    //         one.mul(100),
    //         deployer,
    //         unixTimeNow
    //     )

    //     await addLiquidityPairTx.wait(1)
    // }

    log("...Add or charge liquidity pool")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
