pragma solidity 0.8.0;

import "../libraries/SafeMath.sol";
import "../libraries/TypedMemView.sol";
import "../libraries/ViewBTC.sol";
import "../libraries/ViewSPV.sol";
import "./interfaces/IBitcoinRelay.sol";
import "../routers/interfaces/IExchangeRouter.sol";
import "../erc20/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "hardhat/console.sol";

contract BitcoinRelay is IBitcoinRelay, Ownable, Pausable {
    using SafeMath for uint256;
    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using ViewBTC for bytes29;
    using ViewSPV for bytes29;

    /* using BytesLib for bytes;
    using BTCUtils for bytes;
    using ValidateSPV for bytes; */

    // address public owner;

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
    uint public override rewardAmountInTDT;
    address public override TeleportDAOToken;
    uint public override relayerPercentageFee; // Multiplied by 100 - greater than 100
    uint public override submissionGasUsed;
    uint public override epochLength;
    uint public override lastEpochQueries;
    uint public override currentEpochQueries;
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

    // modifier onlyOwner {
    //     require(msg.sender == owner);
    //     _;
    // }

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
        blockHeight[_periodStart] = _height - (_height % 2016);
        // Added parameters
        finalizationParameter = 1; // TODO: edit it
        lastSubmittedHeight = _height;
        initialHeight = _height;
        // Reward parameters
        TeleportDAOToken = _TeleportDAOToken;
        relayerPercentageFee = 0; // TODO: edit it;
        epochLength = 5;
        baseQueries = epochLength;
        lastEpochQueries = baseQueries;
        currentEpochQueries = 0;
        submissionGasUsed = 100000; // TODO: edit it
        exchangeRouter = _exchangeRouter;
        if (exchangeRouter != address(0)) {
            wrappedNativeToken = IExchangeRouter(exchangeRouter).WAVAX(); // call exchangeRouter to get wrappedNativeToken address
        }

        // owner = msg.sender;
    }

    /// @notice                 Pause the locker, so only the functions can be called which are whenPaused
    /// @dev
    /// @param
    function pauseRelay() external override onlyOwner {
        _pause();
    }

    /// @notice                 Un-pause the locker, so only the functions can be called which are whenNotPaused
    /// @dev
    /// @param
    function unPauseRelay() external override onlyOwner {
        _unpause();
    }

    // fallback () external payable {
    // }

    /// @notice             Getter for an specific block header's hash in the stored chain
    /// @param  _height     The height of the desired block header
    /// @param  _index      The index of the desired block header in that height
    /// @return             Block header's hash
    function getBlockHeaderHash (uint _height, uint _index) external view override returns(bytes32) {
        return _revertBytes32(chain[_height][_index].selfHash);
    }

    /// @notice             Getter for a finalized block header's fee price for a query
    /// @param  _height     The height of the desired block header
    /// @return             Block header's fee price for a query
    function getFinalizedHeaderFee(uint _height) external view override returns (uint) {
        return (submissionGasUsed * chain[_height][0].gasPrice * (1 + relayerPercentageFee) * (epochLength)) / (100 * lastEpochQueries);
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

    /// @notice                             Setter for rewardAmountInTDT
    /// @dev                                This award is for the relayer who has a finalized block header
    /// @param _rewardAmountInTDT           The reward amount in TDT
    function setRewardAmountInTDT(uint _rewardAmountInTDT) external override onlyOwner {
        rewardAmountInTDT = _rewardAmountInTDT;
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
    ) external payable whenNotPaused override returns (bool) {
        // Check for block confirmation
        // FIXME: change 6 with something different
        if (_blockHeight + 6 < lastSubmittedHeight + 1) {
            for (uint256 i = 0; i < chain[_blockHeight].length; i++) {
                bytes32 _merkleRoot = _revertBytes32(chain[_blockHeight][i].merkleRoot);
                bytes29 intermediateNodes = _intermediateNodes.ref(0).tryAsMerkleArray(); // Check for errors if any
                bytes32 txIdLE = _revertBytes32(_txid);
                if (ViewSPV.prove(txIdLE, _merkleRoot, intermediateNodes, _index)) {
                    require(_getFee(), "BitcoinRelay: getting fee was not successful");
                    currentEpochQueries += 1;
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
    function addHeaders(bytes calldata _anchor, bytes calldata _headers) external whenNotPaused override returns (bool) {
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
    ) external whenNotPaused override returns (bool) {
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
        for (uint256 i = 0; i < _offset; i++) {
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
        for (uint256 i = 0; i < _limit; i++) {
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
        for (uint256 i = 0; i < 32; i++) {
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
        feeAmount = (submissionGasUsed*(tx.gasprice)*(1 + relayerPercentageFee)*(epochLength))/(100 * lastEpochQueries);
        require(msg.value >= feeAmount, "BitcoinRelay: fee is not enough");
        bool sentFee;
        bytes memory dataFee;
        (sentFee, dataFee) = payable(msg.sender).call{value: (msg.value - feeAmount)}("");
        return sentFee;
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
        for (uint256 i = 0; i < _headers.len() / 80; i++) {
            bytes29 _header = _headers.indexHeaderArray(i);
            _height = _anchorHeight + i + 1;
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
        return true;
    }

    /// @notice                     Sends reward and compensation to the relayer
    /// @dev                        We pay the block submission cost in Eth and the extra reward in TDT
    /// @param  _relayer            The relayer address
    /// @return                     True if the amount is paid and False if treasury is empty
    function _sendReward(address _relayer) internal returns (uint, uint) {
        // FIXME: adding _getRewardAmountInTDT function

        // Reward in ETH
        uint rewardAmountInEth = submissionGasUsed * tx.gasprice * (1 + relayerPercentageFee) / 100;

        // Reward in TDT
        uint contractTDTBalance;
        if (TeleportDAOToken != address(0)) {
            contractTDTBalance = IERC20(TeleportDAOToken).balanceOf(address(this));
        } else {
            contractTDTBalance = 0;
        }

        // Send reward in TDT
        bool sentTDT;
        if (rewardAmountInTDT <= contractTDTBalance && rewardAmountInTDT > 0) {
            // Call ERC20 token contract to transfer reward tokens to the relayer
            sentTDT = IERC20(TeleportDAOToken).transfer(_relayer, rewardAmountInTDT);
        }

        // Send reward in ETH
        bool sentETH;
        bytes memory dataETH;
        if (address(this).balance > rewardAmountInEth && rewardAmountInEth > 0) {
            // note no need to revert if failed
            (sentETH, dataETH) = payable(_relayer).call{value: rewardAmountInEth}(""); // TODO check if this is the best way
        }

        if (sentETH) {
            if (sentTDT) {
                return (rewardAmountInEth, rewardAmountInTDT);
            } else {
                return (rewardAmountInEth, 0);
            }
        } else {
            if (sentTDT) {
                return (0, rewardAmountInTDT);
            } else {
                return (0, 0);
            }
        }
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
            lastSubmittedHeight += 1;
            _pruneChain();
            _updateFee();
        }
    }

    /// @notice                     Reset the number of users in an epoch when a new epoch starts
    /// @dev                        This parameter is used when calculating the fee that relay gets from a user in the next epoch
    function _updateFee() internal {
        if (lastSubmittedHeight % epochLength == 0) {
            lastEpochQueries = (currentEpochQueries < baseQueries) ? baseQueries : currentEpochQueries;
            currentEpochQueries = 0;
        }
    }

    /// @notice                     Finalizes a block header and removes all the other headers in the same height
    /// @dev
    function _pruneChain() internal {
        // Make sure that we have at least finalizationParameter blocks on relay
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
                // A new block has been finalized, we send its relayer's reward
                uint rewardAmountETH;
                uint rewardAmountTDT;
                (rewardAmountETH, rewardAmountTDT) = _sendReward(chain[currentHeight][0].relayer);
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
        for(uint256 index = 0; index < chain[_height].length; index++) {
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
            delete chain[_height][idx]; // TODO: check if it should be backwards?
            idx += 1;
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
            _endHeight == _startHeight + 2015,
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

    // TODO why commented?

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

    // function sendReward (address relayer, uint numberOfBlocks) internal returns (uint, bool) {
    //     uint rewardAmountInEth = numberOfBlocks*submissionGasUsed*tx.gasprice*feeRatio/100; // TNT is target native token
    //     uint rewardAmountInTDT = getRewardAmountInTDT(rewardAmountInEth);
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
    //     } else if (rewardAmountInEth <= contractTNTBalance && rewardAmountInEth > 0) {
    //         // transfer TNT from relay to relayer
    //         msg.sender.transfer(rewardAmountInEth);
    //         return (rewardAmountInEth, false);
    //     }
    // }

}
