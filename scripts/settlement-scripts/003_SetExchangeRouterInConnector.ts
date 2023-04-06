import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config'
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set Exchange Router in connector...")

    const uniswapRouter = config.get("uniswap_v2_router_02")
    const uniswapConnector = await deployments.get("UniswapV2Connector")

    const uniswapConnectorFactory = await ethers.getContractFactory("UniswapV2Connector");
    const uniswapConnectorInstance = await uniswapConnectorFactory.attach(
        uniswapConnector.address
    );

    const _exchangeRouter = await uniswapConnectorInstance.exchangeRouter();
    if (uniswapRouter != _exchangeRouter) {
        const setExchangeRouterTx = await uniswapConnectorInstance.setExchangeRouter(
            uniswapRouter
        )
        await setExchangeRouterTx.wait(1)
        console.log("set exchange router in connector: ", setExchangeRouterTx.hash)
    } else {
        console.log("exchange router is already settled in exchange connector")
    }

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
