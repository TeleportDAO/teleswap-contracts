import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import verify from "../helper-functions"

require('dotenv').config({path:"../config/temp.env"});

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    // TODO: un-comment the above one and remove the second one
    // let theBlockHeight = process.env.BLOCK_HEIGHT;
    let theBlockHeight = 773999;

    const protocolPercentageFee = config.get("cc_burn.protocol_percentage_fee")
    const slasherPercentageReward = config.get("cc_burn.slasher_percentage_reward")
    const bitcoinFee = config.get("cc_burn.bitcoin_fee")

    // TODO: update treasury address for main net
    const treasuryAddress = config.get("treasury")

    const transferDeadLine = config.get("cc_burn.transfer_deadLine")

    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")



    const deployedContract = await deploy("CCBurnRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            theBlockHeight,
            bitcoinRelay.address,
            lockersProxy.address,
            treasuryAddress,
            teleBTC.address,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        ],
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
            bitcoinRelay.address,
            lockersProxy.address,
            treasuryAddress,
            teleBTC.address,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        ], "contracts/routers/CCBurnRouter.sol:CCBurnRouter")
    }
};

export default func;
func.tags = ["CCBurnRouter"];
