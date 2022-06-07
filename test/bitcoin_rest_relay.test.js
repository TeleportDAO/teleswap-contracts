// const BitcoinRelay = artifacts.require("BitcoinRelay");
const {assert} = require('chai');
const truffleAssert = require('truffle-assertions');
const {BitcoinRESTAPI} = require('bitcoin_rest_api');
const {baseURLMainnet} = require('bitcoin_rest_api');
const {baseURLTestnet} = require('bitcoin_rest_api');
const {networkMainnet} = require('bitcoin_rest_api');
const {networkTestnet} = require('bitcoin_rest_api');
const fs = require('fs');
var path = require('path');
var jsonPath = path.join(__dirname, '..', 'testBlockHeaders.json');
// require('chai').use(require('chai-as-promised')).should();
require('dotenv').config({path:"../../.env"});

describe("Bitcoin Relay (js)", async () => {

  let bitcoinRelay;
  // let deployer = accounts[0];
  let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  let bitcoinRESTAPI;
  let blockHeaders;

  before(async () => {

    // bitcoinRESTAPI = new BitcoinRESTAPI(networkMainnet, baseURLMainnet, 2);
    //
    // // read block headers from file
    // let data = fs.readFileSync(jsonPath, 'utf-8');
    // blockHeaders = data.split('\n');
    //
    // // submit the first block header
    // var _height = 199584; // 99*2016
    // var _genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(_height);
    // var _periodStart = await bitcoinRESTAPI.getHexBlockHash(_height);
    // _genesisHeader = '0x' + _genesisHeader;
    // _periodStart = '0x' + _periodStart;
    // bitcoinRelay = await BitcoinRelay.new(
    //     _genesisHeader,
    //     _height,
    //     _periodStart,
    //     ZERO_ADDRESS,
    //     ZERO_ADDRESS,
    //     {from: deployer}
    // );

    // var _height = 199584; // 99*2016
    // var _genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(_height);
    // var _periodStart = await bitcoinRESTAPI.getHexBlockHash(_height);
    // _genesisHeader = '0x' + _genesisHeader;
    // _periodStart = '0x' + _periodStart;
    // bitcoinRelay = await BitcoinRelay.new(
    //     _genesisHeader,
    //     _height,
    //     _periodStart,
    //     ZERO_ADDRESS,
    //     ZERO_ADDRESS,
    //     {from: deployer}
    // );

  });

  describe('Submitting block headers with retarget', async () => {
    console.log("the js")

    // it('submit old block headers', async function () {
    //   this.timeout(0);
    //   // submit block headers up to 100*2016
    //   for (let i = 0; i < 16; i++) {
    //
    //     blockHeadersNew = '0x';
    //
    //     if (i == 0) {
    //       blockHeaderOld = '0x' + blockHeaders[0];
    //       for (let j = 1; j < 126; j++) {
    //         blockHeadersNew = blockHeadersNew + blockHeaders[j + i*126];
    //       }
    //     } else {
    //       blockHeaderOld = '0x' + blockHeaders[i*126 - 1];
    //       for (let j = 0; j < 126; j++) {
    //         blockHeadersNew = blockHeadersNew + blockHeaders[j + i*126];
    //       }
    //     }
    //
    //     await truffleAssert.passes(bitcoinRelay.addHeaders(
    //         blockHeaderOld, // anchor header
    //         blockHeadersNew, // new header
    //         {from: deployer})
    //     );
    //
    //   }
    //
    // });
    //
    // it('submit a block header with new target', async () => {
    //   let blockHeaderNew = await bitcoinRESTAPI.getHexBlockHeader(100*2016); // this is the new block header
    //   blockHeaderNew = '0x' + blockHeaderNew;
    //   let oldPeriodStartHeader = '0x' + blockHeaders[0];
    //   let oldPeriodEndHeader = '0x' + blockHeaders[2015];
    //   await truffleAssert.passes(bitcoinRelay.addHeadersWithRetarget(
    //       oldPeriodStartHeader,
    //       oldPeriodEndHeader,
    //       blockHeaderNew,
    //       {from: deployer})
    //   );
    // });

  });

  describe('Check tx inclusion', async () => {

    // it('check the inclusion of a transaction having txid',async() => {
    //   blockNumber = 100*2016 - 10;
    //   let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
    //   let block = await bitcoinRESTAPI.getBlock(blockNumber);
    //   _index = 10;
    //   _txid = transactionIds[_index];
    //   let proof = await bitcoinRESTAPI.getMerkleProof(_txid);
    //   _merkleRoot = '0x' + block.merkle_root;
    //   _blockNumber = blockNumber;
    //   _intermediateNodes = proof.intermediateNodes;
    //   _txid = '0x' + _txid;
    //   payWithTDT = false;
    //   _neededConfirmations = 0;
    //   await truffleAssert.passes(bitcoinRelay.checkTxProof(
    //       _txid,
    //       _blockNumber,
    //       _intermediateNodes,
    //       _index,
    //       payWithTDT,
    //       _neededConfirmations,
    //       {from: deployer})
    //   );
    // });

    // it('check txid',async() => {
    //   let blockNumber = 100*2016 - 10;
    //   let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
    //   _index = 0;
    //   _txid = transactionIds[_index];
    //   let parsedTx = await bitcoinRESTAPI.parseTransaction(_txid);
    //   let _version = parsedTx.version;
    //   let _vin = parsedTx.vin;
    //   let _vout = parsedTx.vout;
    //   let _locktime = parsedTx.locktime;
    //   await truffleAssert.passes(bitcoinRelay.calculateTxId(
    //       _version,
    //       _vin,
    //       _vout,
    //       _locktime,
    //       {from: deployer})
    //   );
    // });

  });

});