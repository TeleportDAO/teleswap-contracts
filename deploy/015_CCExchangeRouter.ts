import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import { BigNumber } from 'ethers';

require('dotenv').config({path:"../config/temp.env"});

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    let theBlockHeight = process.env.BLOCK_HEIGHT;
    let theBlockHeightStr = theBlockHeight as string
    let blockHeightBigNumber = BigNumber.from(theBlockHeightStr)

    const protocolPercentageFee = config.get("cc_exchange.protocol_percentage_fee")
    const chainID = config.get("chain_id")
    // const appId = config.get("cc_exchange.app_id")
    const treasuryAddress = config.get("cc_exchange.treasury")

    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")


    await deploy("CCExchangeRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            blockHeightBigNumber,
            protocolPercentageFee,
            chainID,
            lockersProxy.address,
            bitcoinRelay.address,
            teleBTC.address,
            treasuryAddress
        ],
    });
};

export default func;
func.tags = ["CCExchangeRouter"];
