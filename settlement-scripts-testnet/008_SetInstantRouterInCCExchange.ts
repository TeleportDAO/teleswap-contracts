import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("Set instant router and connector in cc exchange...")

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


    const setConnectorAndAppIdTx = await ccExchangeRouterInstance.setExchangeConnector(
        20,
        exchangeConnector.address
    )
    await setConnectorAndAppIdTx.wait(1)

    log("...Set instant router and connector in cc exchange")

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
