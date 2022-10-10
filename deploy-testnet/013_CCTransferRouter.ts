import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import { BigNumber } from 'ethers';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

import * as dotenv from "dotenv";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    let theBlockHeight = await process.env.BLOCK_HEIGHT;

    const protocolPercentageFee = config.get("cc_transfer.protocol_percentage_fee")
    const chainId = config.get("chain_id")
    const appId = config.get("cc_transfer.app_id")
    const treasuryAddress = config.get("cc_transfer.treasury")
    const bitcoinRelayTestnet = await deployments.get("BitcoinRelayTestnet")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")

    const theArgs = [
        theBlockHeight,
        protocolPercentageFee,
        chainId,
        appId,
        bitcoinRelayTestnet.address,
        lockersProxy.address,
        teleBTC.address,
        treasuryAddress
    ]

    const ccTransferRouter = await deploy("CCTransferRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    log(`CCTransferRouter at ${ccTransferRouter.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        verify(
            ccTransferRouter.address,
            theArgs
        )
    }
};

export default func;
func.tags = ["CCTransferRouter", "BitcoinTestnet"];
