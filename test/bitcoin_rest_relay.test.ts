// // const BitcoinRelay = artifacts.require("BitcoinRelay");
// import { assert, expect, use } from "chai";
// // const truffleAssert = require('truffle-assertions');
// const {BitcoinRESTAPI} = require('bitcoin_rest_api');
// const {baseURLMainnet} = require('bitcoin_rest_api');
// const {baseURLTestnet} = require('bitcoin_rest_api');
// const {networkMainnet} = require('bitcoin_rest_api');
// const {networkTestnet} = require('bitcoin_rest_api');
// const fs = require('fs');
// var path = require('path');
// var jsonPath = path.join(__dirname, './test_fixtures', 'testBlockHeaders.json');
// // require('chai').use(require('chai-as-promised')).should();
// require('dotenv').config({path:"../../.env"});
//
// import { deployments, ethers } from "hardhat";
// import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
// import { solidity } from "ethereum-waffle";
//
// import { isBytesLike } from "ethers/lib/utils";
// import {BitcoinRelay} from "../src/types/BitcoinRelay";
// import {BitcoinRelay__factory} from "../src/types/factories/BitcoinRelay__factory";
//
//
// describe("Bitcoin Relay (ts)", async () => {
//
//     let bitcoinRelay: BitcoinRelay;
//     let deployer: Signer;
//     let signer1: Signer;
//
//     let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
//     let bitcoinRESTAPI: any;
//     let blockHeaders: any;
//
//     before(async () => {
//
//         [deployer, signer1] = await ethers.getSigners();
//
//         bitcoinRESTAPI = new BitcoinRESTAPI(networkMainnet, baseURLMainnet, 2);
//
//         // read block headers from file
//         let data = fs.readFileSync(jsonPath, 'utf-8');
//         blockHeaders = data.split('\n');
//
//         bitcoinRelay = await deployBitcoinRelay();
//
//     });
//
//     const deployBitcoinRelay = async (
//         _signer?: Signer
//     ): Promise<BitcoinRelay> => {
//         const bitcoinRelayFactory = new BitcoinRelay__factory(
//             _signer || deployer
//         );
//
//         let _height = 199584; // 99*2016
//         let _heightBigNumber = BigNumber.from(199584)
//         let _genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(_height);
//         let _periodStart = await bitcoinRESTAPI.getHexBlockHash(_height);
//         _genesisHeader = '0x' + _genesisHeader;
//
//         console.log("the genesis header: ", _genesisHeader)
//         _periodStart = '0x' + _periodStart;
//
//         const bitcoinRelay = await bitcoinRelayFactory.deploy(
//             _genesisHeader,
//             _heightBigNumber,
//             _periodStart,
//             ZERO_ADDRESS,
//             ZERO_ADDRESS,
//         );
//
//         return bitcoinRelay;
//     };
//
//     describe('Submitting block headers with retarget', async () => {
//
//         it('check the owner', async function () {
//             let theOwnerAddress = await bitcoinRelay.owner()
//
//             let theDeplyerAddress = await deployer.getAddress();
//
//             expect(theOwnerAddress).to.equal(theDeplyerAddress);
//         })
//
//         it('submit old block headers', async function () {
//             this.timeout(0);
//             // submit block headers up to 100*2016
//             for (let i = 0; i < 32; i++) {
//
//                 let blockHeadersNew = '0x';
//
//                 let blockHeaderOld = '';
//
//                 if (i == 0) {
//                     blockHeaderOld = '0x' + blockHeaders[0];
//                     for (let j = 1; j < 63; j++) {
//                         blockHeadersNew = blockHeadersNew + blockHeaders[j + i*63];
//                     }
//                 } else {
//                     blockHeaderOld = '0x' + blockHeaders[i*63 - 1];
//                     for (let j = 0; j < 63; j++) {
//                         blockHeadersNew = blockHeadersNew + blockHeaders[j + i*63];
//                     }
//                 }
//
//                 await expect(
//                     bitcoinRelay.addHeaders(
//                         blockHeaderOld, // anchor header
//                         blockHeadersNew // new header;
//                     )
//                 ).to.emit(bitcoinRelay, "BlockAdded")
//
//             }
//
//         });
//
//         it('submit a block header with new target', async () => {
//             let blockHeaderNew = await bitcoinRESTAPI.getHexBlockHeader(100*2016); // this is the new block header
//             blockHeaderNew = '0x' + blockHeaderNew;
//             let oldPeriodStartHeader = '0x' + blockHeaders[0];
//             let oldPeriodEndHeader = '0x' + blockHeaders[2015];
//
//             await expect(
//                 bitcoinRelay.addHeadersWithRetarget(
//                     oldPeriodStartHeader,
//                     oldPeriodEndHeader,
//                     blockHeaderNew
//                 )
//             ).to.emit(bitcoinRelay, "BlockAdded")
//
//         });
//
//     });
//
//     describe('Check tx inclusion', async () => {
//
//         it('check the inclusion of a transaction having txid',async() => {
//             let blockNumber = 100*2016 - 10;
//             let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
//             let block = await bitcoinRESTAPI.getBlock(blockNumber);
//             let _index = 10;
//             let _txid = transactionIds[_index];
//             let proof = await bitcoinRESTAPI.getMerkleProof(_txid);
//             let _merkleRoot = '0x' + block.merkle_root;
//             let _blockNumber = blockNumber;
//             let _intermediateNodes = proof.intermediateNodes;
//             _txid = '0x' + _txid;
//             let payWithTDT = false;
//             let _neededConfirmations = 0;
//
//             expect(
//                 await bitcoinRelay.checkTxProof(
//                     _txid,
//                     _blockNumber,
//                     _intermediateNodes,
//                     _index,
//                     // payWithTDT,
//                     // _neededConfirmations
//                 )
//             ).to.equal(true);
//
//         });
//
//         // it('check txid',async() => {
//         //     let blockNumber = 100*2016 - 10;
//         //     let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
//         //     let _index = 0;
//         //     let _txid = transactionIds[_index];
//         //     console.log("type of txid: ", typeof(_txid))
//         //     console.log("txid: ", _txid)
//         //     let parsedTx = await bitcoinRESTAPI.parseTransaction(_txid);
//         //     let _version = parsedTx.version;
//         //     let _vin = parsedTx.vin;
//         //     let _vout = parsedTx.vout;
//         //     let _locktime = parsedTx.locktime;
//
//         //     expect(
//         //         await bitcoinRelay.calculateTxId(
//         //             _version,
//         //             _vin,
//         //             _vout,
//         //             _locktime
//         //         )
//         //         // TODO: why the txid is different?!
//         //     ).to.equal("0xb2e944205992eec82c5076eb62146d52acccc1700a5428922a04d2bfea581e89")
//         //     // ).to.equal(_txid)
//         // });
//
//     });
//
// });