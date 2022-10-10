import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();


    const slasherPercentageReward = 10;
    const paybackDeadline = 12;

    const teleBTC = await deployments.get("TeleBTC")
    const bitcoinRelayTestnet = await deployments.get("BitcoinRelayTestnet")
    const priceOracle = await deployments.get("PriceOracle")
    const collateralPoolFactory = await deployments.get("CollateralPoolFactory")
    const defaultExchangeConnector = await deployments.get("UniswapV2Connector")

    const theArgs = [
        teleBTC.address,
        bitcoinRelayTestnet.address,
        priceOracle.address,
        collateralPoolFactory.address,
        slasherPercentageReward,
        paybackDeadline,
        defaultExchangeConnector.address
    ]

    const instantRouter = await deploy("InstantRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    log(`InstantRouter at ${instantRouter.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        verify(
            collateralPoolFactory.address,
            theArgs
        )
    }
};

export default func;
func.tags = ["InstantRouter", "BitcoinTestnet"];
