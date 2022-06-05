import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const punisherReward = 10;
    const paybackDeadline = 10;
    const collateralRatio = 100;
    const instantFee = 10;

    const ccTransferRouter = await deployments.get("CCTransferRouter")
    const exchangeRouter = await deployments.get("ExchangeRouter")
    const tbtToken = await deployments.get("ERC20")
    const liquidityPoolFactory = await deployments.get("LiquidityPoolFactory")
    const staking = await deployments.get("Staking")
    const bitcoinRelay = await deployments.get("BitcoinRelay")

    await deploy("InstantRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            ccTransferRouter.address,
            exchangeRouter.address,
            tbtToken.address,
            liquidityPoolFactory.address,
            staking.address,
            bitcoinRelay.address,
            punisherReward,
            paybackDeadline,
            collateralRatio,
            instantFee
        ],
    });
};

export default func;
func.tags = ["InstantRouter"];
