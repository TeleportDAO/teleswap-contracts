import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const one = BigNumber.from(10).pow(18).mul(1)

    const teleBTC = await deployments.get("TeleBTC")
    const linkToken = await deployments.get("ERC20AsLink")
    const uniswapRouter = await deployments.get("UniswapV2Router02")

    const teleBTCFactory = await ethers.getContractFactory("TeleBTC");
    const teleBTCInstance = await teleBTCFactory.attach(
        teleBTC.address
    );

    const linkTokenFactory = await ethers.getContractFactory("ERC20AsLink");
    const linkTokenInstance = await linkTokenFactory.attach(
        linkToken.address
    );

    const uniswapRouterFactory = await ethers.getContractFactory("UniswapV2Router02");
    const uniswapRouterInstance = await uniswapRouterFactory.attach(
        uniswapRouter.address
    );

    const mintTeleBTCTx = await teleBTCInstance.mintTestToken()
    await mintTeleBTCTx.wait(1)

    const approveTeleBTCTx = await teleBTCInstance.approve(
        uniswapRouter.address,
        one
    )
    await approveTeleBTCTx.wait(1)

    const approveLinkTokenTx = await linkTokenInstance.approve(
        uniswapRouter.address,
        one.mul(500)
    )
    await approveLinkTokenTx.wait(1)

    // const addLiquidityPairTx = await uniswapRouterInstance.addLiquidity(
    //     lockersProxy.address
    // )

    // await addLiquidityPairTx.wait(1)

};

export default func;
func.tags = ["PriceOracle", "BitcoinTestnet"];
