import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const ccExchangeRouter = await deployments.get("CCExchangeRouter")
    const instantRouter = await deployments.get("InstantRouter")

    const ccExchangeRouterFactory = await ethers.getContractFactory("CCExchangeRouter");
    const ccExchangeRouterInstance = await ccExchangeRouterFactory.attach(
        ccExchangeRouter.address
    );

    const setInstantRouterTx = await ccExchangeRouterInstance.setInstantRouter(
        instantRouter.address
    )

    await setInstantRouterTx.wait(1)

};

export default func;
func.tags = ["PriceOracle", "BitcoinTestnet"];
