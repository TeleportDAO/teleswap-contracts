import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber } from 'ethers';
import { time } from 'console';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Create collateral pool with factory and add liquidity to it...")

    const uniswapRouterContract = await deployments.get("UniswapV2Router02")
    const uniswapRouterFactory = await ethers.getContractFactory("UniswapV2Router02")
    const uniswapRouterInstance = await uniswapRouterFactory.attach(
        uniswapRouterContract.address
    )

    const wEthContract = await deployments.get("WETH")
    const wEthFactory = await ethers.getContractFactory("WETH")
    const wEthInstance = await wEthFactory.attach(
        wEthContract.address
    )

    const teleBTC = await deployments.get("TeleBTC")
    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    let theAmount18Decimal = BigNumber.from(10).pow(18).mul(10)
    let theAmount8Decimal = BigNumber.from(10).pow(4).mul(5)
     
    const depositTx = await wEthInstance.deposit(
        {value: theAmount18Decimal}
    );
    await depositTx.wait(1)

    const balanceOfDeployer = await wEthInstance.balanceOf(deployer) 

    const approveForUniswapRouterTx = await wEthInstance.approve(uniswapRouterContract.address, balanceOfDeployer)
    await approveForUniswapRouterTx.wait(1)
    console.log("approve wEth to uniswap router: ", approveForUniswapRouterTx.hash)

    const isDeployerMinter = await teleBTCInstance.minters(
        deployer
    )

    if (!isDeployerMinter) {
        const addDeployerAsMinter = await teleBTCInstance.addMinter(
            deployer
        )

        await addDeployerAsMinter.wait(1)
        console.log("add deployer as minter: ", addDeployerAsMinter.hash)
    }

    const mintTeleBTC = await teleBTCInstance.mint(
        deployer,
        theAmount8Decimal
    )
    await mintTeleBTC.wait(1)
    console.log("mint teleBTC: ", mintTeleBTC.hash)

    const approveTeleBTCForUniswapTx = await teleBTCInstance.approve(uniswapRouterContract.address, theAmount8Decimal)
    await approveTeleBTCForUniswapTx.wait(1)
    console.log("approve teleBTC to uniswap router: ", approveTeleBTCForUniswapTx.hash)

    var deadline = (Date.now() / 1000) + 2000;
    deadline = Math.trunc(deadline)

    const addLiqudidutyTx = await uniswapRouterInstance.addLiquidity(
        wEthContract.address,
        teleBTC.address,
        theAmount18Decimal,
        theAmount8Decimal.div(2),
        theAmount18Decimal.div(2),
        theAmount8Decimal.div(4),
        deployer,
        deadline
    )
    await addLiqudidutyTx.wait(1)
    console.log("add liquidity: ", addLiqudidutyTx.hash)

    logger.color('blue').log("-------------------------------------------------")
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
