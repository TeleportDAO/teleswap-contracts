import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const slasherPercentageReward = config.get("instant_router.slasher_percentage_reward");
    const paybackDeadline = config.get("instant_router.payback_deadline");
    const maxPriceDifferencePercent = config.get("instant_router.max_price_difference_percent");

    // TODO: update treasury address for main net
    const treasuryAddress = config.get("treasury")

    const teleBTC = await deployments.get("TeleBTC")
    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const priceOracle = await deployments.get("PriceOracle")
    const collateralPoolFactory = await deployments.get("CollateralPoolFactory")
    const defaultExchangeConnector = await deployments.get("UniswapV2Connector")


    const deployedContract = await deploy("InstantRouter", {
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
            defaultExchangeConnector.address,
            maxPriceDifferencePercent,
            treasuryAddress
        ],
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
            teleBTC.address,
            bitcoinRelay.address,
            priceOracle.address,
            collateralPoolFactory.address,
            slasherPercentageReward,
            paybackDeadline,
            defaultExchangeConnector.address,
            maxPriceDifferencePercent,
            treasuryAddress
        ], "contracts/routers/InstantRouter.sol:InstantRouter")
    }
};

export default func;
func.tags = ["InstantRouter"];
