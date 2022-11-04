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

    /// @notice                   Gives a starting point for the relay
    /// @param  _genesisHeader    The starting header
    /// @param  _height           The starting height
    /// @param  _periodStart      The hash of the first header in the genesis epoch
    /// @param  _TeleportDAOToken The address of the TeleportDAO ERC20 token contract
    constructor(
        bytes memory _genesisHeader,
        uint256 _height,
        bytes32 _periodStart,
        address _TeleportDAOToken
    ) {
        // Adds the initial block header to the chain
        bytes29 _genesisView = _genesisHeader.ref(0).tryAsHeader();
        require(_genesisView.notNull(), "BitcoinRelay: stop being dumb");
        // genesis header and period start can be same
        bytes32 _genesisHash = _genesisView.hash256();
        relayGenesisHash = _genesisHash;
        blockHeader memory newBlockHeader;
        newBlockHeader.selfHash = _genesisHash;
        newBlockHeader.parentHash = _genesisView.parent();
        newBlockHeader.merkleRoot = _genesisView.merkleRoot();
        newBlockHeader.relayer = _msgSender();
        newBlockHeader.gasPrice = 0;
        chain[_height].push(newBlockHeader);
        require(
            _periodStart & bytes32(0x0000000000000000000000000000000000000000000000000000000000ffffff) == bytes32(0),
            "Period start hash does not have work. Hint: wrong byte order?");
        blockHeight[_genesisHash] = _height;
        blockHeight[_periodStart] = _height - (_height % BitcoinHelper.RETARGET_PERIOD_BLOCKS);

        // Relay parameters
        _setFinalizationParameter(3);
        initialHeight = _height;
        lastSubmittedHeight = _height;
        
        _setTeleportDAOToken(_TeleportDAOToken);
        _setRelayerPercentageFee(5);
        _setEpochLength(BitcoinHelper.RETARGET_PERIOD_BLOCKS);
        _setBaseQueries(epochLength);
        lastEpochQueries = baseQueries;
        currentEpochQueries = 0;
        _setSubmissionGasUsed(300000); // in wei
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice        Pause the relay
    /// @dev           Only functions with whenPaused modifier can be called
    function pauseRelay() external override onlyOwner {
        _pause();
    }

    /// @notice        Unpause the relay
    /// @dev           Only functions with whenNotPaused modifier can be called
    function unpauseRelay() external override onlyOwner {
        _unpause();
    }

    /// @notice             Getter for a specific block header's hash in the stored chain
    /// @param  _height     The height of the desired block header
    /// @param  _index      The index of the desired block header in that height
    /// @return             Block header's hash
    function getBlockHeaderHash (uint _height, uint _index) external view override returns(bytes32) {
        return chain[_height][_index].selfHash;
    }

    /// @notice             Getter for a specific block header's fee price for a query
    /// @param  _height     The height of the desired block header
    /// @param  _index      The index of the desired block header in that height
    /// @return             Block header's fee price for a query
    function getBlockHeaderFee (uint _height, uint _index) external view override returns(uint) {
        return _calculateFee(chain[_height][_index].gasPrice);
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
        return IERC20(TeleportDAOToken).balanceOf(address(this));
    }

    /// @notice             Getter for available target native token in treasury
    /// @return             Amount of target blockchain native token available in Relay treasury
    function availableTNT() external view override returns(uint) {
        return address(this).balance;
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
    /// @param _hash    The header hash to search for
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

    /// @notice                             External setter for rewardAmountInTDT
    /// @dev                                This award is for the relayer who has a finalized block header
    /// @param _rewardAmountInTDT           The reward amount in TDT
    function setRewardAmountInTDT(uint _rewardAmountInTDT) external override onlyOwner {
        _setRewardAmountInTDT(_rewardAmountInTDT);
    }

    /// @notice                             External setter for finalizationParameter
    /// @dev                                This might change if finalization rule of the source chain gets updated
    /// @param _finalizationParameter       The finalization parameter of the source chain
    function setFinalizationParameter(uint _finalizationParameter) external override onlyOwner {
        _setFinalizationParameter(_finalizationParameter);
    }

    /// @notice                             External setter for relayerPercentageFee
    /// @dev                                This is updated when we want to change the Relayer reward
    /// @param _relayerPercentageFee               Ratio > 1 that determines percentage of reward to the Relayer
    function setRelayerPercentageFee(uint _relayerPercentageFee) external override onlyOwner {
        _setRelayerPercentageFee(_relayerPercentageFee);
    }

    /// @notice                             External setter for teleportDAO token
    /// @dev                                This is updated when we want to change the teleportDAO token 
    /// @param _TeleportDAOToken            The teleportDAO token address
    function setTeleportDAOToken(address _TeleportDAOToken) external override onlyOwner {
        _setTeleportDAOToken(_TeleportDAOToken);
    }

    /// @notice                             External setter for epochLength
    /// @param _epochLength                 The length of epochs for estimating the user queries hence their fees
    function setEpochLength(uint _epochLength) external override onlyOwner {
        _setEpochLength(_epochLength);
    }

    /// @notice                             External setter for baseQueries
    /// @param _baseQueries                 The base amount of queries we assume in each epoch
    ///                                     (This is for preventing user fees to grow significantly)
    function setBaseQueries(uint _baseQueries) external override onlyOwner {
        _setBaseQueries(_baseQueries);
    }

    /// @notice                             External setter for submissionGasUsed
    /// @dev                                This is updated when the smart contract changes the way of getting block headers
    /// @param _submissionGasUsed           The gas used for submitting one block header
    function setSubmissionGasUsed(uint _submissionGasUsed) external override onlyOwner {
        _setSubmissionGasUsed(_submissionGasUsed);
    }

    /// @notice                             Internal setter for rewardAmountInTDT
    /// @dev                                This award is for the relayer who has a finalized block header
    /// @param _rewardAmountInTDT           The reward amount in TDT
    function _setRewardAmountInTDT(uint _rewardAmountInTDT) private {
        emit NewRewardAmountInTDT(rewardAmountInTDT, _rewardAmountInTDT);
        // this reward can be zero as well
        rewardAmountInTDT = _rewardAmountInTDT;
    }

    /// @notice                             Internal setter for finalizationParameter
    /// @dev                                This might change if finalization rule of the source chain gets updated
    /// @param _finalizationParameter       The finalization parameter of the source chain
    function _setFinalizationParameter(uint _finalizationParameter) private {
        emit NewFinalizationParameter(finalizationParameter, _finalizationParameter);
        require(
            _finalizationParameter > 0,
            "BitcoinRelay: zero finalization param"
        );

        finalizationParameter = _finalizationParameter;
    }

    /// @notice                             Internal setter for relayerPercentageFee
    /// @dev                                This is updated when we want to change the Relayer reward
    /// @param _relayerPercentageFee               Ratio > 1 that determines percentage of reward to the Relayer
    function _setRelayerPercentageFee(uint _relayerPercentageFee) private {
        emit NewRelayerPercentageFee(relayerPercentageFee, _relayerPercentageFee);
        require(
            _relayerPercentageFee <= ONE_HUNDRED_PERCENT,
            "BitcoinRelay: relay fee is above max"
        );
        relayerPercentageFee = _relayerPercentageFee;
    }

    /// @notice                             Internal setter for teleportDAO token
    /// @dev                                This is updated when we want to change the teleportDAO token
    /// @param _TeleportDAOToken            The teleportDAO token address
    function _setTeleportDAOToken(address _TeleportDAOToken) private {
        emit NewTeleportDAOToken(TeleportDAOToken, _TeleportDAOToken);
        TeleportDAOToken = _TeleportDAOToken;
    }

    /// @notice                             Internal setter for epochLength
    /// @param _epochLength                 The length of epochs for estimating the user queries hence their fees
    function _setEpochLength(uint _epochLength) private {
        emit NewEpochLength(epochLength, _epochLength);
        require(
            _epochLength > 0,
            "BitcoinRelay: zero epoch length"
        );
        epochLength = _epochLength;
    }

    /// @notice                             Internal setter for baseQueries
    /// @param _baseQueries                 The base amount of queries we assume in each epoch
    ///                                     (This is for preventing user fees to grow significantly)
    function _setBaseQueries(uint _baseQueries) private {
        emit NewBaseQueries(baseQueries, _baseQueries);
        require(
            _baseQueries > 0,
            "BitcoinRelay: zero base query"
        );
        baseQueries = _baseQueries;
    }

    /// @notice                             Internal setter for submissionGasUsed
    /// @dev                                This is updated when the smart contract changes the way of getting block headers
    /// @param _submissionGasUsed           The gas used for submitting one block header
    function _setSubmissionGasUsed(uint _submissionGasUsed) private {
        emit NewSubmissionGasUsed(submissionGasUsed, _submissionGasUsed);
        submissionGasUsed = _submissionGasUsed;
    }

    /// @notice                         Checks if a tx is included and finalized on the source blockchain
    /// @dev                            Checks if the block is finalized, and Merkle proof is correct
    /// @param  _txid                   Desired transaction's tx Id
    /// @param  _blockHeight            Block height of the desired tx
    /// @param  _intermediateNodes      Part of the Merkle tree from the tx to the root using for proof
    /// @param  _index                  The index of the tx in Merkle tree
    /// @return                         True if the provided tx is confirmed on the source blockchain, False otherwise
    function checkTxProof (
        bytes32 _txid, // In BE form
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
        
        // Count the query for next epoch fee calculation
        currentEpochQueries += 1;

        // Get the relay fee from the user
        require(
            _getFee(chain[_blockHeight][0].gasPrice), 
            "BitcoinRelay: getting fee was not successful"
        );
        
        // Check the inclusion of the transaction
        bytes32 _merkleRoot = chain[_blockHeight][0].merkleRoot;
        bytes29 intermediateNodes = _intermediateNodes.ref(0).tryAsMerkleArray(); // Check for errors if any
        bytes32 txIdLE = _revertBytes32(_txid);
        return BitcoinHelper.prove(txIdLE, _merkleRoot, intermediateNodes, _index);
    }

    /// @notice             Adds headers to storage after validating
    /// @dev                We check integrity and consistency of the header chain
    /// @param  _anchor     The header immediately preceeding the new chain
    /// @param  _headers    A tightly-packed list of 80-byte Bitcoin headers
    /// @return             True if successfully written, error otherwise
    function addHeaders(bytes calldata _anchor, bytes calldata _headers) external nonReentrant whenNotPaused override returns (bool) {
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();
        bytes29 _anchorView = _anchor.ref(0).tryAsHeader();

        _checkInputSizeAddHeaders(_headersView, _anchorView);

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
    ) external nonReentrant whenNotPaused override returns (bool) {
        bytes29 _oldStart = _oldPeriodStartHeader.ref(0).tryAsHeader();
        bytes29 _oldEnd = _oldPeriodEndHeader.ref(0).tryAsHeader();
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();

        _checkInputSizeAddHeadersWithRetarget(_oldStart, _oldEnd, _headersView);

        return _addHeadersWithRetarget(_oldStart, _oldEnd, _headersView);
    }

    /// @notice             Adds headers to storage after validating
    /// @dev                Works like the other addHeaders; we use this function when relay is paused
    /// then only owner can add the new blocks, like when a fork happens
    /// @param  _anchor     The header immediately preceeding the new chain
    /// @param  _headers    A tightly-packed list of 80-byte Bitcoin headers
    /// @return             True if successfully written, error otherwise
    function ownerAddHeaders(bytes calldata _anchor, bytes calldata _headers) external nonReentrant onlyOwner override returns (bool) {
        bytes29 _headersView = _headers.ref(0).tryAsHeaderArray();
        bytes29 _anchorView = _anchor.ref(0).tryAsHeader();

        _checkInputSizeAddHeaders(_headersView, _anchorView);

        return _addHeaders(_anchorView, _headersView, false);
    }

    /// @notice                       Adds headers to storage, performs additional validation of retarget
    /// @dev                          Works like the other addHeadersWithRetarget; we use this function when relay is paused
    /// then only owner can add the new blocks, like when a fork happens
    /// @param  _oldPeriodStartHeader The first header in the difficulty period being closed
    /// @param  _oldPeriodEndHeader   The last header in the difficulty period being closed (anchor of new headers)
    /// @param  _headers              A tightly-packed list of 80-byte Bitcoin headers
    /// @return                       True if successfully written, error otherwise
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

    /// @notice                 Checks the size of addHeaders inputs 
    /// @param  _headersView    Input to the addHeaders and ownerAddHeaders functions
    /// @param  _anchorView     Input to the addHeaders and ownerAddHeaders functions
    function _checkInputSizeAddHeaders(bytes29 _headersView, bytes29 _anchorView) internal pure {
        require(_headersView.notNull(), "BitcoinRelay: header array length must be divisible by 80");
        require(_anchorView.notNull(), "BitcoinRelay: anchor must be 80 bytes");
    }

    /// @notice                     Checks the size of addHeadersWithRetarget inputs 
    /// @param  _oldStart           Input to the addHeadersWithRetarget and ownerAddHeadersWithRetarget functions
    /// @param  _oldEnd             Input to the addHeadersWithRetarget and ownerAddHeadersWithRetarget functions
    /// @param  _headersView        Input to the addHeadersWithRetarget functions
    function _checkInputSizeAddHeadersWithRetarget(
        bytes29 _oldStart,
        bytes29 _oldEnd,
        bytes29 _headersView
    ) internal pure {
        require(
            _oldStart.notNull() && _oldEnd.notNull() && _headersView.notNull(),
            "BitcoinRelay: bad args. Check header and array byte lengths."
        );
    }

    /// @notice             Finds the height of a header by its hash
    /// @dev                Will fail if the header is unknown
    /// @param _hash        The header hash to search for
    /// @return             The height of the header
    function _findHeight(bytes32 _hash) internal view returns (uint256) {
        if (blockHeight[_hash] == 0) {
            revert("BitcoinRelay: unknown block");
        }
        else {
            return blockHeight[_hash];
        }
    }

    /// @notice             Finds an ancestor for a block by its hash
    /// @dev                Will fail if the header is unknown
    /// @param _hash        The header hash to search for
    /// @param _offset      The depth which is going to be searched
    /// @return             The height of the header, or error if unknown
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

    function _revertBytes32(bytes32 _input) internal pure returns(bytes32) {
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
    /// @param gasPrice         The gas price had been used for adding the bitcoin block header
    /// @return                 True if the fee payment was successful
    function _getFee(uint gasPrice) internal returns (bool){
        uint feeAmount;
        feeAmount = _calculateFee(gasPrice);
        require(msg.value >= feeAmount, "BitcoinRelay: fee is not enough");
        Address.sendValue(payable(_msgSender()), msg.value - feeAmount);
        return true;
    }

    /// @notice                 Calculates the fee amount
    /// @dev                    Fee is paid in target blockchain native token
    /// @param gasPrice         The gas price had been used for adding the bitcoin block header
    /// @return                 The fee amount 
    function _calculateFee(uint gasPrice) private view returns (uint) {
        // TODO: check the first ONE_HUNDRED_PERCENT with others
        return (submissionGasUsed * gasPrice * (ONE_HUNDRED_PERCENT + relayerPercentageFee) * epochLength) / lastEpochQueries / ONE_HUNDRED_PERCENT;
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
            require(previousBlock[_currentHash] == bytes32(0),
            "BitcoinRelay: the block header exists on the relay");

            // Blocks that are multiplies of 2016 should be submitted using addHeadersWithRetarget
            require(
                _internal || _height % BitcoinHelper.RETARGET_PERIOD_BLOCKS != 0,
                "BitcoinRelay: headers should be submitted by calling addHeadersWithRetarget"
            );

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

    /// @notice                     Sends reward and compensation to the relayer
    /// @dev                        We pay the block submission cost in TNT and the extra reward in TDT
    /// @param  _relayer            The relayer address
    /// @param  _height             The height of the bitcoin block
    /// @return                     Reward in native token
    /// @return                     Reward in TDT token
    function _sendReward(address _relayer, uint _height) internal returns (uint, uint) {

        // Reward in TNT
        // TODO: check the first ONE_HUNDRED_PERCENT with others
        uint rewardAmountInTNT = submissionGasUsed * chain[_height][0].gasPrice * (ONE_HUNDRED_PERCENT + relayerPercentageFee) / ONE_HUNDRED_PERCENT;

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

    /// @notice                     Adds a header to the chain
    /// @dev                        We prune the chain if the new header causes other block headers to get finalized
    /// @param  _header             The new block header
    /// @param  _height             The height of the new block header
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

    /// @notice                     Reset the number of users in an epoch when a new epoch starts
    /// @dev                        This parameter is used when calculating the fee that relay gets from a user in the next epoch
    function _updateFee() internal {
        if (lastSubmittedHeight % epochLength == 0) {
            lastEpochQueries = (currentEpochQueries < baseQueries) ? baseQueries : currentEpochQueries;
            currentEpochQueries = 0;
        }
    }

    /// @notice                     Finalizes a block header and removes all the other headers in the same height
    /// @dev                        Note that when a chain gets pruned, it only deletes other blocks in the same 
    ///                             height as the finalized blocks. Other blocks on top of the non finalized blocks 
    ///                             of that height will exist until their height gets finalized.
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

    /// @notice                     Finds the index of a block header in a specific height
    /// @dev
    /// @param  _headerHash         The block header hash
    /// @param  _height             The height of the block header
    /// @return  index              Index of the block header
    function _findIndex(bytes32 _headerHash, uint _height) internal view returns(uint index) {
        for(uint256 _index = 0; _index < chain[_height].length; _index++) {
            if(_headerHash == chain[_height][_index].selfHash) {
                index = _index;
            }
        }
    }

    /// @notice                     Deletes all the block header in the same height except the first header
    /// @dev                        The first header is the one that has gotten finalized
    /// @param  _height             The height of the new block header
    function _pruneHeight(uint _height) internal {
        uint idx = chain[_height].length - 1;
        while(idx > 0){
            chain[_height].pop();
            idx -= 1;
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
            // TODO: check it precisely
            (_actualTarget & _expectedTarget) == _actualTarget, // is this correct?
            // it was in the original code, and we are not sure why is it this way
            "BitcoinRelay: invalid retarget provided");

        // Pass all but the first through to be added
        return _addHeaders(_oldEnd, _headers, true);
    }
}
