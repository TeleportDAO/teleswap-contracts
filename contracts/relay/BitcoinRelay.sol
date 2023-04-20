// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "../libraries/TypedMemView.sol";
import "../libraries/BitcoinHelper.sol";
import "./interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BitcoinRelay is IBitcoinRelay, Ownable, ReentrancyGuard, Pausable {

    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using BitcoinHelper for bytes29;
    using SafeERC20 for IERC20;

    // Public variables
    uint constant ONE_HUNDRED_PERCENT = 10000;
    uint constant MAX_FINALIZATION_PARAMETER = 432; // roughly 3 days
    uint constant MAX_ALLOWED_GAP = 90 minutes;
    // ^ This is to prevent the submission of a Bitcoin block header with a timestamp 
    // that is more than 90 minutes ahead of the network's timestamp. Without this check,
    // the attacker could manipulate the difficulty target of a new epoch

    uint public override initialHeight;
    uint public override lastSubmittedHeight;
    uint public override finalizationParameter;
    uint public override rewardAmountInTDT;
    uint public override relayerPercentageFee; // A number between [0, 10000)
    uint public override submissionGasUsed; // Gas used for submitting a block header
    uint public override epochLength;
    uint public override baseQueries;
    uint public override currentEpochQueries;
    uint public override lastEpochQueries;
    address public override TeleportDAOToken;
    bytes32 public override relayGenesisHash; // Initial block header of relay

    // Private and internal variables
    mapping(uint => blockHeader[]) private chain; // height => list of block headers
    mapping(bytes32 => bytes32) internal previousBlock; // block header hash => parent header hash
    mapping(bytes32 => uint256) internal blockHeight; // block header hash => block height

    /// @notice Gives a starting point for the relay
    /// @param  _genesisHeader The starting header
    /// @param  _height The starting height
    /// @param  _periodStart The hash of the first header in the genesis epoch
    /// @param  _TeleportDAOToken The address of the TeleportDAO ERC20 token contract
    constructor(
        bytes memory _genesisHeader,
        uint256 _height,
        bytes32 _periodStart,
        address _TeleportDAOToken
    ) {
        // Adds the initial block header to the chain
        bytes29 _genesisView = _genesisHeader.ref(0).tryAsHeader();
        require(_genesisView.notNull(), "BitcoinRelay: null block");
        // Genesis header and period start can be same
        bytes32 _genesisHash = _genesisView.hash256();
        relayGenesisHash = _genesisHash;
        blockHeader memory newBlockHeader;
        newBlockHeader.selfHash = _genesisHash;
        newBlockHeader.parentHash = _genesisView.parent();
        newBlockHeader.merkleRoot = _genesisView.merkleRoot();
        newBlockHeader.relayer = _msgSender();
        newBlockHeader.gasPrice = 0;
        chain[_height].push(newBlockHeader);
        blockHeight[_genesisHash] = _height;
        blockHeight[_periodStart] = _height - (_height % BitcoinHelper.RETARGET_PERIOD_BLOCKS);

        // Relay parameters
        _setFinalizationParameter(3);
        initialHeight = _height;
        lastSubmittedHeight = _height;
        
        _setTeleportDAOToken(_TeleportDAOToken);
        _setRelayerPercentageFee(500);
        _setEpochLength(BitcoinHelper.RETARGET_PERIOD_BLOCKS);
        _setBaseQueries(epochLength);
        lastEpochQueries = baseQueries;
        currentEpochQueries = 0;
        _setSubmissionGasUsed(300000); // in wei
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice Pauses the Relay
    /// @dev Only functions with whenPaused modifier can be called
    function pauseRelay() external override onlyOwner {
        _pause();
    }

    /// @notice Unpauses the relay
    /// @dev Only functions with whenNotPaused modifier can be called
    function unpauseRelay() external override onlyOwner {
        _unpause();
    }

    /// @notice Getter for a specific block header's hash in the stored chain
    /// @dev It cannot be called by other contracts
    /// @param  _height of the desired block header
    /// @param  _index of the desired block header in that height
    /// @return Block header's hash
    function getBlockHeaderHash(uint _height, uint _index) external view override returns (bytes32) {
        require(
            !Address.isContract(msg.sender), 
            "BitcoinRelay: addr is contract"
        );
        return chain[_height][_index].selfHash;
    }

    /// @notice Getter for a specific block header submission gas price
    /// @param  _height of the desired block header
    /// @param  _index of the desired block header in that height
    /// @return Block header submission gas price
    function getBlockHeaderFee(uint _height, uint _index) external view override returns (uint) {
        return _calculateFee(chain[_height][_index].gasPrice);
    }

    /// @notice Getter for the number of submitted block headers in a height
    /// @dev This shows the number of temporary forks in that specific height
    /// @param  _height The desired height of the blockchain
    /// @return Number of block headers stored in a height
    function getNumberOfSubmittedHeaders(uint _height) external view override returns (uint) {
        return chain[_height].length;
    }

    /// @notice Getter for available TDT in Relay treasury
    function availableTDT() external view override returns (uint) {
        return IERC20(TeleportDAOToken).balanceOf(address(this));
    }

    /// @notice Getter for available target native token (TNT) in Relay treasury
    function availableTNT() external view override returns (uint) {
        return address(this).balance;
    }

    /// @notice Finds the height of a header by its hash
    /// @dev Fails if the header is unknown
    /// @param _hash The header hash to search for
    /// @return The height of the header
    function findHeight(bytes32 _hash) external view override returns (uint256) {
        return _findHeight(_hash);
    }

    /// @notice External setter for rewardAmountInTDT
    /// @dev This award is for the Relayer who submitted a finalized block header
    /// @param _rewardAmountInTDT The amount of reward in TDT
    function setRewardAmountInTDT(uint _rewardAmountInTDT) external override onlyOwner {
        _setRewardAmountInTDT(_rewardAmountInTDT);
    }

    /// @notice External setter for finalizationParameter
    /// @dev Bigger finalization parameter increases security but also increases the delay
    /// @param _finalizationParameter The finalization parameter of Bitcoin
    function setFinalizationParameter(uint _finalizationParameter) external override onlyOwner {
        _setFinalizationParameter(_finalizationParameter);
    }

    /// @notice External setter for relayerPercentageFee
    /// @dev A percentage of the submission gas used goes to Relayers as reward
    /// @param _relayerPercentageFee New percentage fee
    function setRelayerPercentageFee(uint _relayerPercentageFee) external override onlyOwner {
        _setRelayerPercentageFee(_relayerPercentageFee);
    }

    /// @notice External setter for TeleportDAO token
    /// @param _TeleportDAOToken The TeleportDAO token (TDT) address
    function setTeleportDAOToken(address _TeleportDAOToken) external override onlyOwner {
        _setTeleportDAOToken(_TeleportDAOToken);
    }

    /// @notice External setter for epochLength
    /// @param _epochLength The length of epochs used for estimating the query fee
    function setEpochLength(uint _epochLength) external override onlyOwner {
        _setEpochLength(_epochLength);
    }

    /// @notice External setter for baseQueries
    /// @param _baseQueries The base number of queries we assume in each epoch
    ///                     This prevents query fee to grow significantly
    function setBaseQueries(uint _baseQueries) external override onlyOwner {
        _setBaseQueries(_baseQueries);
    }

    /// @notice External setter for submissionGasUsed
    /// @param _submissionGasUsed The gas used by Relayers for submitting a block header
    function setSubmissionGasUsed(uint _submissionGasUsed) external override onlyOwner {
        _setSubmissionGasUsed(_submissionGasUsed);
    }

    /// @notice Checks if a tx is included and finalized on Bitcoin
    /// @dev Checks if the block is finalized, and Merkle proof is valid
    /// @param _txid Desired tx Id in LE form
    /// @param _blockHeight of the desired tx
    /// @param _intermediateNodes Part of the Merkle tree from the tx to the root in LE form (called Merkle proof)
    /// @param _index of the tx in Merkle tree
    /// @return True if the provided tx is confirmed on Bitcoin
    function checkTxProof (
        bytes32 _txid, // In LE form
        uint _blockHeight,
        bytes calldata _intermediateNodes, // In LE form
        uint _index
    ) external payable nonReentrant whenNotPaused override returns (bool) {
        require(_txid != bytes32(0), "BitcoinRelay: txid should be non-zero");
        // Revert if the block is not finalized
        require(
            _blockHeight + finalizationParameter < lastSubmittedHeight + 1,
            "BitcoinRelay: block is not finalized on the relay"
        );
        // Block header exists on the relay
        require(
            _blockHeight >= initialHeight,
            "BitcoinRelay: the requested height is not submitted on the relay (too old)"
        );

        // Get the Relay fee from the user
        uint paidFee = _getFee(chain[_blockHeight][0].gasPrice);
        
        // Check the inclusion of the transaction
        bytes32 _merkleRoot = chain[_blockHeight][0].merkleRoot;
        bytes29 intermediateNodes = _intermediateNodes.ref(0).tryAsMerkleArray(); // Check for errors if any
        
        emit NewQuery(_txid, _blockHeight, paidFee); 
        return BitcoinHelper.prove(_txid, _merkleRoot, intermediateNodes, _index);   
    }

    /// @notice Same as getBlockHeaderHash, but can be called by other contracts
    /// @dev Caller should pay the query fee
    function getBlockHeaderHashContract(uint _height, uint _index) external payable override returns (bytes32) {
        uint paidFee = _getFee(chain[_height][_index].gasPrice);
        emit NewQuery(chain[_height][_index].selfHash, _height, paidFee); 
        return chain[_height][_index].selfHash;
    }

    /// @notice Adds headers to storage after validating
    /// @dev Checks integrity and consistency of the header chain
    /// @param _anchor The header immediately preceeding the new chain
    /// @param _headers A tightly-packed list of 80-byte Bitcoin headers
    /// @return True if successfully written, error otherwise
    function addHeaders(
        bytes calldata _anchor, 
        bytes calldata _headers
    ) external nonReentrant whenNotPaused override returns (bool) {
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();
        bytes29 _anchorView = _anchor.ref(0).tryAsHeader();

        _checkInputSizeAddHeaders(_headersView, _anchorView);

        return _addHeaders(_anchorView, _headersView, false);
    }

    /// @notice Adds headers to storage, performs additional validation of retarget
    /// @dev Checks the retarget, the heights, and the linkage
    /// @param _oldPeriodStartHeader The first header in the difficulty period being closed
    /// @param _oldPeriodEndHeader The last header in the difficulty period being closed (anchor of new headers)
    /// @param _headers A tightly-packed list of 80-byte Bitcoin headers
    /// @return True if successfully written, error otherwise
    function addHeadersWithRetarget(
        bytes calldata _oldPeriodStartHeader,
        bytes calldata _oldPeriodEndHeader,
        bytes calldata _headers
    ) external nonReentrant whenNotPaused override returns (bool) {
        bytes29 _oldStart = _oldPeriodStartHeader.ref(0).tryAsHeader();
        bytes29 _oldEnd = _oldPeriodEndHeader.ref(0).tryAsHeader();
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();

        _checkInputSizeAddHeadersWithRetarget(_oldStart, _oldEnd, _headersView);

        return _addHeadersWithRetarget(_oldStart, _oldEnd, _headersView);
    }

    /// @notice Same as addHeaders, but can only be called by owner even if contract is paused
    ///         It will be used if a fork happend
    function ownerAddHeaders(
        bytes calldata _anchor, 
        bytes calldata _headers
    ) external nonReentrant onlyOwner override returns (bool) {
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();
        bytes29 _anchorView = _anchor.ref(0).tryAsHeader();

        _checkInputSizeAddHeaders(_headersView, _anchorView);

        return _addHeaders(_anchorView, _headersView, false);
    }

    /// @notice Same as addHeadersWithRetarget, but can only be called by owner even if contract is paused
    ///         It will be used if a fork happend
    function ownerAddHeadersWithRetarget(
        bytes calldata _oldPeriodStartHeader,
        bytes calldata _oldPeriodEndHeader,
        bytes calldata _headers
    ) external nonReentrant onlyOwner override returns (bool) {
        bytes29 _oldStart = _oldPeriodStartHeader.ref(0).tryAsHeader();
        bytes29 _oldEnd = _oldPeriodEndHeader.ref(0).tryAsHeader();
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();

        _checkInputSizeAddHeadersWithRetarget(_oldStart, _oldEnd, _headersView);

        return _addHeadersWithRetarget(_oldStart, _oldEnd, _headersView);
    }

    /// @notice  Checks the size of addHeaders inputs 
    function _checkInputSizeAddHeaders(bytes29 _headersView, bytes29 _anchorView) internal pure {
        require(
            _headersView.notNull() && _headersView.len() % 80 == 0
                && _anchorView.notNull() && _anchorView.len() == 80,
            "BitcoinRelay: wrong len"
        );
    }

    /// @notice Checks the size of addHeadersWithRetarget inputs 
    function _checkInputSizeAddHeadersWithRetarget(
        bytes29 _oldStart,
        bytes29 _oldEnd,
        bytes29 _headersView
    ) internal pure {
        require(
            _oldStart.notNull() && _oldStart.len() == 80 
                && _oldEnd.notNull() && _oldEnd.len() == 80 
                    && _headersView.notNull() && _headersView.len() % 80 == 0,
            "BitcoinRelay: wrong len"
        );
    }

    /// @notice Finds the height of a header by its hash
    /// @dev Reverts if the header is unknown
    /// @param _hash of the desired header
    /// @return The height of the header
    function _findHeight(bytes32 _hash) internal view returns (uint256) {
        if (blockHeight[_hash] == 0) {
            revert("BitcoinRelay: unknown block");
        }
        else {
            return blockHeight[_hash];
        }
    }

    /// @notice Gets fee from the user who queries the Relay
    /// @dev Fee is paid in target blockchain native token (called TNT)
    /// @param _gasPrice has been used for submitting the block header
    /// @return _feeAmount Needed fee
    function _getFee(uint _gasPrice) internal returns (uint _feeAmount) {
        // Count the query for next epoch fee calculation
        currentEpochQueries += 1;
        _feeAmount = _calculateFee(_gasPrice);
        require(msg.value >= _feeAmount, "BitcoinRelay: fee is not enough");
        Address.sendValue(payable(_msgSender()), msg.value - _feeAmount);
    }

    /// @notice Calculates the fee of querying a block header
    /// @param _gasPrice has been used for submitting the block header
    /// @return The fee amount 
    function _calculateFee(uint _gasPrice) private view returns (uint) {
        return (submissionGasUsed * _gasPrice * (ONE_HUNDRED_PERCENT + relayerPercentageFee) * epochLength) 
            / lastEpochQueries / ONE_HUNDRED_PERCENT;
    }

    /// @notice Adds headers to storage after validating
    function _addHeaders(bytes29 _anchor, bytes29 _headers, bool _internal) internal virtual returns (bool) {
        // Extract basic info
        bytes32 _previousHash = _anchor.hash256();
        uint256 _anchorHeight = _findHeight(_previousHash); // revert if the block is unknown
        uint256 _target = _headers.indexHeaderArray(0).target();

        // When calling addHeaders, no retargetting should happen
        require(
            _internal || _anchor.target() == _target,
            "BitcoinRelay: unexpected retarget on external call"
        );
        // check the height on top of the anchor is not finalized
        require(
            _anchorHeight + 1 + finalizationParameter > lastSubmittedHeight, 
            "BitcoinRelay: block headers are too old"
        );

        /*
            1. check that the blockheader is not a replica
            2. check blocks are in the same epoch regarding difficulty
            3. check that headers are in a coherent chain (no retargets, hash links good)
            4. check that the header has sufficient work
            5. Store the block connection
            6. Store the height
            7. store the block in the chain
        */
        uint256 _height;
        bytes32 _currentHash;
        for (uint256 i = 0; i < _headers.len() / 80; i++) {
            bytes29 _header = _headers.indexHeaderArray(i);
            _height = _anchorHeight + i + 1;
            _currentHash = _header.hash256();

            // The below check prevents adding a replicated block header
            require(
                previousBlock[_currentHash] == bytes32(0),
                "BitcoinRelay: the block header exists on the relay"
            );

            // Blocks that are multiplies of 2016 should be submitted using addHeadersWithRetarget
            require(
                _internal || _height % BitcoinHelper.RETARGET_PERIOD_BLOCKS != 0,
                "BitcoinRelay: headers should be submitted by calling addHeadersWithRetarget"
            );

            require(_header.time() < block.timestamp + MAX_ALLOWED_GAP, "BitcoinRelay: block is ahead in time");
            require(_header.target() == _target, "BitcoinRelay: target changed unexpectedly");
            require(_header.checkParent(_previousHash), "BitcoinRelay: headers do not form a consistent chain");
            
            require(
                TypedMemView.reverseUint256(uint256(_currentHash)) <= _target,
                "BitcoinRelay: header work is insufficient"
            );

            previousBlock[_currentHash] = _previousHash;
            blockHeight[_currentHash] = _height;
            emit BlockAdded(_height, _currentHash, _previousHash, _msgSender());
            _addToChain(_header, _height);
            _previousHash = _currentHash;
        }
        return true;
    }

    /// @notice Adds headers to storage, performs additional validation of retarget
    function _addHeadersWithRetarget(
        bytes29 _oldStart,
        bytes29 _oldEnd,
        bytes29 _headers
    ) internal virtual returns (bool) {
        // requires that both blocks are known
        uint256 _startHeight = _findHeight(_oldStart.hash256());
        uint256 _endHeight = _findHeight(_oldEnd.hash256());

        // retargets should happen at 2016 block intervals
        require(
            _endHeight % BitcoinHelper.RETARGET_PERIOD_BLOCKS == 2015,
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
        uint256 _expectedTarget = BitcoinHelper.retargetAlgorithm(
            _oldStart.target(),
            _oldStart.time(),
            _oldEnd.time()
        );
        require(
            (_actualTarget & _expectedTarget) == _actualTarget, 
            "BitcoinRelay: invalid retarget provided"
        );

        // Pass all but the first through to be added
        return _addHeaders(_oldEnd, _headers, true);
    }

    /// @notice Sends reward to the Relayer
    /// @dev We compensate the Relayer for the block submission cost + give extra reward in TDT
    /// @param _relayer The Relayer address
    /// @param _height The height of the submitted block header
    /// @return Reward in TNT
    /// @return Reward in TDT
    function _sendReward(address _relayer, uint _height) internal returns (uint, uint) {

        // Reward in TNT
        uint rewardAmountInTNT = submissionGasUsed * chain[_height][0].gasPrice 
            * (ONE_HUNDRED_PERCENT + relayerPercentageFee) / ONE_HUNDRED_PERCENT;

        // Reward in TDT
        uint contractTDTBalance = 0;
        if (TeleportDAOToken != address(0)) {
            contractTDTBalance = IERC20(TeleportDAOToken).balanceOf(address(this));
        }

        // Send reward in TDT
        bool sentTDT;
        if (rewardAmountInTDT <= contractTDTBalance && rewardAmountInTDT > 0) {
            // Call ERC20 token contract to transfer reward tokens to the relayer
            IERC20(TeleportDAOToken).safeTransfer(_relayer, rewardAmountInTDT);
            sentTDT = true;
        }

        // Send reward in TNT
        bool sentTNT;
        if (address(this).balance > rewardAmountInTNT && rewardAmountInTNT > 0) {
            // note: no need to revert if failed
            (sentTNT,) = payable(_relayer).call{value: rewardAmountInTNT}("");
        }

        if (sentTNT) {
            return sentTDT ? (rewardAmountInTNT, rewardAmountInTDT) : (rewardAmountInTNT, 0);
        } else {
            return sentTDT ? (0, rewardAmountInTDT) : (0, 0);
        }
    }

    /// @notice Adds a header to the chain
    /// @dev We prune the chain if the new header finalizes any header
    /// @param  _header The new block header
    /// @param  _height The height of the new block header
    function _addToChain(bytes29 _header, uint _height) internal {
        // Prevent relayers to submit too old block headers
        require(_height + finalizationParameter > lastSubmittedHeight, "BitcoinRelay: block header is too old");
        blockHeader memory newBlockHeader;
        newBlockHeader.selfHash = _header.hash256();
        newBlockHeader.parentHash = _header.parent();
        newBlockHeader.merkleRoot = _header.merkleRoot();
        newBlockHeader.relayer = _msgSender();
        newBlockHeader.gasPrice = tx.gasprice;
        chain[_height].push(newBlockHeader);
        if(_height > lastSubmittedHeight){
            lastSubmittedHeight += 1;
            _updateFee();
            _pruneChain();
        }
    }

    /// @notice Reset the number of epoch users when a new epoch starts
    /// @dev This parameter is used to calculate the fee that Relay gets from users in the next epoch
    function _updateFee() internal {
        if (lastSubmittedHeight % epochLength == 0) {
            lastEpochQueries = (currentEpochQueries < baseQueries) ? baseQueries : currentEpochQueries;
            currentEpochQueries = 0;
        }
    }

    /// @notice Finalizes a block header and removes all the other headers in that height
    /// @dev When chain gets pruned, we only delete blocks in the same 
    ///      height as the finalized header. Other blocks on top of the non finalized blocks 
    ///      will exist until their height gets finalized.
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
            }
            // A new block has been finalized, we send its relayer's reward
            uint rewardAmountTNT;
            uint rewardAmountTDT;
            (rewardAmountTNT, rewardAmountTDT) = _sendReward(chain[currentHeight][0].relayer, currentHeight);

            emit BlockFinalized(
                currentHeight,
                chain[currentHeight][0].selfHash,
                chain[currentHeight][0].parentHash,
                chain[currentHeight][0].relayer,
                rewardAmountTNT,
                rewardAmountTDT
            );
        }
    }

    /// @notice Finds the index of a block header in a specific height
    /// @param _headerHash The block header hash
    /// @param _height The height that we are searching
    /// @return _index Index of the block header
    function _findIndex(bytes32 _headerHash, uint _height) internal view returns(uint _index) {
        for(uint256 i = 0; i < chain[_height].length; i++) {
            if(_headerHash == chain[_height][i].selfHash) {
                _index = i;
            }
        }
    }

    /// @notice Deletes all the block header in a height except the first header
    /// @dev The first header is the one that gets finalized
    /// @param _height The height that we are pruning
    function _pruneHeight(uint _height) internal {
        uint idx = chain[_height].length - 1;
        while(idx > 0){
            chain[_height].pop();
            idx -= 1;
        }
    }

    /// @notice nternal setter for rewardAmountInTDT
    function _setRewardAmountInTDT(uint _rewardAmountInTDT) private {
        emit NewRewardAmountInTDT(rewardAmountInTDT, _rewardAmountInTDT);
        // this reward can be zero as well
        rewardAmountInTDT = _rewardAmountInTDT;
    }

    /// @notice Internal setter for finalizationParameter
    function _setFinalizationParameter(uint _finalizationParameter) private {
        emit NewFinalizationParameter(finalizationParameter, _finalizationParameter);
        require(
            _finalizationParameter > 0 && _finalizationParameter <= MAX_FINALIZATION_PARAMETER,
            "BitcoinRelay: invalid finalization param"
        );

        finalizationParameter = _finalizationParameter;
    }

    /// @notice Internal setter for relayerPercentageFee
    function _setRelayerPercentageFee(uint _relayerPercentageFee) private {
        emit NewRelayerPercentageFee(relayerPercentageFee, _relayerPercentageFee);
        require(
            _relayerPercentageFee <= ONE_HUNDRED_PERCENT,
            "BitcoinRelay: relay fee is above max"
        );
        relayerPercentageFee = _relayerPercentageFee;
    }

    /// @notice Internal setter for teleportDAO token
    function _setTeleportDAOToken(address _TeleportDAOToken) private {
        emit NewTeleportDAOToken(TeleportDAOToken, _TeleportDAOToken);
        TeleportDAOToken = _TeleportDAOToken;
    }

    /// @notice Internal setter for epochLength
    function _setEpochLength(uint _epochLength) private {
        emit NewEpochLength(epochLength, _epochLength);
        require(
            _epochLength > 0,
            "BitcoinRelay: zero epoch length"
        );
        epochLength = _epochLength;
    }

    /// @notice Internal setter for baseQueries
    function _setBaseQueries(uint _baseQueries) private {
        emit NewBaseQueries(baseQueries, _baseQueries);
        require(
            _baseQueries > 0,
            "BitcoinRelay: zero base query"
        );
        baseQueries = _baseQueries;
    }

    /// @notice Internal setter for submissionGasUsed
    function _setSubmissionGasUsed(uint _submissionGasUsed) private {
        emit NewSubmissionGasUsed(submissionGasUsed, _submissionGasUsed);
        submissionGasUsed = _submissionGasUsed;
    }
}
