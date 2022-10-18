import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'

require('dotenv').config({path:"../config/temp.env"});

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    let theBlockHeight = process.env.BLOCK_HEIGHT;

    const protocolPercentageFee = config.get("cc_burn.protocol_percentage_fee")
    const slasherPercentageReward = config.get("cc_burn.slasher_percentage_reward")
    const bitcoinFee = config.get("cc_burn.bitcoin_fee")
    const treasuryAddress = config.get("cc_burn.treasury")

    const transferDeadLine = 10

    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")



    await deploy("CCBurnRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            bitcoinRelay.address,
            lockersProxy.address,
            treasuryAddress,
            teleBTC,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        ],
    });
};

export default func;
func.tags = ["CCBurnRouter"];
