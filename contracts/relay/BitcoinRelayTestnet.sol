// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./BitcoinRelay.sol";
import "../libraries/TypedMemView.sol";
import "../libraries/BitcoinHelper.sol";

contract BitcoinRelayTestnet is BitcoinRelay {

    using TypedMemView for bytes;
    using TypedMemView for bytes29;
    using BitcoinHelper for bytes29;

    /// @notice Gives a starting point for the relay
    /// @dev Same as BitcoinRelay contract, but some retargeting checks has been removed
    constructor(
        bytes memory _genesisHeader,
        uint256 _height,
        bytes32 _periodStart,
        address _TeleportDAOToken
    ) BitcoinRelay(_genesisHeader, _height, _periodStart, _TeleportDAOToken) {}

    /// @notice Adds headers to storage after validating
    /// @dev Checks for retargeting have been removed since the Bitcoin testnet has unexpected retargeting
    function _addHeaders(bytes29 _anchor, bytes29 _headers, bool _internal) internal override returns (bool) {
        // Extract basic info
        bytes32 _previousHash = _anchor.hash256();
        uint256 _anchorHeight = _findHeight(_previousHash); // revert if the block is unknown
        uint256 _target = _headers.indexHeaderArray(0).target();

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
    /// @dev Checks for retargeting have been removed since the Bitcoin testnet has unexpected retargeting
    function _addHeadersWithRetarget(
        bytes29 _oldStart,
        bytes29 _oldEnd,
        bytes29 _headers
    ) internal override returns (bool) {
        return _addHeaders(_oldEnd, _headers, true);
    }

}