import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();


    const slasherPercentageReward = 10;
    const paybackDeadline = 12;

    const teleBTC = await deployments.get("TeleBTC")
    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const priceOracle = await deployments.get("PriceOracle")
    const collateralPoolFactory = await deployments.get("CollateralPoolFactory")
    const defaultExchangeConnector = await deployments.get("UniswapV2Connector")


    await deploy("InstantRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            teleBTC.address,
            bitcoinRelay.address,
            priceOracle.address,
            collateralPoolFactory.address,
            slasherPercentageReward,
            paybackDeadline,
            defaultExchangeConnector.address
        ],
    });
};

export default func;
func.tags = ["InstantRouter"];
