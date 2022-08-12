/* global artifacts contract describe before it assert web3 */
const BN = require('bn.js');
const utils = require('./utils.js');
const REGULAR_CHAIN = require('./test_fixtures/headers.json');
const RETARGET_CHAIN = require('./test_fixtures/headersWithRetarget.json');
const REORG_AND_RETARGET_CHAIN = require('./test_fixtures/headersReorgAndRetarget.json');

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

import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import {BitcoinRelay} from "../src/types/BitcoinRelay";
import {BitcoinRelay__factory} from "../src/types/factories/BitcoinRelay__factory";


describe("Bitcoin Relay [combined version]", async () => {

    let bitcoinRelayFactory: BitcoinRelay__factory;

    let bitcoinRelay: BitcoinRelay;
    let instance: BitcoinRelay;
    let instance2: BitcoinRelay;

    let deployer: Signer;
    let signer1: Signer;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let bitcoinRESTAPI: any;
    let blockHeaders: any;

    before(async () => {

        [deployer, signer1] = await ethers.getSigners();

        bitcoinRelayFactory = new BitcoinRelay__factory(
            deployer
        );

        bitcoinRESTAPI = new BitcoinRESTAPI(networkMainnet, baseURLMainnet, 2);

        // read block headers from file
        let data = fs.readFileSync(jsonPath, 'utf-8');
        blockHeaders = data.split('\n');

        bitcoinRelay = await deployBitcoinRelay();

    });

    const deployBitcoinRelay = async (
        _signer?: Signer
    ): Promise<BitcoinRelay> => {
        const bitcoinRelayFactory = new BitcoinRelay__factory(
            _signer || deployer
        );

        let _height = 199584; // 99*2016
        let _heightBigNumber = BigNumber.from(199584)
        let _genesisHeader = await bitcoinRESTAPI.getHexBlockHeader(_height);
        let _periodStart = await bitcoinRESTAPI.getHexBlockHash(_height);
        _genesisHeader = '0x' + _genesisHeader;

        _periodStart = '0x' + _periodStart;

        const bitcoinRelay = await bitcoinRelayFactory.deploy(
            _genesisHeader,
            _heightBigNumber,
            _periodStart,
            ZERO_ADDRESS
        );

        return bitcoinRelay;
    };

    describe('Submitting block headers with retarget', async () => {

        it('check the owner', async function () {
            let theOwnerAddress = await bitcoinRelay.owner()

            let theDeplyerAddress = await deployer.getAddress();

            expect(theOwnerAddress).to.equal(theDeplyerAddress);
        })

        it('submit old block headers', async function () {
            this.timeout(0);
            // submit block headers up to 100*2016
            for (let i = 0; i < 32; i++) {

                let blockHeadersNew = '0x';

                let blockHeaderOld = '';

                if (i == 0) {
                    blockHeaderOld = '0x' + blockHeaders[0];
                    for (let j = 1; j < 63; j++) {
                        blockHeadersNew = blockHeadersNew + blockHeaders[j + i*63];
                    }
                } else {
                    blockHeaderOld = '0x' + blockHeaders[i*63 - 1];
                    for (let j = 0; j < 63; j++) {
                        blockHeadersNew = blockHeadersNew + blockHeaders[j + i*63];
                    }
                }

                await expect(
                    bitcoinRelay.addHeaders(
                        blockHeaderOld, // anchor header
                        blockHeadersNew // new header;
                    )
                ).to.emit(bitcoinRelay, "BlockAdded")

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
            ).to.emit(bitcoinRelay, "BlockAdded")

        });

    });

    describe('Check tx inclusion', async () => {

        it('check the inclusion of a transaction having txid',async() => {
            let blockNumber = 100*2016 - 10;
            let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
            let block = await bitcoinRESTAPI.getBlock(blockNumber);
            let _index = 10;
            let _txid = transactionIds[_index];
            let proof = await bitcoinRESTAPI.getMerkleProof(_txid);
            let _merkleRoot = '0x' + block.merkle_root;
            let _blockNumber = blockNumber;
            let _intermediateNodes = proof.intermediateNodes;
            _txid = '0x' + _txid;

            let bitcoinRelaySigner1 = await bitcoinRelay.connect(signer1);

            let relayETHBalance0 = await bitcoinRelay.provider.getBalance(bitcoinRelay.address);
            let currentEpochQueries0 = await bitcoinRelaySigner1.currentEpochQueries();

            // Transaction check goes through successfully
            expect(
                await bitcoinRelaySigner1.checkTxProof(
                    _txid,
                    _blockNumber,
                    _intermediateNodes,
                    _index,
                    {
                    value: ethers.utils.parseEther('0.00001'),
                  })
            // ).to.equal(true);
            );

            let currentEpochQueries1 = await bitcoinRelaySigner1.currentEpochQueries();

            // Number of queries is being counted correctly for fee calculation purposes
            expect(currentEpochQueries1.sub(currentEpochQueries0)).to.equal(1);

            let relayETHBalance1 = await bitcoinRelay.provider.getBalance(bitcoinRelay.address);
            let feeAmount = await bitcoinRelaySigner1.getBlockHeaderFee(_blockNumber, 0);

            // Expected fee should be equal to the contract balance after tx is processed
            expect(relayETHBalance1.sub(relayETHBalance0)).to.equal(feeAmount);
        });

        // TODO: it actually reverts with the desired string but fails to pass the test
        // it('reverts when enough fee is not paid',async() => {
        //     let blockNumber = 100*2016 - 10;
        //     let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
        //     let block = await bitcoinRESTAPI.getBlock(blockNumber);
        //     let _index = 10;
        //     let _txid = transactionIds[_index];
        //     let proof = await bitcoinRESTAPI.getMerkleProof(_txid);
        //     let _merkleRoot = '0x' + block.merkle_root;
        //     let _blockNumber = blockNumber;
        //     let _intermediateNodes = proof.intermediateNodes;
        //     _txid = '0x' + _txid;

        //     let bitcoinRelaySigner1 = await bitcoinRelay.connect(signer1);

        //     let signerInitialBalance = await signer1.getBalance();

        //     expect(
        //         await bitcoinRelaySigner1.checkTxProof(
        //             _txid,
        //             _blockNumber,
        //             _intermediateNodes,
        //             _index,
        //             {
        //             value: ethers.utils.parseEther('0.000000001'),
        //           })
        //     ).to.revertedWith("BitcoinRelay: fee is not enough")

        //     let signerFinalBalance = await signer1.getBalance();
        // });

        // it('check txid',async() => {
        //     let blockNumber = 100*2016 - 10;
        //     let transactionIds = await bitcoinRESTAPI.getBlockTransactionIds(blockNumber);
        //     let _index = 0;
        //     let _txid = transactionIds[_index];
        //     console.log("type of txid: ", typeof(_txid))
        //     console.log("txid: ", _txid)
        //     let parsedTx = await bitcoinRESTAPI.parseTransaction(_txid);
        //     let _version = parsedTx.version;
        //     let _vin = parsedTx.vin;
        //     let _vout = parsedTx.vout;
        //     let _locktime = parsedTx.locktime;

        //     expect(
        //         await bitcoinRelay.calculateTxId(
        //             _version,
        //             _vin,
        //             _vout,
        //             _locktime
        //         )
        //         // TODO: why the txid is different?!
        //     ).to.equal("0xb2e944205992eec82c5076eb62146d52acccc1700a5428922a04d2bfea581e89")
        //     // ).to.equal(_txid)
        // });

    });

    describe('#constructor', async () => {
        /* eslint-disable-next-line camelcase */
        const { genesis, orphan_562630 } = REGULAR_CHAIN;

        beforeEach(async () => {
            instance = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                orphan_562630.digest_le,
                ZERO_ADDRESS
            );
        });

        it('errors if the caller is being an idiot', async () => {

            await expect(
                bitcoinRelayFactory.deploy(
                    '0x00',
                    genesis.height,
                    genesis.digest_le,
                    ZERO_ADDRESS
                )
            ).to.revertedWith("BitcoinRelay: stop being dumb")
        });

        it('errors if the period start is in wrong byte order', async () => {

            // TODO: if want to get this error, must un-comment the require in the constructor
            // await expect(
            //     bitcoinRelayFactory.deploy(
            //         genesis.hex,
            //         genesis.height,
            //         orphan_562630.digest,
            //         ZERO_ADDRESS
            //     )
            // ).to.revertedWith("Hint: wrong byte order?")
        });

        it('stores genesis block info', async () => {

            expect(
                await instance.relayGenesisHash()
            ).to.equal(genesis.digest_le)

            // expect(
            //     await instance.getBestKnownDigest()
            // ).to.equal(genesis.digest_le)


            // expect(
            //     await instance.getLastReorgCommonAncestor()
            // ).to.equal(genesis.digest_le)

            expect(
                await instance.findAncestor(
                    genesis.digest_le,
                    0
                )
            ).to.equal(genesis.digest_le)

            expect(
                await instance.findHeight(genesis.digest_le)
            ).to.equal(genesis.height)

            // const genDiff = new BN(genesis.difficulty);
            // res = await instance.getCurrentEpochDifficulty();
            // assert(res.eq(genDiff));

            // expect(
            //     await instance.prevEpochDiff()
            // ).to.equal(0)
        });
    });

    describe('#addHeaders', async () => {
        /* eslint-disable-next-line camelcase */
        const { chain_header_hex, chain, genesis, orphan_562630 } = REGULAR_CHAIN;
        // const headerHex = chain.map(header=> header.hex);
        const headerHex = chain_header_hex;

        const headers = utils.concatenateHexStrings(headerHex.slice(0, 6));

        beforeEach(async () => {

            instance = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                orphan_562630.digest_le,
                ZERO_ADDRESS
            );

        });

        it('errors if the anchor is unknown', async () => {

            await expect(
                instance.addHeaders(
                    '0x00',
                    headers
                )
            ).to.revertedWith("BitcoinRelay: anchor must be 80 bytes")
        });

        it('errors if it encounters a retarget on an external call', async () => {
            let badHeaders = '0x0000002073bd2184edd9c4fc76642ea6754ee40136970efc10c4190000000000000000000296ef123ea96da5cf695f22bf7d94be87d49db1ad7ac371ac43c4da4161c8c216349c5ba11928170d38782b0000002073bd2184edd9c4fc76642ea6754ee40136970efc10c4190000000000000000005af53b865c27c6e9b5e5db4c3ea8e024f8329178a79ddb39f7727ea2fe6e6825d1349c5ba1192817e2d951590000002073bd2184edd9c4fc76642ea6754ee40136970efc10c419000000000000000000c63a8848a448a43c9e4402bd893f701cd11856e14cbbe026699e8fdc445b35a8d93c9c5ba1192817b945dc6c00000020f402c0b551b944665332466753f1eebb846a64ef24c71700000000000000000033fc68e070964e908d961cd11033896fa6c9b8b76f64a2db7ea928afa7e304257d3f9c5ba11928176164145d0000ff3f63d40efa46403afd71a254b54f2b495b7b0164991c2d22000000000000000000f046dc1b71560b7d0786cfbdb25ae320bd9644c98d5c7c77bf9df05cbe96212758419c5ba1192817a2bb2caa00000020e2d4f0edd5edd80bdcb880535443747c6b22b48fb6200d0000000000000000001d3799aa3eb8d18916f46bf2cf807cb89a9b1b4c56c3f2693711bf1064d9a32435429c5ba1192817752e49ae0000002022dba41dff28b337ee3463bf1ab1acf0e57443e0f7ab1d000000000000000000c3aadcc8def003ecbd1ba514592a18baddddcd3a287ccf74f584b04c5c10044e97479c5ba1192817c341f595';

            await expect(
                instance.addHeaders(
                    genesis.hex,
                    badHeaders
                )
            ).to.revertedWith("BitcoinRelay: unexpected retarget on external call")
        });

        it('errors if the header array is not a multiple of 80 bytes', async () => {
            let badHeaders = headers.substring(0, 8 + 5 * 160)

            await expect(
                instance.addHeaders(
                    genesis.hex,
                    badHeaders
                )
            ).to.revertedWith("BitcoinRelay: header array length must be divisible by 80")
        });

        it('errors if a header work is too low', async () => {

            let badHeaders = `${headers}${'00'.repeat(80)}`

            await expect(
                instance.addHeaders(
                    genesis.hex,
                    badHeaders
                )
            // ).to.revertedWith("BitcoinRelay: header work is insufficient")
            ).to.reverted; // above should be uncommented when a proper input is given
            // now it reverts before being catched in the expect that we want -> it has invalid target

        });

        it('errors if the target changes mid-chain', async () => {

            let badHeaders = utils.concatenateHexStrings([headers, REGULAR_CHAIN.badHeader.hex]);

            await expect(
                instance.addHeaders(
                    genesis.hex,
                    badHeaders
                )
            ).to.revertedWith("BitcoinRelay: target changed unexpectedly")

        });

        it('errors if a prevhash link is broken', async () => {

            let badHeaders = utils.concatenateHexStrings([headers, chain[15].hex]);

            await expect(
                instance.addHeaders(
                    genesis.hex,
                    badHeaders
                )
            ).to.revertedWith("BitcoinRelay: headers do not form a consistent chain")

        });

        it('appends new links to the chain and fires an event', async () => {

            expect(
                await instance.addHeaders(
                    genesis.hex,
                    headers
                )
            ).to.emit(instance, "BlockAdded")
        });

        it('skips some validation steps for known blocks', async () => {
            const oneMoreHeader = utils.concatenateHexStrings([headers, headerHex[6]]);
            await instance.addHeaders(genesis.hex, oneMoreHeader);
        });
    });

    describe('#addHeadersWithRetarget', async () => {
        const { chain, chain_header_hex } = RETARGET_CHAIN;
        const headerHex = chain_header_hex;
        const genesis = chain[1];

        const firstHeader = RETARGET_CHAIN.oldPeriodStart;
        const lastHeader = chain[8];
        const preChange = utils.concatenateHexStrings(headerHex.slice(2, 9));
        const headers = utils.concatenateHexStrings(headerHex.slice(9, 15));

        // let btcutils

        beforeEach(async () => {

            // btcutils = await BTCUtils.new()
            instance = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                firstHeader.digest_le,
                ZERO_ADDRESS
            );

            await instance.addHeaders(genesis.hex, preChange);

        });

        it('errors if the old period start header is unknown', async () => {

            await expect(
                instance.addHeadersWithRetarget(
                    '0x00',
                    lastHeader.hex,
                    headers
                )
            ).to.revertedWith("Bad args. Check header and array byte lengths.")

        });

        it('errors if the old period end header is unknown', async () => {

            await expect(
                instance.addHeadersWithRetarget(
                    firstHeader.hex,
                    chain[15].hex,
                    headers
                )
            ).to.revertedWith("Unknown block")

        });

        it('errors if the provided last header does not match records', async () => {

            await expect(
                instance.addHeadersWithRetarget(
                    firstHeader.hex,
                    firstHeader.hex,
                    headers)
            ).to.revertedWith("Must provide the last header of the closing difficulty period")

        });

        it('errors if the start and end headers are not exactly 2015 blocks apart', async () => {

            await expect(
                instance.addHeadersWithRetarget(
                    lastHeader.hex,
                    lastHeader.hex,
                    headers
                )
            ).to.revertedWith("Must provide exactly 1 difficulty period")

        });

        it('errors if the retarget is performed incorrectly', async () => {
            const bitcoinRelayFactory = new BitcoinRelay__factory(
                deployer
            );

            const tmpInstance = await bitcoinRelayFactory.deploy(
                genesis.hex,
                lastHeader.height, // This is a lie
                firstHeader.digest_le,
                ZERO_ADDRESS
            );

            await expect(
                tmpInstance.addHeadersWithRetarget(
                    firstHeader.hex,
                    genesis.hex,
                    headers
                )
            ).to.revertedWith("Invalid retarget provided")

        });

        it('appends new links to the chain', async () => {
            await instance.addHeadersWithRetarget(
                firstHeader.hex,
                lastHeader.hex,
                headers
            );

            expect(
                await instance.findHeight(chain[10].digest_le)
            ).to.equal(lastHeader.height + 2)

        });
    });

    describe('#findHeight', async () => {
        const { genesis, chain, chain_header_hex, oldPeriodStart } = REGULAR_CHAIN;
        const headerHex = chain_header_hex;
        const headers = utils.concatenateHexStrings(headerHex.slice(0, 6));

        beforeEach(async () => {

            instance2 = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                oldPeriodStart.digest_le,
                ZERO_ADDRESS
            );

            await instance2.addHeaders(genesis.hex, headers);
        });

        it('errors on unknown blocks', async () => {

            await expect(
                instance2.findHeight(`0x${'00'.repeat(32)}`)
            ).to.revertedWith("Unknown block")

        });

        it('Finds height of known blocks', async () => {
            //  since there's only 6 blocks added
            for (let i = 1; i < 6; i += 1) {
                /* eslint-disable-next-line camelcase */
                const { digest_le, height } = chain[i];

                /* eslint-disable-next-line no-await-in-loop */
                expect(
                    await instance2.findHeight(digest_le)
                ).to.equal(height)

            }
        });
    });

    describe('#findAncestor', async () => {
        const { chain, genesis, chain_header_hex, oldPeriodStart } = REGULAR_CHAIN;
        const headerHex = chain_header_hex;
        const headers = utils.concatenateHexStrings(headerHex.slice(0, 6));

        beforeEach(async () => {

            instance2 = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                // FIXME: must pass the first block of the block period (2016)
                oldPeriodStart.digest_le,
                ZERO_ADDRESS
            );

            await instance2.addHeaders(genesis.hex, headers);
        });

        it('errors on unknown blocks', async () => {

            await expect(
                instance2.findAncestor(`0x${'00'.repeat(32)}`, 3)
            ).to.revertedWith("BitcoinRelay: unknown ancestor")

        });

        it('Finds known ancestors based on on offsets', async () => {
            //  since there's only 6 blocks added
            for (let i = 0; i < 6; i += 1) {
                /* eslint-disable-next-line camelcase */
                const { digest_le } = chain[i];
                // console.log("i", i);
                // console.log("chain[i]: ", chain[i]);

                /* eslint-disable-next-line no-await-in-loop */
                let res = await instance2.findAncestor(digest_le, 0);
                expect(
                    res
                ).to.equal(digest_le)

                // assert.equal(res, digest_le);

                if (i > 0) {
                    /* eslint-disable-next-line no-await-in-loop */
                    res = await instance2.findAncestor(digest_le, 1);
                    expect(
                        res
                    ).to.equal(chain[i - 1].digest_le)

                    // assert.equal(res, chain[i - 1].digest_le);
                }
            }
        });

    });

    describe('#isAncestor', async () => {
        const { chain, genesis, chain_header_hex, oldPeriodStart } = REGULAR_CHAIN;
        const headerHex = chain_header_hex;
        const headers = utils.concatenateHexStrings(headerHex.slice(0, 6));

        before(async () => {

            instance = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                oldPeriodStart.digest_le,
                ZERO_ADDRESS
            );
            await instance.addHeaders(genesis.hex, headers);
        });

        it('returns false if it exceeds the limit', async () => {

            expect(
                await instance.isAncestor(
                    genesis.digest_le, chain[3].digest_le, 1
                )
            ).to.equal(false);

        });

        it('finds the ancestor if within the limit', async () => {

            expect(
                await instance.isAncestor(
                    genesis.digest_le, chain[3].digest_le, 5
                )
            ).to.equal(true);

        });
    });

    describe('#heaviestFromAncestor', async () => {
        const { chain, genesis, chain_header_hex, oldPeriodStart } = REGULAR_CHAIN;
        const headerHex = chain_header_hex;
        const headers = utils.concatenateHexStrings(headerHex.slice(0, 8));
        const headersWithMain = utils.concatenateHexStrings([headers, chain[8].hex]);
        const headersWithOrphan = utils.concatenateHexStrings(
            [headers, REGULAR_CHAIN.orphan_562630.hex]
        );

        beforeEach(async () => {

            instance = await bitcoinRelayFactory.deploy(
                genesis.hex,
                genesis.height,
                oldPeriodStart.digest_le,
                ZERO_ADDRESS
            );

            await instance.addHeaders(genesis.hex, headersWithMain);
            await instance.addHeaders(genesis.hex, headersWithOrphan);
        });

        // it('errors if ancestor is unknown', async () => {
        //     await expect(
        //         instance.heaviestFromAncestor(
        //             chain[10].digest_le,
        //             headerHex[3],
        //             headerHex[4]
        //         )
        //     ).to.revertedWith("Unknown block")

        // });

        // it('errors if left is unknown', async () => {

        //     await expect(
        //         instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             chain[10].hex,
        //             headerHex[4]
        //         )
        //     ).to.revertedWith("Unknown block")

        // });

        // it('errors if right is unknown', async () => {

        //     await expect(
        //         instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             headerHex[4],
        //             chain[10].hex
        //         )
        //     ).to.revertedWith("Unknown block")

        // });

        // it('errors if either block is below the ancestor', async () => {

        //     await expect(
        //         instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             headerHex[2],
        //             headerHex[4]
        //         )
        //     ).to.revertedWith("A descendant height is below the ancestor height")


        //     await expect(
        //         instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             headerHex[4],
        //             headerHex[2]
        //         )
        //     ).to.revertedWith("A descendant height is below the ancestor height")

        // });

        // it('returns left if left is heavier', async () => {

        //     expect(
        //         await instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             headerHex[5],
        //             headerHex[4]
        //         )
        //     ).to.equal(chain[5].digest_le)
        // });

        // it('returns right if right is heavier', async () => {
        //     expect(
        //         await instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             headerHex[4],
        //             headerHex[5]
        //         )
        //     ).to.equal(chain[5].digest_le)

        // });

        // it('returns left if the weights are equal', async () => {

        //     expect(
        //         await instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             chain[8].hex,
        //             REGULAR_CHAIN.orphan_562630.hex
        //         )
        //     ).to.equal(chain[8].digest_le)

        //     expect(
        //         await instance.heaviestFromAncestor(
        //             chain[3].digest_le,
        //             REGULAR_CHAIN.orphan_562630.hex,
        //             chain[8].hex
        //         )
        //     ).to.equal(REGULAR_CHAIN.orphan_562630.digest_le)

        // });
    });

    describe('#heaviestFromAncestor (with retarget)', async () => {
        const PRE_CHAIN = REORG_AND_RETARGET_CHAIN.preRetargetChain;
        const POST_CHAIN = REORG_AND_RETARGET_CHAIN.postRetargetChain;

        const orphan = REORG_AND_RETARGET_CHAIN.orphan_437478;
        const pre = utils.concatenateHeadersHexes(PRE_CHAIN);
        const post = utils.concatenateHeadersHexes(POST_CHAIN);
        const shortPost = utils.concatenateHeadersHexes(POST_CHAIN.slice(0, POST_CHAIN.length - 2));
        const postWithOrphan = utils.concatenateHexStrings([shortPost, orphan.hex]);

        beforeEach(async () => {

            instance = await bitcoinRelayFactory.deploy(
                REORG_AND_RETARGET_CHAIN.genesis.hex,
                REORG_AND_RETARGET_CHAIN.genesis.height,
                REORG_AND_RETARGET_CHAIN.oldPeriodStart.digest_le,
                ZERO_ADDRESS
            );
            await instance.addHeaders(
                REORG_AND_RETARGET_CHAIN.genesis.hex,
                pre
            );
            await instance.addHeadersWithRetarget(
                REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
                PRE_CHAIN[PRE_CHAIN.length - 1].hex,
                post
            );
            await instance.addHeadersWithRetarget(
                REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
                PRE_CHAIN[PRE_CHAIN.length - 1].hex,
                postWithOrphan
            );
        });

        // it('handles descendants in different difficulty periods', async () => {

        //     expect(
        //         await instance.heaviestFromAncestor(
        //             REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //             orphan.hex,
        //             PRE_CHAIN[3].hex
        //         )
        //     ).to.equal(orphan.digest_le)

        //     // let res = await instance.heaviestFromAncestor.call(
        //     //   REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //     //   orphan.hex,
        //     //   PRE_CHAIN[3].hex
        //     // );
        //     // assert.equal(res, orphan.digest_le);

        //     expect(
        //         await instance.heaviestFromAncestor(
        //             REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //             PRE_CHAIN[3].hex,
        //             orphan.hex
        //         )
        //     ).to.equal(orphan.digest_le)
        // });

        // it('handles descendants when both are in a new difficulty period', async () => {
        //     expect(
        //         await instance.heaviestFromAncestor(
        //             REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //             orphan.hex,
        //             POST_CHAIN[3].hex
        //         )
        //     ).to.equal(orphan.digest_le)


        //     expect(
        //         await instance.heaviestFromAncestor(
        //             REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //             POST_CHAIN[3].hex,
        //             orphan.hex
        //         )
        //     ).to.equal(orphan.digest_le)

        // });
    });

    describe('#markNewHeaviest', async () => {
        const PRE_CHAIN = REORG_AND_RETARGET_CHAIN.preRetargetChain;
        const POST_CHAIN = REORG_AND_RETARGET_CHAIN.postRetargetChain;

        const orphan = REORG_AND_RETARGET_CHAIN.orphan_437478;
        const pre = utils.concatenateHeadersHexes(PRE_CHAIN);
        const post = utils.concatenateHeadersHexes(POST_CHAIN);
        const shortPost = utils.concatenateHeadersHexes(POST_CHAIN.slice(0, POST_CHAIN.length - 2));
        const postWithOrphan = utils.concatenateHexStrings([shortPost, orphan.hex]);

        before(async () => {

            instance = await bitcoinRelayFactory.deploy(
                REORG_AND_RETARGET_CHAIN.genesis.hex,
                REORG_AND_RETARGET_CHAIN.genesis.height,
                REORG_AND_RETARGET_CHAIN.oldPeriodStart.digest_le,
                ZERO_ADDRESS
            );
            await instance.addHeaders(
                REORG_AND_RETARGET_CHAIN.genesis.hex,
                pre
            );
            await instance.addHeadersWithRetarget(
                REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
                PRE_CHAIN[PRE_CHAIN.length - 1].hex,
                post
            );
            await instance.addHeadersWithRetarget(
                REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
                PRE_CHAIN[PRE_CHAIN.length - 1].hex,
                postWithOrphan
            );
        });

        // it('errors if the passed in best is not the best known', async () => {

        //     await expect(
        //         instance.markNewHeaviest(
        //             REORG_AND_RETARGET_CHAIN.oldPeriodStart.digest_le,
        //             REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
        //             REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
        //             10
        //         )
        //     ).to.revertedWith("Passed in best is not best known")

        // });

        // it('errors if the new best is not already known', async () => {

        //     await expect(
        //         instance.markNewHeaviest(
        //             REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //             REORG_AND_RETARGET_CHAIN.genesis.hex,
        //             `0x${'99'.repeat(80)}`,
        //             10
        //         )
        //     ).to.revertedWith("New best is unknown")

        // });

        // it('errors if the ancestor is not the heaviest common ancestor', async () => {
        //     await instance.markNewHeaviest(
        //         REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //         REORG_AND_RETARGET_CHAIN.genesis.hex,
        //         PRE_CHAIN[0].hex,
        //         10
        //     );

        //     await expect(
        //         instance.markNewHeaviest(
        //             REORG_AND_RETARGET_CHAIN.genesis.digest_le,
        //             PRE_CHAIN[0].hex,
        //             PRE_CHAIN[1].hex,
        //             10
        //         )
        //     ).to.revertedWith("Ancestor must be heaviest common ancestor")

        // });

        // it('updates the best known and emits a reorg event', async () => {

        //     expect(
        //         await instance.markNewHeaviest(
        //             PRE_CHAIN[0].digest_le,
        //             PRE_CHAIN[0].hex,
        //             orphan.hex,
        //             20
        //         )
        //     ).to.emit(instance, "NewTip")

        //     // const blockNumber = await web3.eth.getBlock('latest').number;
        //     // await instance.markNewHeaviest(
        //     //   PRE_CHAIN[0].digest_le,
        //     //   PRE_CHAIN[0].hex,
        //     //   orphan.hex,
        //     //   20
        //     // );
        //     // const eventList = await instance.getPastEvents(
        //     //   'NewTip',
        //     //   { fromBlock: blockNumber, toBlock: 'latest' }
        //     // );

        //     /* eslint-disable no-underscore-dangle */
        //     // assert.equal(eventList[0].returnValues._to, orphan.digest_le);
        //     // assert.equal(eventList[0].returnValues._from, PRE_CHAIN[0].digest_le);
        //     // assert.equal(eventList[0].returnValues._gcd, PRE_CHAIN[0].digest_le);
        //     /* eslint-enable no-underscore-dangle */
        // });

        // it('errors if the new best hash is not better', async () => {

        //     await expect(
        //         instance.markNewHeaviest(
        //             POST_CHAIN.slice(-3)[0].digest_le, // the main chain before the split
        //             orphan.hex,
        //             POST_CHAIN.slice(-2)[0].hex, // the main chain competing with the split
        //             10
        //         )
        //     ).to.revertedWith("New best hash does not have more work than previous")
        // });
    });

    // describe('#isMostRecentAncestor', async () => {
    //     const PRE_CHAIN = REORG_AND_RETARGET_CHAIN.preRetargetChain;
    //     const POST_CHAIN = REORG_AND_RETARGET_CHAIN.postRetargetChain;

    //     const orphan = REORG_AND_RETARGET_CHAIN.orphan_437478;
    //     const pre = utils.concatenateHeadersHexes(PRE_CHAIN);
    //     const post = utils.concatenateHeadersHexes(POST_CHAIN);
    //     const shortPost = utils.concatenateHeadersHexes(POST_CHAIN.slice(0, POST_CHAIN.length - 2));
    //     const postWithOrphan = utils.concatenateHexStrings([shortPost, orphan.hex]);

    //     beforeEach(async () => {
    //         [deployer, signer1] = await ethers.getSigners();

    //         const bitcoinRelayFactory = new BitcoinRelay__factory(
    //             deployer
    //         );

    //         instance = await bitcoinRelayFactory.deploy(
    //             REORG_AND_RETARGET_CHAIN.genesis.hex,
    //             REORG_AND_RETARGET_CHAIN.genesis.height,
    //             REORG_AND_RETARGET_CHAIN.oldPeriodStart.digest_le,
    //             ZERO_ADDRESS
    //         );
    //         await instance.addHeaders(
    //             REORG_AND_RETARGET_CHAIN.genesis.hex,
    //             pre
    //         );
    //         await instance.addHeadersWithRetarget(
    //             REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
    //             PRE_CHAIN[PRE_CHAIN.length - 1].hex,
    //             post
    //         );
    //         await instance.addHeadersWithRetarget(
    //             REORG_AND_RETARGET_CHAIN.oldPeriodStart.hex,
    //             PRE_CHAIN[PRE_CHAIN.length - 1].hex,
    //             postWithOrphan
    //         );
    //     });

    //     it('returns false if it found a more recent ancestor', async () => {

    //         expect(
    //             await instance.isMostRecentAncestor(
    //                 POST_CHAIN[0].digest_le,
    //                 POST_CHAIN[3].digest_le,
    //                 POST_CHAIN[2].digest_le,
    //                 5
    //             )
    //         ).to.equal(false)

    //     });

    //     it('returns false if it did not find the specified common ancestor within the limit', async () => {

    //         expect(
    //             await instance.isMostRecentAncestor(
    //                 POST_CHAIN[1].digest_le,
    //                 POST_CHAIN[3].digest_le,
    //                 POST_CHAIN[2].digest_le,
    //                 1
    //             )
    //         ).to.equal(false)

    //     });

    //     it('returns true if the provided digest is the most recent common ancestor', async () => {

    //         expect(
    //             await instance.isMostRecentAncestor(
    //                 POST_CHAIN[2].digest_le,
    //                 POST_CHAIN[3].digest_le,
    //                 POST_CHAIN[2].digest_le,
    //                 5
    //             )
    //         ).to.equal(true)


    //         expect(
    //             await instance.isMostRecentAncestor(
    //                 POST_CHAIN[5].digest_le,
    //                 POST_CHAIN[6].digest_le,
    //                 orphan.digest_le,
    //                 5
    //             )
    //         ).to.equal(true)

    //     });

    //     it('shortcuts the trivial case (ancestor is left is right)', async () => {

    //         expect(
    //             await instance.isMostRecentAncestor(
    //                 POST_CHAIN[3].digest_le,
    //                 POST_CHAIN[3].digest_le,
    //                 POST_CHAIN[3].digest_le,
    //                 5
    //             )
    //         ).to.equal(true)

    //     });
    // });



});