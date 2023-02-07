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

    const exchangeAppId = config.get("cc_exchange.app_id")

    const checkExchangeConnectorInCCExchange = await ccExchangeRouterInstance.exchangeConnector(exchangeAppId)

    if (checkExchangeConnectorInCCExchange != exchangeConnector.address) {
        const setConnectorAndAppIdTx = await ccExchangeRouterInstance.setExchangeConnector(
            exchangeAppId,
            exchangeConnector.address
        )
        await setConnectorAndAppIdTx.wait(1)
        console.log("set connector and app id in CC exchange: ", setConnectorAndAppIdTx.hash)
    } else {
        console.log("connector and app id are already settled in CC exchange")
    }
    

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
