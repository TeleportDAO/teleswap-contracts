import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
var path = require('path');
var fs = require('fs');
import verify from "../helper-functions";

// TODO: use another file instead of .env
var tempFilePath = path.join(__dirname, '..', '.env');

const {BitcoinRESTAPI} = require('bitcoin_rest_api');
const {baseURLMainnet} = require('bitcoin_rest_api');
const {baseURLTestnet} = require('bitcoin_rest_api');
const {networkMainnet} = require('bitcoin_rest_api');
const {networkTestnet} = require('bitcoin_rest_api');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    let bitcoinRESTAPI = new BitcoinRESTAPI(networkTestnet, baseURLTestnet, 2);

    // Deploys BitcoinRelay
    // note: NEVER START WITH 0! IT MAKES PROBLEM
    let blockCount = await bitcoinRESTAPI.getBlockCount();
    let height;
    if (blockCount > 5) {
        height = blockCount - 5;
    } else {
        height = blockCount;
    }

    // TODO: setting the following parameters
    let genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(height);

    let periodStartHeight = height - height%2016;
    let periodStart = await bitcoinRESTAPI.getHexBlockHash(periodStartHeight);
    periodStart = Buffer.from(periodStart , 'hex').reverse().toString('hex');

    const tdtToken = await deployments.get("ERC20")

    var blockHeight = "BLOCK_HEIGHT=" + height + "\n";
    fs.appendFileSync(tempFilePath, blockHeight);

    const relayer = await deploy("BitcoinRelayTestnet", {
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
};

export default func;
func.tags = ["BitcoinRelayTestnet", "BitcoinTestnet"];
