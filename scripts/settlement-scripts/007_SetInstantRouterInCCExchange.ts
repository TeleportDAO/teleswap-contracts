import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();


    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set instant router and connector in CC exchange...")

    const ccExchangeRouter = await deployments.get("CCExchangeRouter")
    const instantRouter = await deployments.get("InstantRouter")
    const exchangeConnector = await deployments.get("UniswapV2Connector")

    const ccExchangeRouterFactory = await ethers.getContractFactory("CCExchangeRouter");
    const ccExchangeRouterInstance = await ccExchangeRouterFactory.attach(
        ccExchangeRouter.address
    );

    const setInstantRouterTx = await ccExchangeRouterInstance.setInstantRouter(
        instantRouter.address
    )
    await setInstantRouterTx.wait(1)
    console.log("set instant router in CC exchange: ", setInstantRouterTx.hash)

    const setConnectorAndAppIdTx = await ccExchangeRouterInstance.setExchangeConnector(
        20,
        exchangeConnector.address
    )
    await setConnectorAndAppIdTx.wait(1)
    console.log("set connector and app id in CC exchange: ", setConnectorAndAppIdTx.hash)

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
