// const BitcoinRelay = artifacts.require("BitcoinRelay");
import { assert, expect, use } from "chai";
// const truffleAssert = require('truffle-assertions');
const {BitcoinRESTAPI} = require('bitcoin_rest_api');
const {baseURLMainnet} = require('bitcoin_rest_api');
const {baseURLTestnet} = require('bitcoin_rest_api');
const {networkMainnet} = require('bitcoin_rest_api');
const {networkTestnet} = require('bitcoin_rest_api');
const fs = require('fs');
var path = require('path');
var jsonPath = path.join(__dirname, './test_fixtures', 'testBlockHeaders.json');
// require('chai').use(require('chai-as-promised')).should();
require('dotenv').config({path:"../../.env"});

import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import {BitcoinRelay} from "../src/types/BitcoinRelay";
import {BitcoinRelay__factory} from "../src/types/factories/BitcoinRelay__factory";

describe("Bitcoin Relay (ts)", async () => {

    let bitcoinRelay: BitcoinRelay;
    let deployer: Signer;
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let bitcoinRESTAPI: any;
    let blockHeaders: any;

    before(async () => {

        bitcoinRESTAPI = new BitcoinRESTAPI(networkMainnet, baseURLMainnet, 2);

        // read block headers from file
        let data = fs.readFileSync(jsonPath, 'utf-8');
        blockHeaders = data.split('\n');

        // submit the first block header
        // var _height = 199584; // 99*2016
        // var _genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(_height);
        // var _periodStart = await bitcoinRESTAPI.getHexBlockHash(_height);
        // _genesisHeader = '0x' + _genesisHeader;
        // _periodStart = '0x' + _periodStart;
        bitcoinRelay = await deployBitcoinRelay();

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

    const deployBitcoinRelay = async (
        _signer?: Signer
    ): Promise<BitcoinRelay> => {
        const bitcoinRelayFactory = new BitcoinRelay__factory(
            _signer || deployer
        );

        let _height = 199584; // 99*2016
        let _heightBigNumber = BigNumber.from(199584)
        let _genesisHeader: BytesLike = await bitcoinRESTAPI.getHexBlockHeader(_height);
        let _periodStart: BytesLike = await bitcoinRESTAPI.getHexBlockHash(_height);
        _genesisHeader = '0x' + _genesisHeader;
        _periodStart = '0x' + _periodStart;

        console.log("before deploying the bitcoin relay")
        const bitcoinRelay = await bitcoinRelayFactory.deploy(
            _genesisHeader,
            _heightBigNumber,
            _periodStart,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
        );
        console.log("after deploying the bitcoin relay")
        return bitcoinRelay;
    };

    describe('Submitting block headers with retarget', async () => {
        console.log("the ts")

        it('submit old block headers', async function () {
          this.timeout(0);
          // submit block headers up to 100*2016
          for (let i = 0; i < 16; i++) {

            let blockHeadersNew = '0x';

            let blockHeaderOld;

            if (i == 0) {
              blockHeaderOld = '0x' + blockHeaders[0];
              for (let j = 1; j < 126; j++) {
                blockHeadersNew = blockHeadersNew + blockHeaders[j + i*126];
              }
            } else {
              blockHeaderOld = '0x' + blockHeaders[i*126 - 1];
              for (let j = 0; j < 126; j++) {
                blockHeadersNew = blockHeadersNew + blockHeaders[j + i*126];
              }
            }

            await expect(
                bitcoinRelay.addHeaders(
                    blockHeaderOld, // anchor header
                    blockHeadersNew // new header
                )
            ).to.equal(true);

          }

        });

        it('submit a block header with new target', async () => {
          let blockHeaderNew = await bitcoinRESTAPI.getHexBlockHeader(100*2016); // this is the new block header
          blockHeaderNew = '0x' + blockHeaderNew;
          let oldPeriodStartHeader = '0x' + blockHeaders[0];
          let oldPeriodEndHeader = '0x' + blockHeaders[2015];
          await expect(
              bitcoinRelay.addHeadersWithRetarget(
                  oldPeriodStartHeader,
                  oldPeriodEndHeader,
                  blockHeaderNew
            )
          ).to.equal(true);
        });

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