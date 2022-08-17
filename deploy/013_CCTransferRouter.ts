import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import { BigNumber } from 'ethers';

import * as dotenv from "dotenv";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    let theBlockHeight = await process.env.BLOCK_HEIGHT;

    const protocolPercentageFee = config.get("cc_transfer.protocol_percentage_fee")
    const chainId = config.get("chain_id")
    const appId = config.get("cc_transfer.app_id")
    const treasuryAddress = config.get("cc_transfer.treasury")

    const bitcoinRelay = await deployments.get("BitcoinRelay")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")

    await deploy("CCTransferRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            theBlockHeight,
            protocolPercentageFee,
            chainId,
            appId,
            bitcoinRelay.address,
            lockersProxy.address,
            teleBTC.address,
            treasuryAddress
        ],
    });
};

export default func;
func.tags = ["CCTransferRouter"];
