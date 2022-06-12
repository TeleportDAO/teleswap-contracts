const { MerkleTree } = require('merkletreejs');
const SHA256 = require('crypto-js/sha256');


getProof = (transactionIds, index) => {
  const leaves = transactionIds;
  const tree = new MerkleTree(leaves, SHA256);
  const root = tree.getRoot().toString('hex');
  const proof = tree.getProof(transactionIds[index]);
  return proof;
}

exports.getProof = getProof;