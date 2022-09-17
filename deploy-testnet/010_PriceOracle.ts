import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const acceptableDelay = 1000;
    const tdtToken = await deployments.get("ERC20")

    const uniswapV2Router02 = await deployments.get("UniswapV2Router02")
    const uniswapV2Connector = await deployments.get("UniswapV2Connector")

    const priceOracle = await deploy("PriceOracle", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            acceptableDelay,
            tdtToken.address
        ],
    });

    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    const priceOracleInstance = await PriceOracleFactory.attach(
        priceOracle.address
    );

    const addExchangeTx = await priceOracleInstance.addExchangeConnector(
        uniswapV2Router02.address,
        uniswapV2Connector.address
    )

    await addExchangeTx.wait(1)
};

export default func;
func.tags = ["PriceOracle", "BitcoinTestnet"];
