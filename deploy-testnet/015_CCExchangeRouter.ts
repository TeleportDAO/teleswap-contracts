import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import { BigNumber } from 'ethers';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

require('dotenv').config({path:"../config/temp.env"});

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    let theBlockHeight = process.env.BLOCK_HEIGHT;
    let theBlockHeightStr = theBlockHeight as string
    let blockHeightBigNumber = BigNumber.from(theBlockHeightStr)

    const protocolPercentageFee = config.get("cc_exchange.protocol_percentage_fee")
    const chainID = config.get("chain_id")
    // const appId = config.get("cc_exchange.app_id")
    const treasuryAddress = config.get("cc_exchange.treasury")

    const bitcoinRelayTestnet = await deployments.get("BitcoinRelayTestnet")
    const lockersProxy = await deployments.get("LockersProxy")
    const teleBTC = await deployments.get("TeleBTC")

    const theArgs = [
        blockHeightBigNumber,
        protocolPercentageFee,
        chainID,
        lockersProxy.address,
        bitcoinRelayTestnet.address,
        teleBTC.address,
        treasuryAddress
    ]


    const ccExchange = await deploy("CCExchangeRouter", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });

    log(`CCExchangeRouter at ${ccExchange.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        await verify(
            ccExchange.address,
            theArgs
        )
    }
};

export default func;
func.tags = ["CCExchangeRouter", "BitcoinTestnet"];
