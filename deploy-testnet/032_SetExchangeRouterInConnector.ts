import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const uniswapRouter = await deployments.get("UniswapV2Router02")
    const uniswapConnector = await deployments.get("UniswapV2Connector")

    const uniswapConnectorFactory = await ethers.getContractFactory("UniswapV2Connector");
    const uniswapConnectorInstance = await uniswapConnectorFactory.attach(
        uniswapConnector.address
    );

    const setExchangeRouterTx = await uniswapConnectorInstance.setExchangeRouter(
        uniswapRouter.address
    )
    await setExchangeRouterTx.wait(1)

};

export default func;
func.tags = ["PriceOracle", "BitcoinTestnet"];
