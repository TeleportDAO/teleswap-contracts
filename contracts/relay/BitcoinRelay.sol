pragma solidity ^0.7.6;

/** @title Relay */
/** @author Summa (https://summa.one) */

import "../libraries/SafeMath.sol";
import "../libraries/TypedMemView.sol";
import "../libraries/ViewBTC.sol";
import "../libraries/ViewSPV.sol";
import "./interfaces/IBitcoinRelay.sol";
import "../routers/interfaces/IExchangeRouter.sol";
import "../erc20/interfaces/IERC20.sol";
import "hardhat/console.sol";

contract BitcoinRelay is IBitcoinRelay {
    using SafeMath for uint256;
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ViewBTC for bytes29;
    using ViewSPV for bytes29;

    /* using BytesLib for bytes;
    using BTCUtils for bytes;
    using ValidateSPV for bytes; */

    address public owner;

    uint public override initialHeight;
    uint public override lastSubmittedHeight;
    uint public override finalizationParameter;

    bytes32 public override relayGenesisHash;
    mapping(bytes32 => bytes32) internal previousBlock;
    mapping(bytes32 => uint256) internal blockHeight;
    mapping(uint => blockHeader[]) private chain;

    uint256 internal currentEpochDiff;
    uint256 internal prevEpochDiff;

    // Reward parameters
    address public override TeleportDAOToken;
    uint public override relayerPercentageFee; // Multiplied by 100 - greater than 100
    uint public override submissionGasUsed;
    uint public override epochLength;
    uint public override lastEpochQueries;
    uint public override baseQueries;
    address public override exchangeRouter;
    address public override wrappedNativeToken;
    mapping (uint => uint) private numberOfQueries;

    // TODO: prevent reverting when treasury (to pay relayers) gets empty but a relayer still wants to submit
    // TODO: manual buyback (called only by owner)
    // TODO: handle the case when TDT is not released yet (and to start incentive program when is released)
    // TODO: relayer incentive program (to release like 2% of TDTs in like 10 years)
    // TODO: users pay fees only using TNT for now (otherwise, cuz TDT is voletile and has low price, we should release
    // lots of TDT to compensate Relayers and give them the fees)
    // TODO: extra relayer fee is paid in TDT (incentive program) but the main relayer submission cost gets compensated with
    // the user fee in TNT. If treasury is out of TNT, relayers should be able to continue with no fee if they'd like to.
    // TODO: add MMR for the first block submitted on the relay and add check proof function so users can use previous data

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    /// @notice                   Gives a starting point for the relay
    /// @param  _genesisHeader    The starting header
    /// @param  _height           The starting height
    /// @param  _periodStart      The hash of the first header in the genesis epoch
    constructor(
        bytes memory _genesisHeader,
        uint256 _height,
        bytes32 _periodStart,
        address _TeleportDAOToken,
        address _exchangeRouter
    ) public {
        bytes29 _genesisView = _genesisHeader.ref(0).tryAsHeader();
        require(_genesisView.notNull(), "BitcoinRelay: stop being dumb");
        bytes32 _genesisHash = _genesisView.hash256();
        // Add the initial block header to the chain
        blockHeader memory newBlockHeader;
        newBlockHeader.selfHash = _genesisHash;
        newBlockHeader.merkleRoot = _genesisView.merkleRoot();
        newBlockHeader.relayer = msg.sender;
        chain[_height].push(newBlockHeader);

        // require(
        //     _periodStart & bytes32(0x0000000000000000000000000000000000000000000000000000000000ffffff) == bytes32(0),
        //     "Period start hash does not have work. Hint: wrong byte order?");
        relayGenesisHash = _genesisHash;
        blockHeight[_genesisHash] = _height;
        blockHeight[_periodStart] = _height.sub(_height % 2016);
        // Added parameters
        finalizationParameter = 1; // TODO: edit it
        lastSubmittedHeight = _height;
        initialHeight = _height;
        // Reward parameters
        TeleportDAOToken = _TeleportDAOToken;
        relayerPercentageFee = 0; // TODO: edit it;
        epochLength = 1;
        baseQueries = epochLength;
        lastEpochQueries = baseQueries;
        submissionGasUsed = 100000; // TODO: edit it
        exchangeRouter = _exchangeRouter;
        if (exchangeRouter != address(0)) {
            wrappedNativeToken = IExchangeRouter(exchangeRouter).WAVAX(); // call exchangeRouter to get wrappedNativeToken address
        }

        owner = msg.sender;
    }

    fallback () external payable {
    }

    /// @notice             Getter for an specific block header's hash in the stored chain
    /// @param  _height     The height of the desired block header
    /// @param  _index      The index of the desired block header in that height
    /// @return             Block header's hash
    function getBlockHeaderHash (uint _height, uint _index) external view override returns(bytes32) {
        return _revertBytes32(chain[_height][_index].selfHash);
    }

    /// @notice             Getter for the number of block headers in the same height
    /// @dev                This shows the number of temporary forks in that specific height
    /// @param  _height     The desired height of the blockchain
    /// @return             Number of block headers stored in the same height
    function getNumberOfSubmittedHeaders (uint _height) external view override returns (uint) {
        return chain[_height].length;
    }

    /// @notice             Getter for available TDT in treasury
    /// @return             Amount of TDT available in Relay treasury
    function availableTDT() external view override returns(uint) {
        // TODO
        return 0;
    }

    /// @notice             Getter for available target native token in treasury
    /// @return             Amount of target blockchain native token available in Relay treasury
    function availableTNT() external view override returns(uint) {
        // TODO
        return 0;
    }

    /// @notice         Finds the height of a header by its hash
    /// @dev            Will fail if the header is unknown
    /// @param _hash  The header hash to search for
    /// @return         The height of the header, or error if unknown
    function findHeight(bytes32 _hash) external view override returns (uint256) {
        return _findHeight(_hash);
    }

    /// @notice         Finds an ancestor for a block by its hash
    /// @dev            Will fail if the header is unknown
    /// @param _hash  The header hash to search for
    /// @return         The height of the header, or error if unknown
    function findAncestor(bytes32 _hash, uint256 _offset) external view override returns (bytes32) {
        return _findAncestor(_hash, _offset);
    }

    /// @notice             Checks if a hash is an ancestor of the current one
    /// @dev                Limit the amount of lookups (and thus gas usage) with _limit
    /// @param _ancestor    The prospective ancestor
    /// @param _descendant  The descendant to check
    /// @param _limit       The maximum number of blocks to check
    /// @return             true if ancestor is at most limit blocks lower than descendant, otherwise false
    function isAncestor(bytes32 _ancestor, bytes32 _descendant, uint256 _limit) external view override returns (bool) {
        return _isAncestor(_ancestor, _descendant, _limit);
    }

    /// @notice                             Setter for finalizationParameter
    /// @dev                                This might change if finalization rule of the source chain gets updated
    /// @param _finalizationParameter       The finalization parameter of the source chain
    function setFinalizationParameter(uint _finalizationParameter) external override onlyOwner {
        finalizationParameter = _finalizationParameter;
    }

    /// @notice                             Setter for relayerPercentageFee
    /// @dev                                This is updated when we want to change the Relayer reward
    /// @param _relayerPercentageFee               Ratio > 1 that determines percentage of reward to the Relayer
    function setRelayerPercentageFee(uint _relayerPercentageFee) external override onlyOwner {
        relayerPercentageFee = _relayerPercentageFee;
    }

    /// @notice                             Setter for epochLength
    /// @param _epochLength                 The length of epochs for estimating the user queries hence their fees
    function setEpochLength(uint _epochLength) external override onlyOwner {
        epochLength = _epochLength;
    }

    /// @notice                             Setter for baseQueries
    /// @param _baseQueries                 The base amount of queries we assume in each epoch
    ///                                     (This is for preventing user fees to grow significantly)
    function setBaseQueries(uint _baseQueries) external override onlyOwner {
        baseQueries = _baseQueries;
    }

    /// @notice                             Setter for submissionGasUsed
    /// @dev                                This is updated when the smart contract changes the way of getting block headers
    /// @param _submissionGasUsed           The gas used for submitting one block header
    function setSubmissionGasUsed(uint _submissionGasUsed) external override onlyOwner {
        submissionGasUsed = _submissionGasUsed;
    }

    /// @notice                             Setter for exchangeRouter
    /// @dev                                This is updated when we want to use another exchange
    /// @param _exchangeRouter              The contract address to use for exchanging tokens and
    ///                                     reading prices (for buyback and paying fees)
    function setExchangeRouter(address _exchangeRouter) external override onlyOwner {
        exchangeRouter = _exchangeRouter;
    }

    /// @notice                         Checks if a tx is included and finalized on the source blockchain
    /// @dev                            Checks if the block is finalized, and Merkle proof is correct
    /// @param  _txid                   Desired transaction's tx Id
    /// @param  _blockHeight            Block height of the desired tx
    /// @param  _intermediateNodes      Part of the Merkle proof for the desired tx
    /// @param  _index                  Part of the Merkle proof for the desired tx
    /// @return                         True if the provided tx is confirmed on the source blockchain, False otherwise
    function checkTxProof (
        bytes32 _txid, // In BE form
        uint _blockHeight,
        bytes calldata _intermediateNodes, // In LE form
        uint _index
    ) external view override returns (bool) {
        // Check for block confirmation
        // FIXME: change 6 with something different
        if (_blockHeight + 6 < lastSubmittedHeight + 1) {
            for (uint256 i = 0; i < chain[_blockHeight].length; i = i.add(1)) {
                bytes32 _merkleRoot = _revertBytes32(chain[_blockHeight][i].merkleRoot);
                bytes29 intermediateNodes = _intermediateNodes.ref(0).tryAsMerkleArray(); // Check for errors if any
                bytes32 txIdLE = _revertBytes32(_txid);
                if (ViewSPV.prove(txIdLE, _merkleRoot, intermediateNodes, _index)) {
                    // _getFee();
                    return true;
                }
            }
            require(false, "BitcoinRelay: tx has not been included");
        } else {
            return false;
        }
    }

    /// @notice             Adds headers to storage after validating
    /// @dev                We check integrity and consistency of the header chain
    /// @param  _anchor     The header immediately preceeding the new chain
    /// @param  _headers    A tightly-packed list of 80-byte Bitcoin headers
    /// @return             True if successfully written, error otherwise
    function addHeaders(bytes calldata _anchor, bytes calldata _headers) external override returns (bool) {
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();
        bytes29 _anchorView = _anchor.ref(0).tryAsHeader();

        require(_headersView.notNull(), "BitcoinRelay: header array length must be divisible by 80");
        require(_anchorView.notNull(), "BitcoinRelay: anchor must be 80 bytes");

        return _addHeaders(_anchorView, _headersView, false);
    }

    /// @notice                       Adds headers to storage, performs additional validation of retarget
    /// @dev                          Checks the retarget, the heights, and the linkage
    /// @param  _oldPeriodStartHeader The first header in the difficulty period being closed
    /// @param  _oldPeriodEndHeader   The last header in the difficulty period being closed (anchor of new headers)
    /// @param  _headers              A tightly-packed list of 80-byte Bitcoin headers
    /// @return                       True if successfully written, error otherwise
    function addHeadersWithRetarget(
        bytes calldata _oldPeriodStartHeader,
        bytes calldata _oldPeriodEndHeader,
        bytes calldata _headers
    ) external override returns (bool) {
        bytes29 _oldStart = _oldPeriodStartHeader.ref(0).tryAsHeader();
        bytes29 _oldEnd = _oldPeriodEndHeader.ref(0).tryAsHeader();
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();

        require(
            _oldStart.notNull() && _oldEnd.notNull() && _headersView.notNull(),
            "BitcoinRelay: bad args. Check header and array byte lengths."
        );

        return _addHeadersWithRetarget(_oldStart, _oldEnd, _headersView);
    }

    /// @notice         Finds the height of a header by its hash
    /// @dev            Will fail if the header is unknown
    /// @param _hash  The header hash to search for
    /// @return         The height of the header
    function _findHeight(bytes32 _hash) internal view returns (uint256) {
        if (blockHeight[_hash] == 0) {
            revert("Unknown block");
        }
        else {
            return blockHeight[_hash];
        }
    }

    /// @notice         Finds an ancestor for a block by its hash
    /// @dev            Will fail if the header is unknown
    /// @param _hash  The header hash to search for
    /// @return         The height of the header, or error if unknown
    function _findAncestor(bytes32 _hash, uint256 _offset) internal view returns (bytes32) {
        bytes32 _current = _hash;
        for (uint256 i = 0; i < _offset; i = i.add(1)) {
            _current = previousBlock[_current];
        }
        require(_current != bytes32(0), "BitcoinRelay: unknown ancestor");
        return _current;
    }

    /// @notice             Checks if a hash is an ancestor of the current one
    /// @dev                Limit the amount of lookups (and thus gas usage) with _limit
    /// @param _ancestor    The prospective ancestor
    /// @param _descendant  The descendant to check
    /// @param _limit       The maximum number of blocks to check
    /// @return             true if ancestor is at most limit blocks lower than descendant, otherwise false
    function _isAncestor(bytes32 _ancestor, bytes32 _descendant, uint256 _limit) internal view returns (bool) {
        bytes32 _current = _descendant;
        /* NB: 200 gas/read, so gas is capped at ~200 * limit */
        for (uint256 i = 0; i < _limit; i = i.add(1)) {
            if (_current == _ancestor) {
                return true;
            }
            _current = previousBlock[_current];
        }
        return false;
    }

    function _revertBytes32(bytes32 _input) internal view returns(bytes32) {
        bytes memory temp;
        bytes32 result;
        for (uint256 i = 0; i < 32; i = i.add(1)) {
            temp = abi.encodePacked(temp, _input[31-i]);
        }
        assembly {
            result := mload(add(temp, 32))
        }
        return result;
    }

    /// @notice                 Gets fee from the user
    /// @dev                    Fee is paid in target blockchain native token
    /// @return                 True if the fee payment was successful
    function _getFee() internal returns(bool){
        uint feeAmount;
        feeAmount = (submissionGasUsed.mul(tx.gasprice).mul(relayerPercentageFee).mul(epochLength)).div(lastEpochQueries.mul(100));
        require(msg.value >= feeAmount, "BitcoinRelay: fee is not enough");
        msg.sender.send(feeAmount);
        return true;
    }

    /// @notice             Adds headers to storage after validating
    /// @dev                We check integrity and consistency of the header chain
    /// @param  _anchor     The header immediately preceeding the new chain
    /// @param  _headers    A tightly-packed list of new 80-byte Bitcoin headers to record
    /// @param  _internal   True if called internally from addHeadersWithRetarget, false otherwise
    /// @return             True if successfully written, error otherwise
    function _addHeaders(bytes29 _anchor, bytes29 _headers, bool _internal) internal returns (bool) {
        // Extract basic info
        bytes32 _previousHash = _anchor.hash256();
        uint256 _anchorHeight = _findHeight(_previousHash);  /* NB: errors if unknown */
        uint256 _target = _headers.indexHeaderArray(0).target();

        require(
            _internal || _anchor.target() == _target,
            "BitcoinRelay: unexpected retarget on external call"
        );

        /*
        NB:
        1. check that the header has sufficient work
        2. check that headers are in a coherent chain (no retargets, hash links good)
        3. Store the block connection
        4. Store the height
        */
        uint256 _height;
        bytes32 _currentHash;
        for (uint256 i = 0; i < _headers.len() / 80; i += 1) {
            bytes29 _header = _headers.indexHeaderArray(i);
            _height = _anchorHeight.add(i + 1);
            _currentHash = _header.hash256();

            /* NB: we do still need to make chain level checks tho */
            // require(_header.target() == _target, "BitcoinRelay: target changed unexpectedly");
            require(_header.checkParent(_previousHash), "BitcoinRelay: headers do not form a consistent chain");

            require(_height + finalizationParameter > lastSubmittedHeight, "BitcoinRelay: block header is too old"); // TODO: test
            /*
            NB:
            if the block is already authenticated, we don't need to a work check
            Or write anything to state. This saves gas
            */
            // The below check prevents adding a replicated block header
            if (previousBlock[_currentHash] == bytes32(0)) {
                require(
                    TypedMemView.reverseUint256(uint256(_currentHash)) <= _target,
                    "BitcoinRelay: header work is insufficient"
                );

                previousBlock[_currentHash] = _previousHash;
                blockHeight[_currentHash] = _height;
                _addToChain(_header, _height);
                emit BlockAdded(_height, _currentHash, _previousHash, msg.sender);
            }
            _previousHash = _currentHash;
        }
        uint rewardAmount;
        bool isTDT;
        (rewardAmount, isTDT) = _sendReward(msg.sender, _headers.len()); // TOO: move it to where block gets finalized
        return true;
    }

    /// @notice                     Sends reward and compensation to the relayer who submitted the block
    /// @dev                        We pay the block submission cost in TNT and the extra reward in TDT which decreses in time
    /// @param  _relayer            The relayer address (message sender)
    /// @param  _numberOfBlocks     Number of blocks that the relayer submitted
    /// @return                     True if the amount is paid and False if treasury is empty
    function _sendReward(address _relayer, uint _numberOfBlocks) internal returns (uint, bool) {
        // TODO: change this function to what comments and description says
        // give TNT in full without the relayerPercentageFee mul, then, give extra reward by TDT (constant in several epochs but decrease in time)
        uint rewardAmountInTNT = _numberOfBlocks.mul(submissionGasUsed).mul(tx.gasprice).mul(relayerPercentageFee).div(100); // TNT is target native token
        // FIXME: adding _getRewardAmountInTDT function
        // uint rewardAmountInTDT = _getRewardAmountInTDT(rewardAmountInTNT);
        uint rewardAmountInTDT = 0;
        uint contractTDTBalance;
        if (TeleportDAOToken != address(0)) {
            contractTDTBalance = IERC20(TeleportDAOToken).balanceOf(address(this));
        } else {
            contractTDTBalance = 0;
        }
        uint contractTNTBalance = address(this).balance;
        if (rewardAmountInTDT <= contractTDTBalance && rewardAmountInTDT > 0) {
            // Call ERC20 token contract to transfer reward tokens to the relayer
            IERC20(TeleportDAOToken).transfer(_relayer, rewardAmountInTDT);
            return (rewardAmountInTDT, true);
        } else if (rewardAmountInTNT <= contractTNTBalance && rewardAmountInTNT > 0) {
            // Transfer TNT from relay to relayer
            msg.sender.transfer(rewardAmountInTNT);
            return (rewardAmountInTNT, false);
        }
        // TODO: handle if both treasuries go out of funds (decreasment in TDT should prevent confronting a limit but still keep an eye)
    }

    /// @notice                     Adds a header to the chain
    /// @dev                        We prune the chain if the new header causes other block headers to get finalized
    /// @param  _header             The new block header
    /// @param  _height             The height of the new block header
    function _addToChain(bytes29 _header, uint _height) internal {
        // Prevent relayers to submit too old block headers
        // TODO: replace 6 with a correct number
        require(_height + finalizationParameter > lastSubmittedHeight, "BitcoinRelay: block header is too old"); // TODO: test
        blockHeader memory newBlockHeader;
        newBlockHeader.selfHash = _header.hash256();
        newBlockHeader.parentHash = _header.parent();
        newBlockHeader.merkleRoot = _header.merkleRoot();
        newBlockHeader.relayer = msg.sender;
        chain[_height].push(newBlockHeader);
        if(_height > lastSubmittedHeight){
            lastSubmittedHeight++;
            _pruneChain();
        }
    }

    /// @notice                     Finalizes a block header and removes all the other headers in the same height
    /// @dev
    function _pruneChain() internal {
        if ((lastSubmittedHeight - initialHeight) >= finalizationParameter){
            uint idx = finalizationParameter;
            uint currentHeight = lastSubmittedHeight;
            uint stableIdx = 0;
            while (idx > 0) {
                // bytes29 header = chain[currentHeight][stableIdx];
                bytes32 parentHeaderHash = chain[currentHeight][stableIdx].parentHash;
                stableIdx = _findIndex(parentHeaderHash, currentHeight-1);
                idx--;
                currentHeight--;
            }
            // Keep the finalized block header and delete rest of headers
            chain[currentHeight][0] = chain[currentHeight][stableIdx];
            if(chain[currentHeight].length > 1){
                _pruneHeight(currentHeight);
                // TODO: send the block reward here to the remaining block in that height
                // and get rewardAmountTNT and rewardAmountTDT
                // TODO: then uncomment below event
                // emit BlockFinalized(
                //     currentHeight,
                //     chain[currentHeight][0].selfHash,
                //     chain[currentHeight][0].parentHash,
                //     chain[currentHeight][0].relayer,
                //     rewardAmountTNT,
                //     rewardAmountTDT
                // );
            }
        }
    }

    /// @notice                     Finds the index of a block header in a specific height
    /// @dev
    /// @param  _headerHash         The block header hash
    /// @param  _height             The height of the block header
    /// @return                     Index of the block header
    function _findIndex(bytes32 _headerHash, uint _height) internal returns(uint) {
        for(uint256 index = 0; index < chain[_height].length; index = index.add(1)) {
            if(_headerHash == chain[_height][index].selfHash) {
                return index;
            }
        }
        return 0;
    }

    /// @notice                     Deletes all the block header in the same height except the first header
    /// @dev                        The first header is the one that has gotten finalized
    /// @param  _height             The height of the new block header
    function _pruneHeight(uint _height) internal {
        uint idx = 1;
        while(idx < chain[_height].length){
            delete chain[_height][idx];
            idx++;
        }
    }

    /// @notice                       Adds headers to storage, performs additional validation of retarget
    /// @dev                          Checks the retarget, the heights, and the linkage
    /// @param  _oldStart             The first header in the difficulty period being closed
    /// @param  _oldEnd               The last header in the difficulty period being closed
    /// @param  _headers              A tightly-packed list of 80-byte Bitcoin headers
    /// @return                       True if successfully written, error otherwise
    function _addHeadersWithRetarget(
        bytes29 _oldStart,
        bytes29 _oldEnd,
        bytes29 _headers
    ) internal returns (bool) {

        /* NB: requires that both blocks are known */
        uint256 _startHeight = _findHeight(_oldStart.hash256());
        uint256 _endHeight = _findHeight(_oldEnd.hash256());

        /* NB: retargets should happen at 2016 block intervals */
        require(
            _endHeight % 2016 == 2015,
            "BitcoinRelay: must provide the last header of the closing difficulty period");
        require(
            _endHeight == _startHeight.add(2015),
            "BitcoinRelay: must provide exactly 1 difficulty period");
        require(
            _oldStart.diff() == _oldEnd.diff(),
            "BitcoinRelay: period header difficulties do not match");

        /* NB: This comparison looks weird because header nBits encoding truncates targets */
        bytes29 _newStart = _headers.indexHeaderArray(0);
        uint256 _actualTarget = _newStart.target();
        uint256 _expectedTarget = ViewBTC.retargetAlgorithm(
            _oldStart.target(),
            _oldStart.time(),
            _oldEnd.time()
        );
        require(
            (_actualTarget & _expectedTarget) == _actualTarget, // TODO: shouldn't it be == _expected??
            "BitcoinRelay: invalid retarget provided");

        // Pass all but the first through to be added
        return _addHeaders(_oldEnd, _headers, true);
    }


    // function changeOwner(address _owner) external override onlyOwner {
    //     owner = _owner;
    // }

    // function setFeeRatio(uint _feeRatio) external override onlyOwner {
    //     feeRatio = _feeRatio;
    // }



    // function setBuyBackPeriod(uint _buyBackPeriod) external override onlyOwner {
    //     buyBackPeriod = _buyBackPeriod;
    // }

    // /// @notice     Getter for currentEpochDiff
    // /// @dev        This is updated when a new heavist header has a new diff
    // /// @return     The difficulty of the bestKnownDigest
    // function getCurrentEpochDifficulty() external view override returns (uint256) {
    //     return currentEpochDiff;
    // }
    // /// @notice     Getter for prevEpochDiff
    // /// @dev        This is updated when a difficulty change is accepted
    // /// @return     The difficulty of the previous epoch
    // function getPrevEpochDifficulty() external view override returns (uint256) {
    //     return prevEpochDiff;
    // }

    // /// @notice     Getter for relayGenesis
    // /// @dev        This is an initialization parameter
    // /// @return     The hash of the first block of the relay
    // function getRelayGenesis() public view override returns (bytes32) {
    //     return relayGenesis;
    // }

    // /// @notice     Getter for bestKnownDigest
    // /// @dev        This updated only by calling markNewHeaviest
    // /// @return     The hash of the best marked chain tip
    // function getBestKnownDigest() public view override returns (bytes32) {
    //     return bestKnownDigest;
    // }

    // /// @notice     Getter for relayGenesis
    // /// @dev        This is updated only by calling markNewHeaviest
    // /// @return     The hash of the shared ancestor of the most recent fork
    // function getLastReorgCommonAncestor() public view override returns (bytes32) {
    //     return lastReorgCommonAncestor;
    // }

    // function getFee (bool payWithTDT) internal {
    //     uint feeAmount;
    //     feeAmount = (submissionGasUsed*tx.gasprice*feeRatio*epochLength)/(100*lastEpochQueries);
    //     if (payWithTDT == false) {
    //         // require(msg.value >= feeAmount, "fee is not enough");
    //         if (msg.value >= feeAmount){
    //             msg.sender.send(feeAmount);
    //         }
    //     } else { // payWithTDT == true
    //         feeAmount = getFeeAmountInTDT(feeAmount);
    //         uint TDTBalance = IERC20(TeleportDAOToken).balanceOf(address(this));
    //         if (feeAmount > 0 && TDTBalance >= feeAmount) {
    //             IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), feeAmount); // tx.origin instead of msg.sender
    //         }
    //     }
    // }

    // /// @notice                   Gives a starting point for the relay
    // /// @dev                      We don't check this AT ALL really. Don't use relays with bad genesis
    // /// @param  _ancestor         The digest of the most recent common ancestor
    // /// @param  _currentBest      The 80-byte header referenced by bestKnownDigest
    // /// @param  _newBest          The 80-byte header to mark as the new best
    // /// @param  _limit            Limit the amount of traversal of the chain
    // /// @return                   True if successfully updates bestKnownDigest, error otherwise
    // function markNewHeaviest(
    //     bytes32 _ancestor,
    //     bytes calldata _currentBest,
    //     bytes calldata _newBest,
    //     uint256 _limit
    // ) external override returns (bool) {
    //     bytes29 _new = _newBest.ref(0).tryAsHeader();
    //     bytes29 _current = _currentBest.ref(0).tryAsHeader();
    //     require(
    //         _new.notNull() && _current.notNull(),
    //         "Bad args. Check header and array byte lengths."
    //     );
    //     return _markNewHeaviest(_ancestor, _current, _new, _limit);
    // }

    // function sendReward (address relayer, uint numberOfBlocks) internal returns (uint, bool) {
    //     uint rewardAmountInTNT = numberOfBlocks*submissionGasUsed*tx.gasprice*feeRatio/100; // TNT is target native token
    //     uint rewardAmountInTDT = getRewardAmountInTDT(rewardAmountInTNT);
    //     uint contractTDTBalance;
    //     if (TeleportDAOToken != address(0)) {
    //         contractTDTBalance = IERC20(TeleportDAOToken).balanceOf(address(this));
    //     } else {
    //         contractTDTBalance = 0;
    //     }
    //     uint contractTNTBalance = address(this).balance;
    //     if (rewardAmountInTDT <= contractTDTBalance && rewardAmountInTDT > 0) {
    //         // call ERC20 token contract to transfer reward tokens to the relayer
    //         IERC20(TeleportDAOToken).transfer(relayer, rewardAmountInTDT);
    //         return (rewardAmountInTDT, true);
    //     } else if (rewardAmountInTNT <= contractTNTBalance && rewardAmountInTNT > 0) {
    //         // transfer TNT from relay to relayer
    //         msg.sender.transfer(rewardAmountInTNT);
    //         return (rewardAmountInTNT, false);
    //     }
    // }

    // function getRewardAmountInTDT(uint rewardAmountInTNT) internal returns(uint) {
    //     // TODO: calculate the reward using the swap rate between the token and TDT
    //     return 0;
    // }

    // function getFeeAmountInTDT(uint feeAmount) internal returns(uint) {
    //     // TODO: calculate the fee using the swap rate between the token and TDT
    //     return 0;
    // }

    // function addToChain(bytes29 _header, uint _height) internal {
    //     // prevent relayers to submit too old block headers
    //     // TODO: replace 6 with a correct number

    //     require(_height + 2*finalizationParameter >= lastSubmittedHeight, "block header is too old");
    //     blockHeader memory newBlockHeader;
    //     newBlockHeader.selfHash = _header.hash256();
    //     newBlockHeader.parentHash = _header.parent();
    //     newBlockHeader.merkleRoot = _header.merkleRoot();
    //     chain[_height].push(newBlockHeader);
    //     if(_height > lastSubmittedHeight){
    //         lastSubmittedHeight++;
    //         pruneChain();
    //     }
    // }

    // function pruneChain() internal {
    //     if ((lastSubmittedHeight - initialHeight) >= finalizationParameter){
    //         uint idx = finalizationParameter;
    //         uint currentHeight = lastSubmittedHeight;
    //         uint stableIdx = 0;
    //         while (idx > 0) {
    //             // bytes29 header = chain[currentHeight][stableIdx];
    //             bytes32 parentHeaderHash = chain[currentHeight][stableIdx].parentHash;
    //             stableIdx = findIndex(parentHeaderHash, currentHeight-1);
    //             idx--;
    //             currentHeight--;
    //         }
    //         // keep the finalized block header and delete rest of headers
    //         chain[currentHeight][0] = chain[currentHeight][stableIdx];
    //         if(chain[currentHeight].length > 1){
    //             deleteHeight(currentHeight);
    //         }
    //     }
    // }

    // function findIndex(bytes32 headerHash, uint height) internal returns(uint) {
    //     for(uint index = 0; index < chain[height].length; index ++) {
    //         if(headerHash == chain[height][index].selfHash) {
    //             return index;
    //         }
    //     }
    //     return 0;
    // }

    // function deleteHeight(uint height) internal {
    //     uint idx = 1;
    //     while(idx < chain[height].length){
    //         delete chain[height][idx];
    //         idx++;
    //     }
    // }


    // /// @notice                   Marks the new best-known chain tip
    // /// @param  _ancestor         The digest of the most recent common ancestor
    // /// @param  _current          The 80-byte header referenced by bestKnownDigest
    // /// @param  _new              The 80-byte header to mark as the new best
    // /// @param  _limit            Limit the amount of traversal of the chain
    // /// @return                   True if successfully updates bestKnownDigest, error otherwise
    // function _markNewHeaviest(
    //     bytes32 _ancestor,
    //     bytes29 _current,  // Header
    //     bytes29 _new,      // Header
    //     uint256 _limit
    // ) internal returns (bool) {
    //     require(_limit <= 2016, "Requested limit is greater than 1 difficulty period");

    //     bytes32 _newBestDigest = _new.hash256();
    //     bytes32 _currentBestDigest = _current.hash256();
    //     require(_currentBestDigest == bestKnownDigest, "Passed in best is not best known");
    //     require(
    //         previousBlock[_newBestDigest] != bytes32(0),
    //         "New best is unknown"
    //     );
    //     require(
    //         _isMostRecentAncestor(_ancestor, bestKnownDigest, _newBestDigest, _limit),
    //         "Ancestor must be heaviest common ancestor"
    //     );
    //     require(
    //         _heaviestFromAncestor(_ancestor, _current, _new) == _newBestDigest,
    //         "New best hash does not have more work than previous"
    //     );

    //     bestKnownDigest = _newBestDigest;
    //     lastReorgCommonAncestor = _ancestor;

    //     uint256 _newDiff = _new.diff();
    //     if (_newDiff != currentEpochDiff) {
    //         currentEpochDiff = _newDiff;
    //     }

    //     emit NewTip(
    //         _currentBestDigest,
    //         _newBestDigest,
    //         _ancestor);
    //     return true;
    // }

    // function isMostRecentAncestor(
    //     bytes32 _ancestor,
    //     bytes32 _left,
    //     bytes32 _right,
    //     uint256 _limit
    // ) external view returns (bool) {
    //     return _isMostRecentAncestor(_ancestor, _left, _right, _limit);
    // }

    // /// @notice             Checks if a digest is an ancestor of the current one
    // /// @dev                Limit the amount of lookups (and thus gas usage) with _limit
    // /// @param _ancestor    The prospective shared ancestor
    // /// @param _left        A chain tip
    // /// @param _right       A chain tip
    // /// @param _limit       The maximum number of blocks to check
    // /// @return             true if it is the most recent common ancestor within _limit, false otherwise
    // function _isMostRecentAncestor(
    //     bytes32 _ancestor,
    //     bytes32 _left,
    //     bytes32 _right,
    //     uint256 _limit
    // ) internal view returns (bool) {
    //     /* NB: sure why not */
    //     if (_ancestor == _left && _ancestor == _right) {
    //         return true;
    //     }

    //     bytes32 _leftCurrent = _left;
    //     bytes32 _rightCurrent = _right;
    //     bytes32 _leftPrev = _left;
    //     bytes32 _rightPrev = _right;

    //     for(uint256 i = 0; i < _limit; i = i.add(1)) {
    //         if (_leftPrev != _ancestor) {
    //             _leftCurrent = _leftPrev;  // cheap
    //             _leftPrev = previousBlock[_leftPrev];  // expensive
    //         }
    //         if (_rightPrev != _ancestor) {
    //             _rightCurrent = _rightPrev;  // cheap
    //             _rightPrev = previousBlock[_rightPrev];  // expensive
    //         }
    //     }
    //     if (_leftCurrent == _rightCurrent) {return false;} /* NB: If the same, they're a nearer ancestor */
    //     if (_leftPrev != _rightPrev) {return false;} /* NB: Both must be ancestor */
    //     return true;
    // }

    // function heaviestFromAncestor(
    //     bytes32 _ancestor,
    //     bytes calldata _left,
    //     bytes calldata _right
    // ) external view returns (bytes32) {
    //     return _heaviestFromAncestor(
    //         _ancestor,
    //         _left.ref(0).tryAsHeader(),
    //         _right.ref(0).tryAsHeader()
    //     );
    // }

    // /// @notice             Decides which header is heaviest from the ancestor
    // /// @dev                Does not support reorgs above 2017 blocks (:
    // /// @param _ancestor    The prospective shared ancestor
    // /// @param _left        A chain tip
    // /// @param _right       A chain tip
    // /// @return             true if it is the most recent common ancestor within _limit, false otherwise
    // function _heaviestFromAncestor(
    //     bytes32 _ancestor,
    //     bytes29 _left,
    //     bytes29 _right
    // ) internal view returns (bytes32) {
    //     uint256 _ancestorHeight = _findHeight(_ancestor);
    //     uint256 _leftHeight = _findHeight(_left.hash256());
    //     uint256 _rightHeight = _findHeight(_right.hash256());

    //     require(
    //         _leftHeight >= _ancestorHeight && _rightHeight >= _ancestorHeight,
    //         "A descendant height is below the ancestor height");

    //     /* NB: we can shortcut if one block is in a new difficulty window and the other isn't */
    //     uint256 _nextPeriodStartHeight = _ancestorHeight.add(2016).sub(_ancestorHeight % 2016);
    //     bool _leftInPeriod = _leftHeight < _nextPeriodStartHeight;
    //     bool _rightInPeriod = _rightHeight < _nextPeriodStartHeight;

    //     /*
    //     NB:
    //     1. Left is in a new window, right is in the old window. Left is heavier
    //     2. Right is in a new window, left is in the old window. Right is heavier
    //     3. Both are in the same window, choose the higher one
    //     4. They're in different new windows. Choose the heavier one
    //     */
    //     if (!_leftInPeriod && _rightInPeriod) {return _left.hash256();}
    //     if (_leftInPeriod && !_rightInPeriod) {return _right.hash256();}
    //     if (_leftInPeriod && _rightInPeriod) {
    //         return _leftHeight >= _rightHeight ? _left.hash256() : _right.hash256();
    //     } else {  // if (!_leftInPeriod && !_rightInPeriod) {
    //         if (((_leftHeight % 2016).mul(_left.diff())) <
    //             (_rightHeight % 2016).mul(_right.diff())) {
    //             return _right.hash256();
    //         } else {
    //             return _left.hash256();
    //         }
    //     }
    // }

    // function revertBytes32 (bytes32 input) internal view returns(bytes32) {
    //     bytes memory temp;
    //     bytes32 result;
    //     for (uint i = 0; i < 32; i++) {
    //         temp = abi.encodePacked(temp, input[31-i]);
    //     }
    //     assembly {
    //         result := mload(add(temp, 32))
    //     }
    //     return result;
    // }

    // function revertBytes (bytes memory input) internal returns(bytes memory) {
    //     bytes memory result;
    //     uint len = input.length;
    //     for (uint i = 0; i < len; i++) {
    //         result = abi.encodePacked(result, input[len-i-1]);
    //     }
    //     return result;
    // }

    // function calculateTxId (
    //     bytes4 _version,
    //     bytes memory _vin,
    //     bytes memory _vout,
    //     bytes4 _locktime
    // ) external view override returns(bytes32) {
    //     bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
    //     bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
    //     return inputHash2;
    // }
}
