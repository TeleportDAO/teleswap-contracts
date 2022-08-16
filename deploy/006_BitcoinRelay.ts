import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
// import {BitcoinRESTAPI} from 'bitcoin_rest_api';
// import {baseURLMainnet} from 'bitcoin_rest_api';
// import {baseURLTestnet} from 'bitcoin_rest_api';
// import {networkMainnet} from 'bitcoin_rest_api';
// import {networkTestnet} from 'bitcoin_rest_api';

var path = require('path');
var fs = require('fs');
var tempFilePath = path.join(__dirname, '..', 'config', 'temp.env')

const {BitcoinRESTAPI} = require('bitcoin_rest_api');
const {baseURLMainnet} = require('bitcoin_rest_api');
const {baseURLTestnet} = require('bitcoin_rest_api');
const {networkMainnet} = require('bitcoin_rest_api');
const {networkTestnet} = require('bitcoin_rest_api');


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    let bitcoinRESTAPI = new BitcoinRESTAPI(networkTestnet, baseURLTestnet, 2);

    // deploy BitcoinRelay
    // NEVER START WITH 0! IT MAKES PROBLEM
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

    const tbtToken = await deployments.get("ERC20")

    var blockHeight = "BLOCK_HEIGHT=" + height + "\n";
    fs.appendFileSync(tempFilePath, blockHeight);

    console.log("genesisHeader: ", genesisHeader)
    console.log("height: ", height)
    console.log("periodStart: ", periodStart)

    await deploy("BitcoinRelay", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            '0x' + genesisHeader,
            height,
            '0x' + periodStart,
            tbtToken.address
        ],
    });
};

export default func;
func.tags = ["BitcoinRelay"];
