import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import config from 'config'
import verify from "../helper-functions"
import { number } from 'bitcoinjs-lib/src/script';

var path = require('path');
var fs = require('fs');

var tempFilePath = path.join(__dirname, '..', '.env');

const {BitcoinRESTAPI} = require('bitcoin_rest_api');
const {baseURLMainnet} = require('bitcoin_rest_api');
const {baseURLTestnet} = require('bitcoin_rest_api');
const {networkMainnet} = require('bitcoin_rest_api');
const {networkTestnet} = require('bitcoin_rest_api');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    // TODO: check with Sina to use the new bitcoin package
    let bitcoinRESTAPI;
    let bitcoinNetwork = config.get("bitcoin_network")

    if (bitcoinNetwork == "testnet") {
        bitcoinRESTAPI = new BitcoinRESTAPI(networkTestnet, baseURLTestnet, 2);
    }
    if (bitcoinNetwork == "mainnet") {
        bitcoinRESTAPI = new BitcoinRESTAPI(networkMainnet, baseURLMainnet, 2);
    }
     

    // Deploys BitcoinRelay
    // note: NEVER START WITH 0! IT MAKES PROBLEM
    let blockCount = await bitcoinRESTAPI.getBlockCount();
    let height;
    if (blockCount > 5) {
        height = blockCount - 5;
    } else {
        height = blockCount;
    }

    let genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(height);

    let periodStartHeight = height - height%2016;
    let periodStart = await bitcoinRESTAPI.getHexBlockHash(periodStartHeight);
    periodStart = Buffer.from(periodStart , 'hex').reverse().toString('hex');

    const tdtToken = await deployments.get("ERC20")

    var blockHeight = "BLOCK_HEIGHT=" + height + "\n";
    fs.appendFileSync(tempFilePath, blockHeight);

    let deployedContract;

    if (bitcoinNetwork == "mainnet") {
        deployedContract = await deploy("BitcoinRelay", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [
                '0x' + genesisHeader,
                height,
                '0x' + periodStart,
                tdtToken.address
            ],
        });
    } else {
        deployedContract = await deploy("BitcoinRelayTestnet", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [
                '0x' + genesisHeader,
                height,
                '0x' + periodStart,
                tdtToken.address
            ],
        });
    }

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {

        let theBlockHeight = await process.env.BLOCK_HEIGHT;
        let height = Number(theBlockHeight)

        let genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(height);

        let periodStartHeight = height - height%2016;
        let periodStart = await bitcoinRESTAPI.getHexBlockHash(periodStartHeight);
        periodStart = Buffer.from(periodStart , 'hex').reverse().toString('hex');

        if (bitcoinNetwork == "mainnet") {
            await verify(deployedContract.address, [
                '0x' + genesisHeader,
                height,
                '0x' + periodStart,
                tdtToken.address
            ], "contracts/relay/BitcoinRelay.sol:BitcoinRelay")
        } else {
            await verify(deployedContract.address, [
                '0x' + genesisHeader,
                height,
                '0x' + periodStart,
                tdtToken.address
            ], "contracts/relay/BitcoinRelayTestnet.sol:BitcoinRelayTestnet")
        }
        
    }
};

export default func;
func.tags = ["BitcoinRelay"];
