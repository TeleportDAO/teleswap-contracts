import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import { BigNumber } from 'ethers';
import verify from "../helper-functions"

import * as dotenv from "dotenv";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    let theBlockHeight = await process.env.BLOCK_HEIGHT;

    const protocolPercentageFee = config.get("cc_transfer.protocol_percentage_fee")
    const chainId = config.get("chain_id")
    const appId = config.get("cc_transfer.app_id")
    const bitcoin_network = config.get("bitcoin_network")
    const treasuryAddress = config.get("treasury")

    let bitcoinRelay;
    if (bitcoin_network == 'mainnet') {
        bitcoinRelay = await deployments.get("BitcoinRelay")
    } else {
        bitcoinRelay = await deployments.get("BitcoinRelayTestnet")
    }
    
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")

    const deployedContract = await deploy("CCTransferRouter", {
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

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
            theBlockHeight,
            protocolPercentageFee,
            chainId,
            appId,
            bitcoinRelay.address,
            lockersProxy.address,
            teleBTC.address,
            treasuryAddress
        ], "contracts/routers/CCTransferRouter.sol:CCTransferRouter")
    }
};

export default func;
func.tags = ["CCTransferRouter"];
