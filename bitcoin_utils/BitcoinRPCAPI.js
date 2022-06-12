var deasync = require('deasync');
var RpcClient = require('bitcoind-rpc');
const bitcoinJs = require('bitcoinjs-lib');
const {MerkleTree} = require('merkletreejs');
const SHA256 = require('crypto-js/sha256');
const BigNumber = require('bignumber.js');
let coinSelect = require('coinselect');
const {networks} = require('bitcoinjs-lib');
const networkTestnet = {name: 'testnet', ...networks.testnet};
const { BitcoinAddress } = require('bech32-buffer');
const bs58 = require('bs58');

class BitcoinRPCAPI {

  constructor(rpcConfig) {
    this.rpc = new RpcClient(rpcConfig);
    this.networkTestnet = networkTestnet;
  }

  async createWallet(walletName) {
    let _result;
    this.rpc.createWallet(walletName, async function (err, result) {
      if (err) {
        _result = "error";
        console.error(err);
      } else {
        _result = result;
        console.log(walletName, "wallet was created");
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
  }

  async decodeBase58 (bitcoinAddress) {
    const decodedAddress = bs58.decode(bitcoinAddress);
    const decodedAddressHex = Buffer.from(decodedAddress).toString('hex');
    return '0x' + decodedAddressHex;
  }

  async decodeBech32 (segwitAddress) {
    const address = BitcoinAddress.decode(segwitAddress);
    const hexAddress =  Buffer.from(address.data).toString('hex');
    return '0x' + hexAddress;
  }

  async scanTxOutSet(address) {
    let utxos;
    let _address = "addr(" + address + ")";
    this.rpc.scantxoutset("start", [_address], async function (err, _utxos) {
      if (err) {
        utxos = "error";
        console.error(err);
      } else {
        utxos = _utxos.result.unspents;
      }
    })
    while (utxos == null) {
      deasync.runLoopOnce();
    }
    return utxos;
  }
  
  async deriveAddressFromPubKey (pubKey, network) {
    let {address} = bitcoinJs.payments.p2pkh({network: network, pubkey: Buffer.from(pubKey, 'hex')});
    return address;
  }

  async walletProcessPSBT(unsignedPSBT) {
    let signedPSBT;
    this.rpc.walletprocesspsbt(unsignedPSBT, true, async function (err, _signedPSBT) {
      if (err) {
        signedPSBT = "error";
        console.error(err);
      } else {
        signedPSBT = _signedPSBT.result.psbt;
        // console.log(signedPSBT);
      }
    })
    while (signedPSBT == null) {
      deasync.runLoopOnce();
    }
    return signedPSBT;
  } 

  async finalizePSBT(signedPSBT) {
    let rawSignedPSBT;
    this.rpc.finalizePSBT(signedPSBT, async function (err, _rawSignedPSBT) {
      if (err) {
        rawSignedPSBT = "error";
        console.error(err);
      } else {
        rawSignedPSBT = _rawSignedPSBT.result.hex;
        // console.log(rawSignedPSBT);
      }
    })
    while (rawSignedPSBT == null) {
      deasync.runLoopOnce();
    }
    return rawSignedPSBT;
  }

  async sendRawTransaction(rawTransaction) {
    let result;
    this.rpc.sendrawtransaction(rawTransaction, async function (err, _result) {
      if (err) {
        result = "error";
        console.error(err);
      } else {
        result = _result.result;
        console.log(result);
      }
    })
    while (result == null) {
      deasync.runLoopOnce();
    }
    return result;
  }

  async getNewAddress() {
    let _result;
    this.rpc.getNewAddress(async function (err, result) {
      if (err) {
        _result = "error";
        console.error(err);
      } else {
        _result = result;
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
  }

  async getBlockCount() {
    let _lastBlockHeight;
    this.rpc.getBlockCount(async function (err, lastBlockHeight) {
      if (err) {
        _lastBlockHeight = "error";
        console.error(err);
      } else {
        _lastBlockHeight = lastBlockHeight.result;
      }
    })
    while (_lastBlockHeight == null) {
      deasync.runLoopOnce();
    }
    return _lastBlockHeight;
  }

  // doubleSHA256(message) {
  //   console.log(message);
  //   console.log(sha256(message));
  //   ripemd160(sha256(message)).then(console.log)
  //   // console.log(ripemd160(sha256(message)));
  // }

  async generateToAddress(numberOfBlocks, walletAddress) {
    let _numberOfCreatedBlocks;
    this.rpc.generateToAddress(numberOfBlocks, walletAddress, async function (err, numberOfCreatedBlocks) {
      if (err) {
        numberOfCreatedBlocks = "error";
        console.error(err);
      } else {
        _numberOfCreatedBlocks = numberOfCreatedBlocks;
        // console.log(numberOfBlocks, "blocks were created");
      }
    })
    while (_numberOfCreatedBlocks == null) {
      deasync.runLoopOnce();
    }
  }

  async createMultiSig(numberOfRequiredSignatures, publicKeys) {
    let _result;
    this.rpc.createmultisig(numberOfRequiredSignatures, publicKeys, async function (err, result) {
      if (err) {
        _result = "error";
        console.error(err);
      } else {
        _result = [result.result.address, result.result.redeemScript];
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
    return _result;
  } 

  async createPSBT(inputs, outputs) {
    let unsignedPSBT;
    this.rpc.createpsbt(inputs, outputs, async function (err, _unsignedPSBT) {
      if (err) {
        unsignedPSBT = "error";
        console.error(err);
      } else {
        unsignedPSBT = _unsignedPSBT.result;
      }
    })
    while (unsignedPSBT == null) {
      deasync.runLoopOnce();
    }
    return unsignedPSBT;
  } 

  async createRawTransaction(inputs, outputs) {
    let rawTransaction;
    this.rpc.createrawtransaction(inputs, outputs, async function (err, _rawTransaction) {
      if (err) {
        rawTransaction = "error";
        console.error(err);
      } else {
        rawTransaction = _rawTransaction.result;
      }
    })
    while (rawTransaction == null) {
      deasync.runLoopOnce();
    }
    return rawTransaction;
  } 

  async fundedRawTransaction(hexRawTransaction) {
    let fundedRawTransaction;
    this.rpc.fundrawtransaction(hexRawTransaction, async function (err, _fundedRawTransaction) {
      if (err) {
        fundedRawTransaction = "error";
        console.error(err);
      } else {
        fundedRawTransaction = _fundedRawTransaction.result['hex'];
      }
    })
    while (fundedRawTransaction == null) {
      deasync.runLoopOnce();
    }
    return fundedRawTransaction;
  } 

  async convertToPSBT(rawTransaction) {
    let unsignedPSBT;
    this.rpc.converttopsbt(rawTransaction, async function (err, _unsignedPSBT) {
      if (err) {
        unsignedPSBT = "error";
        console.error(err);
      } else {
        unsignedPSBT = _unsignedPSBT.result;
      }
    })
    while (unsignedPSBT == null) {
      deasync.runLoopOnce();
    }
    return unsignedPSBT;
  } 

  async generateBlock(address, transactions) {
    let _result;
    this.rpc.generateBlock(address, transactions, async function (err, result) {
      if (err) {
        console.error(err);
      } else {
        _result = result.result;
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
    return _result;
  }

  async getBlock(blockHash) {
    let _blockInfo;
    this.rpc.getBlock(blockHash, async function (err, blockInfo) {
      if (err) {
        console.error(err);
      } else {
        _blockInfo = blockInfo.result;
        console.log("blockInfo:\n", _blockInfo);
      }
    })
    while (_blockInfo == null) {
      deasync.runLoopOnce();
    }
    return _blockInfo;
  }
  
  async getBlockHash(blockNumber) {
    let _blockHash;
    this.rpc.getBlockHash(blockNumber, async function (err, blockHash) {
      if (err) {
        console.error(err);
      } else {
        _blockHash = blockHash.result;
      }
    })
    while (_blockHash == null) {
      deasync.runLoopOnce();
    }
    return _blockHash;
  }

  async getJSONBlock(blockNumber) {
    let _blockHash;
    let _block;
    _blockHash = await this.getBlockHash(blockNumber);
    this.rpc.getBlock(_blockHash, 1, async function (err, block) {
      if (err) {
        console.error(err);
      } else {
        _block = block.result;
      }
    })
    while (_block == null) {
      deasync.runLoopOnce();
    }
    return _block;
  }

  async getHexBlockHash(blockNumber) {
    let _blockHash;
    this.rpc.getBlockHash(blockNumber, async function (err, blockHash) {
      if (err) {
        console.error(err);
      } else {
        _blockHash = blockHash.result;
      }
    })
    while (_blockHash == null) {
      deasync.runLoopOnce();
    }
    return '0x'+_blockHash;
  }

  async getHexBlockHashReversed(blockNumber) {
    let _blockHash;
    this.rpc.getBlockHash(blockNumber, async function (err, blockHash) {
      if (err) {
        console.error(err);
      } else {
        _blockHash = blockHash.result;
      }
    })
    while (_blockHash == null) {
      deasync.runLoopOnce();
    }
    return '0x'+_blockHash.match(/[a-fA-F0-9]{2}/g).reverse().join('');
  }

  async getBlockHeader(blockNumber) {
    let _blockHeader;
    let _blockHash;
    _blockHash = await this.getBlockHash(blockNumber);
    this.rpc.getBlockHeader(_blockHash, false, function (err, blockHeader) {
      if (err) {
        console.error(err);
      } else {
        _blockHeader = blockHeader.result;
      }
    })
    while (_blockHeader == null) {
      deasync.runLoopOnce();
    }
    return _blockHeader;
  }

  async getJSONBlockHeader(blockNumber) {
    let _blockHeader;
    let _blockHash;
    _blockHash = await this.getBlockHash(blockNumber);
    this.rpc.getBlockHeader(_blockHash, true, function (err, blockHeader) {
      if (err) {
        console.error(err);
      } else {
        _blockHeader = blockHeader.result;
      }
    })
    while (_blockHeader == null) {
      deasync.runLoopOnce();
    }
    return _blockHeader;
  }

  async getHexBlockHeader(blockNumber) {
    let _blockHeader;
    let _blockHash;
    _blockHash = await this.getBlockHash(blockNumber);
    this.rpc.getBlockHeader(_blockHash, false, function (err, blockHeader) {
      if (err) {
        console.error(err);
      } else {
        _blockHeader = blockHeader.result;
      }
    })
    while (_blockHeader == null) {
      deasync.runLoopOnce();
    }
    return '0x'+_blockHeader;
  } 

  async getHexBlockHeaders(startBlockNumber, endBlockNumber) {
    let blockHeaders = [];
    let blockHeader;

    for (let i = startBlockNumber; i < endBlockNumber + 1; i++) {
      blockHeader = await this.getBlockHeader(i);
      blockHeaders = blockHeaders + blockHeader;
    }

    return '0x' + blockHeaders;
  } 

  async send(address, amount, hexData) {
    let _result;
    let arr = [[address, amount], ['data', hexData]];
    let output = Object.fromEntries(arr);
    this.rpc.send(output, function (err, result) {
      if (err) {
        console.error(err);
      } else {
        _result = result.result;
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
    return _result; // _result.txid gives txid
  }

  async sendToAddress(address, amount) {
    let _result;
    this.rpc.sendtoaddress(address, amount, false, function (err, result) {
      if (err) {
        console.error(err);
      } else {
        _result = result.result;
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
    return _result;
  }

  async getInclusionProof(transactionId, blockNumber) {
    let _blockHash;
    let _inclusionProof;
    _blockHash = await this.getBlockHash(blockNumber);
    let transactions = [transactionId];
    this.rpc.getTxOutProof(transactions, _blockHash, function (err, inclusionProof) {
      if (err) {
        console.error(err);
        _inclusionProof = err;
      } else {
        _inclusionProof = inclusionProof.result;
      }
    })

    while (_inclusionProof == null) {
      deasync.runLoopOnce();
    }
    return _inclusionProof;
  }

  async getTxOut(transactionId, outputNumber) {
    let _result;
    this.rpc.gettxout(transactionId, outputNumber, function (err, txInfo) {
      if (err) {
        console.error(err);
        _result = err;
      } else {
        _result = txInfo.result;
        // console.log("transactionInfo:\n", _result);
      }
    })
    while (_result == null) {
      deasync.runLoopOnce();
    }
    return _result;
  }

  reverseBytes(hexInput) {
    let inputLength = hexInput.length;
    let reversedInput = '';
    for (let i = 0; i < inputLength; i = i + 2) {
      reversedInput = reversedInput + hexInput.slice(inputLength-i-2, inputLength-i)
    }
    return reversedInput;
  }

  async getMerkleProofHavingBlockNumber(transactionId, blockNumber) {
    let transactionIndex;
    let block = await this.getJSONBlock(blockNumber); 
    let transactionIds = block.tx;
    // make transaction ids LE
    for (let i = 0; i < transactionIds.length; i++) {
      if (transactionIds[i] == transactionId) {
        transactionIndex = i;
      }
      transactionIds[i] = this.reverseBytes(transactionIds[i]);
    }
    const leaves = transactionIds;
    const tree = new MerkleTree(leaves, SHA256);
    const merkleRoot = tree.getHexRoot(); // TODO: this merkle root is not equal to the block merkle root
    const merkleProof = tree.getHexProof(transactionIds[transactionIndex]); // return array of hex
    var intermediateNodes = [];
    for (let i = 0; i < merkleProof.length; i++) {
      intermediateNodes = intermediateNodes + merkleProof[i].slice(2, merkleProof[i].length)
    }
    intermediateNodes = '0x' + intermediateNodes;
    return [merkleRoot, intermediateNodes, transactionIndex];
  }

  async getMerkleProof(transactionId) {
    // let transactionIdLE = this.reverseBytes(transactionId);
    let transactionInfo = await this.getTransactionInfo(transactionId);
    let transactionIndex = transactionInfo.blockindex;
    let blockHeight = transactionInfo.blockheight;
    // let _proof = await this.getInclusionProof(transactionId, blockHeight);
    // console.log("transactionId", transactionId);
    // console.log("_proof", _proof);
    let block = await this.getJSONBlock(blockHeight); 
    // console.log(block);
    let transactionIds = block.tx;
    // make transaction ids LE
    for (let i = 0; i < transactionIds.length; i++) {
      transactionIds[i] = this.reverseBytes(transactionIds[i]);
    }
    const leaves = transactionIds;
    const tree = new MerkleTree(leaves, SHA256);
    const merkleRoot = tree.getHexRoot(); // TODO: this merkle root is not equal to the block merkle root
    const merkleProof = tree.getHexProof(transactionIds[transactionIndex]); // return array of hex
    var intermediateNodes = [];
    for (let i = 0; i < merkleProof.length; i++) {
      intermediateNodes = intermediateNodes + merkleProof[i].slice(2, merkleProof[i].length)
    }
    intermediateNodes = '0x' + intermediateNodes;
    return [merkleRoot, intermediateNodes, transactionIndex];
  }

  async getTransactionInfo(transactionId) {
    let _transactionInfo;
    this.rpc.getTransaction(transactionId, function (err, transactionInfo) {
      if (err) {
        console.error(err);
        _transactionInfo = err;
      } else {
        _transactionInfo = transactionInfo.result;
        // console.log("transactionInfo:\n", _transactionInfo);
      }
    })
    while (_transactionInfo == null) {
      deasync.runLoopOnce();
    }
    return _transactionInfo;
  }

  async getRawTransactionHavingBlockNumber(transactionId, blockNumber) {
    let _rawTransaction;
    let _blockHash;
    _blockHash = await this.getBlockHash(blockNumber);
    this.rpc.getRawTransaction(transactionId, false, _blockHash, function (err, rawTransaction) {
      if (err) {
        console.error(err);
      } else {
        _rawTransaction = rawTransaction.result;
      }
    })
    while (_rawTransaction == null) {
      deasync.runLoopOnce();
    }
    return _rawTransaction;
  }

  async getRawTransactionHavingBlockHash(transactionId, blockHash) {
    // if user does not give the block hash, it will search in the mempool for that transaction
    let _rawTransaction;
    this.rpc.getRawTransaction(transactionId, false, blockHash, function (err, rawTransaction) {
      if (err) {
        console.error(err);
      } else {
        _rawTransaction = rawTransaction.result;
        // console.log("rawTransaction:\n", _rawTransaction);
      }
    })
    while (_rawTransaction == null) {
      deasync.runLoopOnce();
    }
    return _rawTransaction;
  }

  async getHexRawTransaction(transactionId, blockNumber) {
    let _rawTransaction = await this.getRawTransactionHavingBlockNumber(transactionId, blockNumber);
    return '0x' +_rawTransaction;
  }

  async decodeRawTransaction(rawTransaction) {
    let _decodedTransaction;
    this.rpc.decodeRawTransaction(rawTransaction, function (err, decodedTransaction) {
      if (err) {
        console.error(err);
      } else {
        _decodedTransaction = decodedTransaction.result;
      }
    })
    while (_decodedTransaction == null) {
      deasync.runLoopOnce();
    }
    return _decodedTransaction;
  }

  async parseTransaction(transactionId, blockNumber) {
    let rawTransaction = await this.getRawTransactionHavingBlockNumber(transactionId, blockNumber);
    let result = await this.parseRawTransaction(rawTransaction);
    let version = result[0];
    let flag = result[1];
    let vin = result[2];
    let vout = result[3];
    let witness = result[4];
    let locktime = result[5];
    return {
      'version': version, 
      'flag': flag, 
      'vin': vin, 
      'vout': vout, 
      'witness': witness, 
      'locktime': locktime
    };
  }

  parseRawTransaction(rawTransaction) { // TODO: should be modified to support parsing of transactions that include segwit addresses
    let version = rawTransaction.slice(0, 8);
    let flag = rawTransaction.slice(8,12); //0x0001 is flag in segwit transactions
    let vinLastIndex = rawTransaction.lastIndexOf("ffffffff") + 8;
    if(vinLastIndex == 7) { // in the case that the transaction has not been finalized yet
      vinLastIndex = rawTransaction.lastIndexOf("feffffff") + 8;
    }
    let numberOfOutputsHex = rawTransaction.slice(vinLastIndex, vinLastIndex + 2);
    let numberOfOutputs = parseInt(numberOfOutputsHex, 16);;
    let outputStartIndex = vinLastIndex + 2;
    let vout = numberOfOutputsHex;
    let i;
    for(i = 0; i < numberOfOutputs; i++) {
      var scriptLengthHex = rawTransaction.slice(outputStartIndex + 16, outputStartIndex + 16 + 2);
      var scriptLength = parseInt(scriptLengthHex, 16)*2; // each byte = 2 hex character
      vout = vout + rawTransaction.slice(outputStartIndex, outputStartIndex + 16 + 2 + scriptLength);
      outputStartIndex = outputStartIndex + 16 + 2 + scriptLength;
    }
    let voutLastIndex = outputStartIndex;
    version = '0x' + version;
    flag = '0x' + flag;
    let vin = '0x' + rawTransaction.slice(12, vinLastIndex);
    vout = '0x' + vout;
    let witness = '0x' + rawTransaction.slice(voutLastIndex, rawTransaction.length - 8);
    let locktime = '0x' + rawTransaction.slice(rawTransaction.length - 8, rawTransaction.length);
    return [version, flag, vin, vout, witness, locktime];
  }

  async signAndSendTransaction(userAddress, recipientAddresses, sendingAmounts, data, _feeRate) {
   
    // find UTXOs
    let utxos = await this.scanTxOutSet(userAddress);
    let _utxos = utxos.map((utxo) => ({
        txid: utxo.txid,
        vout: utxo.vout,
        value: BigNumber(utxo.amount).times(1e8).toNumber()
    }));
    console.log(_utxos);

    // define targets
    let targets = recipientAddresses.map((sendAddress, i) => ({
        address: sendAddress,
        value: BigNumber(sendingAmounts[i]).times(1e8).toNumber()
    }));

    // fee rate (satoshis per byte)
    let feeRate = _feeRate; 
    
    let {inputs, outputs, fee} = await coinSelect(_utxos, targets, feeRate);

    // define inputs
    let _inputs = inputs.map((input) => ({
        txid: input.txid,
        vout: input.vout
    }));

    // define outputs
    let _outputs = [];
    for (i = 0; i < outputs.length; i++) {
        output = outputs[i];
        if (output.address != undefined) {
            _output = [[output.address, BigNumber(output.value).div(1e8).toNumber()]];
            __output = Object.fromEntries(_output);
            _outputs.push(__output);
        } else {
            _output = [[userAddress, BigNumber(output.value).div(1e8).toNumber()]];
            __output = Object.fromEntries(_output);
            _outputs.push(__output);
        }
    }

    // add arbitrary data
    _outputs.push({data});

    unsignedPSBT = await this.createPSBT(_inputs, _outputs);
    let signedPSBT = await this.walletProcessPSBT(unsignedPSBT);
    // TODO: use sign function to sign PSBT using user's wallet
    // let signedPSBT = await sign(userAddress, inputs, unsignedPSBT);
    let rawSignedPSBT = await this.finalizePSBT(signedPSBT);
    await this.sendRawTransaction(rawSignedPSBT);
  }

}

exports.BitcoinRPCAPI = BitcoinRPCAPI;