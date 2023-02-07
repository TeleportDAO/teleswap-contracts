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
    logger.color('blue').bold().log("Set Exchange Router in price oracle...")

    const uniswapV2Router02 = config.get("uniswap_v2_router_02")
    const uniswapV2Connector = await deployments.get("UniswapV2Connector")
    const priceOracle = await deployments.get("PriceOracle")


    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    const priceOracleInstance = await PriceOracleFactory.attach(
        priceOracle.address
    );

    const exchangeConnectorAddress = await priceOracleInstance.exchangeConnector(
        uniswapV2Router02
    )

    if (exchangeConnectorAddress == "0x0000000000000000000000000000000000000000") {
        const addExchangeTx = await priceOracleInstance.addExchangeConnector(
            uniswapV2Router02,
            uniswapV2Connector.address
        )

        await addExchangeTx.wait(1)
        console.log("set exchange router in price oracle: ", addExchangeTx.hash)
    }
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
