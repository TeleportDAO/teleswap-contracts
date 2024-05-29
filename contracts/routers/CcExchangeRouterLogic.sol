// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./CcExchangeRouterStorage.sol";
import "./CcExchangeRouterStorageV2.sol";
import "./interfaces/IBurnRouter.sol";
import "../swap_connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "../libraries/CcExchangeRouterLib.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";
import "hardhat/console.sol";

contract CcExchangeRouterLogic is
    CcExchangeRouterStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    CcExchangeRouterStorageV2
{
    using BytesLib for bytes;

    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    // Contract is payable
    receive() external payable {}

    /// @notice Initialize CcExchangeRouter
    /// @param _startingBlockNumber Transactions that are included in blocks older
    ///                             than _startingBlockNumber cannot be processed
    /// @param _protocolPercentageFee Protocol percentage fee (min: %0.01).
    ///                               This fee goes to treasury from each wrapAndSwap request
    /// @param _chainId Chain Id of the current chain
    /// @param _relay Address of BitcoinRelay which checks Bitcoin transactions inclusion
    /// @param _lockers LockersManager contract address
    /// @param _teleBTC TeleBTC token
    /// @param _treasury Treasury collects protocol fees
    function initialize(
        uint256 _startingBlockNumber,
        uint256 _protocolPercentageFee,
        uint256 _chainId,
        address _lockers,
        address _relay,
        address _teleBTC,
        address _treasury,
        address _across,
        address _burnRouter
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        chainId = _chainId;
        // isChainSupported[chainId] = true;
        _setStartingBlockNumber(_startingBlockNumber);
        _setProtocolPercentageFee(_protocolPercentageFee);
        _setRelay(_relay);
        _setLockers(_lockers);
        _setTeleBTC(_teleBTC);
        _setTreasury(_treasury);
        _setAcross(_across);
        _setBurnRouter(_burnRouter);
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice Setter for starting block number
    function setStartingBlockNumber(uint256 _startingBlockNumber)
        external
        override
        onlyOwner
    {
        _setStartingBlockNumber(_startingBlockNumber);
    }

    /// @notice Update Relay address
    function setRelay(address _relay) external override onlyOwner {
        _setRelay(_relay);
    }

    /// @notice Address of special Teleporter that can submit requests
    function setSpecialTeleporter(address _specialTeleporter)
        external
        override
        onlyOwner
    {
        _setSpecialTeleporter(_specialTeleporter);
    }

    /// @notice Update LockersManager address
    function setLockers(address _lockers) external override onlyOwner {
        _setLockers(_lockers);
    }

    /// @notice Assign an exchange connector to an app id
    /// @dev Users determine which DEX to use by determining the app id.
    function setExchangeConnector(uint256 _appId, address _exchangeConnector)
        external
        override
        onlyOwner
    {
        exchangeConnector[_appId] = _exchangeConnector;
        emit SetExchangeConnector(_appId, _exchangeConnector);
    }

    /// @notice Update TeleBTC address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        _setTeleBTC(_teleBTC);
    }

    /// @notice Setter for protocol percentage fee
    function setProtocolPercentageFee(uint256 _protocolPercentageFee)
        external
        override
        onlyOwner
    {
        _setProtocolPercentageFee(_protocolPercentageFee);
    }

    /// @notice Setter for treasury
    function setTreasury(address _treasury) external override onlyOwner {
        _setTreasury(_treasury);
    }

    // /// @notice Setter for filler withdraw interval
    // /// @dev Assuming that filling is started at X,
    // ///      fillers cannot withdraw their funds before x + _fillerWithdrawInterval
    // ///      (unless that filling is completed)
    // function setFillerWithdrawInterval(uint _fillerWithdrawInterval) external override onlyOwner {
    //     _setFillerWithdrawInterval(_fillerWithdrawInterval);
    // }

    /// @notice Setter for across
    /// @dev Across is used to send exchanged tokens to other chains
    function setAcross(address _across) external override onlyOwner {
        _setAcross(_across);
    }

    /// @notice Setter for BurnRouter
    function setBurnRouter(address _burnRouter) external override onlyOwner {
        _setBurnRouter(_burnRouter);
    }

    /// @notice Setter for third party
    /// @dev Each third party has an id and an address.
    ///      Users determine the third party by determining the id in the request.
    ///      Third party fee is sent to the third party address.
    function setThirdPartyAddress(
        uint256 _thirdPartyId,
        address _thirdPartyAddress
    ) external override onlyOwner {
        _setThirdPartyAddress(_thirdPartyId, _thirdPartyAddress);
    }

    /// @notice Setter for third party fee
    /// @dev Third party fee is a percentage of the input amount.
    ///      Third parties can set their own fees.
    function setThirdPartyFee(uint256 _thirdPartyId, uint256 _thirdPartyFee)
        external
        override
        onlyOwner
    {
        _setThirdPartyFee(_thirdPartyId, _thirdPartyFee);
    }

    /// @notice Setter for wrapped native token
    function setWrappedNativeToken(address _wrappedNativeToken)
        external
        override
        onlyOwner
    {
        _setWrappedNativeToken(_wrappedNativeToken);
    }

    /// @notice Setter for chain id mapping
    /// @dev After processing a request, the exchanged token is sent to the destination chain.
    function setChainIdMapping(
        uint256 _destinationChain,
        uint256 _mappedId
    ) external override onlyOwner {
        _setChainIdMapping(_destinationChain, _mappedId);
    }

    /// @notice Support a new token on specific chain
    /// @dev Users can only submit exchange requests for supported tokens.
    ///      By default, all tokens are supported on the current chain.
    function supportToken(uint256 chainId, address _token)
        external
        override
        onlyOwner
    {
        emit TokenAdded(chainId, _token);
        isTokenSupported[chainId][_token] = true;
    }

    /// @notice Remove a token from supported tokens
    function removeToken(uint256 chainId, address _token)
        external
        override
        onlyOwner
    {
        emit TokenRemoved(chainId, _token);
        isTokenSupported[chainId][_token] = false;
    }

    /// @notice Support a new chain
    /// @dev Users can only submit exchange requests for supported chains.
    function supportChain(uint256 _chainId) external override onlyOwner {
        emit ChainAdded(_chainId);
        isChainSupported[_chainId] = true;
    }

    /// @notice Remove a chain from supported chains
    function removeChain(uint256 _chainId) external override onlyOwner {
        emit ChainRemoved(_chainId);
        isChainSupported[_chainId] = false;
    }

    /// @notice Check if a request has been processed
    /// @dev It prevents re-submitting a processed request
    /// @param _txId The transaction ID of request on Bitcoin
    /// @return True if the cc exchange request has been already executed
    function isRequestUsed(bytes32 _txId)
        external
        view
        override
        returns (bool)
    {
        return ccExchangeRequests[_txId].isUsed ? true : false;
    }

    /// @notice Return the destination chain
    function getDestChainId(uint256 chainId)
        public
        view
        returns (uint256)
    {
        return chainIdMapping[chainId].destinationChain;
    }

    /// @notice Process a wrapAndSwap request after checking its inclusion on Bitcoin
    /// @dev Steps to process a request:
    ///      1. Check transaction inclusion on Bitcoin
    ///      2. Extract the request info
    ///      3. Mint TeleBTC and send fees to protocol, Locker, and third party
    ///      4. Exchange TeleBTC for the output token
    ///      5.1 Send the output token to the user
    ///      5.2 Send TeleBTC to user if exchange fails and the request belongs to the current chain
    ///      5.3 Keep TeleBTC if exchange fails and the request doesn't blong to the current chain
    /// @param _txAndProof Transaction and inclusion proof data
    /// @param _lockerLockingScript Script hash of Locker that user has sent BTC to it
    /// @param _path (Optional) Exchange path from teleBTC to the output token.
    function wrapAndSwap(
        TxAndProof memory _txAndProof,
        bytes calldata _lockerLockingScript,
        address[] memory _path
    ) external payable virtual override nonReentrant returns (bool) {
        // Basic checks
        require(
            _msgSender() == specialTeleporter,
            "ExchangeRouter: invalid sender"
        ); // Only Teleporter can submit requests
        require(
            _txAndProof.blockNumber >= startingBlockNumber,
            "ExchangeRouter: old request"
        );
        require(
            _txAndProof.locktime == bytes4(0),
            "ExchangeRouter: non-zero locktime"
        );

        // Check that the given script hash is Locker
        require(
            ILockersManager(lockers).isLocker(_lockerLockingScript),
            "ExchangeRouter: not locker"
        );

        // Extract request info and check if tx has been finalized on Bitcoin
        bytes32 txId = CcExchangeRouterLib.ccExchangeHelper(
            _txAndProof,
            ccExchangeRequests,
            extendedCcExchangeRequests,
            teleBTC,
            _lockerLockingScript,
            relay
        );

        // Find destination chain Id (the final chain that user gets its token on it) from chainId
        uint256 destinationChainId = getDestChainId(
            extendedCcExchangeRequests[txId].chainId
        );

        ccExchangeRequest memory request = ccExchangeRequests[txId];

        address _exchangeConnector = exchangeConnector[request.appId];
        require(
            _exchangeConnector != address(0),
            "ExchangeRouter: invalid appId"
        );

        // Find remained amount after reducing fees
        _mintAndReduceFees(_lockerLockingScript, txId);

        // if (
        //     request.speed == 1 &&
        //     _canFill(
        //         txId,
        //         request.path[request.path.length - 1], // output token
        //         request.outputAmount
        //     )
        // ) {
        //     // Fills exchange request
        //     _fillCcExchange(
        //         _lockerLockingScript,
        //         txId,
        //         request
        //     );

        // } else {
        if (destinationChainId == chainId) {
            require(
                extendedCcExchangeRequests[txId].bridgeFee == 0,
                "ExchangeRouter: invalid brdige fee"
            );

            // Requests that belongs to the current chain
            // Normal exchange request for a request which has not been filled
            _wrapAndSwap(_exchangeConnector, _lockerLockingScript, txId, _path);
        } else {
            require(
                isChainSupported[destinationChainId],
                "ExchangeRouter: invalid chain id"
            );
            // Requests that belongs to the other chain
            // Exchange and send to other chain for a request which has not been filled
            _wrapAndSwapToOtherChain(
                _exchangeConnector,
                _lockerLockingScript,
                txId,
                _path,
                extendedCcExchangeRequests[txId].bridgeFee,
                destinationChainId
            );
        }
        // }

        return true;
    }

    // /// @notice Filler fills an upcoming exchange request
    // /// @param _txId Bitcoin request that filler wants to fill
    // /// @param _token Address of exchange token in the request
    // /// @param _amount Requested exchanging amount
    // function fillTx(
    //     bytes32 _txId,
    //     address _recipient,
    //     address _token,
    //     uint _amount,
    //     uint _requestAmount
    // ) external override payable nonReentrant {
    //     require (_amount > 0,  "ExchangeRouter: zero amount");
    //     require (
    //         fillersData[_txId][_msgSender()].amount == 0,
    //         "ExchangeRouter: already filled"
    //     );

    //     PrefixFillSum storage _prefixFillSum = prefixFillSums[_txId][_token];

    //     if (_prefixFillSum.currentIndex == 0) {
    //         // ^ This is the first filling
    //         _prefixFillSum.prefixSum.push(0);
    //         _prefixFillSum.currentIndex = 1;
    //     }

    //     // Stores the filling info
    //     uint index = _prefixFillSum.currentIndex;

    //     if (_requestAmount > _prefixFillSum.prefixSum[index]) {
    //         uint fillAmount = _requestAmount - _prefixFillSum.prefixSum[index];

    //         if (_token == NATIVE_TOKEN) {
    //             require(_msgValue() >= fillAmount, "ExchangeRouter: incorrect amount");
    //             (bool sentToRecipient, bytes memory data1) = _recipient.call{value: fillAmount}("");
    //             (bool sentToFiller, bytes memory data2) = _msgSender().call{value: fillAmount}("");
    //             require(
    //                 sentToRecipient == true && sentToFiller == true,
    //                 "ExchangeRouter: failed to transfer native token"
    //             );
    //         } else {
    //             require(
    //                 IERC20(_token).transferFrom(_msgSender(), _recipient, fillAmount),
    //                 "ExchangeRouter: no allowance"
    //             );
    //         }

    //         fillersData[_txId][_msgSender()] = FillerData(_prefixFillSum.currentIndex, _token, fillAmount);

    //         // Updates the cumulative filling
    //         _prefixFillSum.prefixSum.push(_prefixFillSum.prefixSum[index - 1] + fillAmount);
    //         _prefixFillSum.currentIndex += 1;

    //         if (fillsData[_txId].startingTime == 0) {
    //             // ^ No one has filled before
    //             fillsData[_txId].startingTime = block.timestamp;

    //             emit FillStarted(
    //                 _txId,
    //                 block.timestamp
    //             );
    //         }

    //         emit NewFill(
    //             _msgSender(),
    //             _txId,
    //             _token,
    //             fillAmount
    //         );
    //     }
    // }

    // TODO remove
    // / @notice Fillers can withdraw their unused tokens
    // / @param _txId Bitcoin request which filling belongs to
    // / @return true if withdrawing was successful
    // function returnUnusedFill(
    //     bytes32 _txId
    // ) external override nonReentrant returns (bool) {
    //     FillData memory fillData = fillsData[_txId];

    //     // To withdraw tokens, either request should have been processed or
    //     // deadline for processing should has been passed
    //     require (
    //         ccExchangeRequests[_txId].inputAmount > 0 ||
    //             fillData.startingTime + fillerWithdrawInterval < block.timestamp,
    //         "ExchangeRouter: req not processed nor time not passed"
    //     );

    //     FillerData memory fillerData = fillersData[_txId][_msgSender()];

    //     // To withdraw token, either token should be wrong or token should have not been used
    //     if (fillData.reqToken != fillerData.token || fillData.lastUsedIdx < fillerData.index) {
    //         if (fillerData.token == NATIVE_TOKEN) {
    //             require(
    //                 payable(_msgSender()).send(fillerData.amount),
    //                 "ExchangeRouter: can't send Ether"
    //             );
    //         } else {
    //             require(
    //                 IERC20(fillerData.token).transfer(_msgSender(), fillerData.amount),
    //                 "ExchangeRouter: can't transfer token"
    //             );
    //         }
    //         fillersData[_txId][_msgSender()].amount = 0;

    //         emit FillTokensReturned(
    //             fillerData.amount,
    //             fillerData.token,
    //             _msgSender(),
    //             fillerData.index,
    //             _txId
    //         );
    //         return true;
    //     }

    //     // Last used filling may used partially, so filler can withdraw remaining amount
    //     if (
    //         fillData.lastUsedIdx == fillerData.index &&
    //         fillsData[_txId].isWithdrawnLastFill == false
    //     ) {
    //         if (fillerData.token == NATIVE_TOKEN) {
    //             require(
    //                 payable(_msgSender()).send(fillData.remainingAmountOfLastFill),
    //                 "ExchangeRouter: can't send Ether"
    //             );
    //         } else {
    //             require(
    //                 IERC20(fillerData.token).transfer(_msgSender(), fillData.remainingAmountOfLastFill),
    //                 "ExchangeRouter: can't transfer token"
    //             );
    //         }
    //         fillsData[_txId].isWithdrawnLastFill = true;

    //         emit FillTokensReturned(
    //             fillData.remainingAmountOfLastFill,
    //             fillerData.token,
    //             _msgSender(),
    //             fillerData.index,
    //             _txId
    //         );
    //         return true;
    //     }

    //     return false;
    // }

    // /// @notice Filler whose tokens has been used gets teleBTC
    // /// @param _txId Bitcoin request which filling belongs to
    // /// @return true if withdrawing was successful
    // function getTeleBtcForFill(
    //    bytes32 _txId
    // ) external override nonReentrant returns (bool) {
    //     FillData memory fillData = fillsData[_txId];
    //     FillerData memory fillerData = fillersData[_txId][_msgSender()];

    //     if (fillData.lastUsedIdx > fillerData.index) {
    //         // ^ This filling has been fully used
    //         uint amount = extendedCcExchangeRequests[_txId].remainedInputAmount
    //             * fillerData.amount / ccExchangeRequests[_txId].outputAmount;
    //         require(
    //             ITeleBTC(teleBTC).transfer(_msgSender(), amount),
    //             "ExchangeRouter: can't transfer TeleBTC"
    //         );
    //         fillersData[_txId][_msgSender()].amount = 0;

    //         emit FillTeleBtcSent(
    //             fillerData.amount,
    //             0,
    //             fillerData.token,
    //             _msgSender(),
    //             fillerData.index,
    //             _txId,
    //             extendedCcExchangeRequests[_txId].remainedInputAmount,
    //             amount
    //         );
    //         return true;
    //     }

    //     // We treat last used filling separately since part of it may only have been used
    //     if (fillData.lastUsedIdx == fillerData.index) {
    //         uint amount = (fillerData.amount - fillData.remainingAmountOfLastFill)
    //             * extendedCcExchangeRequests[_txId].remainedInputAmount / ccExchangeRequests[_txId].outputAmount;
    //         require(
    //             ITeleBTC(teleBTC).transfer(_msgSender(), amount),
    //             "ExchangeRouter: can't transfer TeleBTC"
    //         );
    //         fillersData[_txId][_msgSender()].amount = 0;

    //         emit FillTeleBtcSent(
    //             fillerData.amount,
    //             fillData.remainingAmountOfLastFill,
    //             fillerData.token,
    //             _msgSender(),
    //             fillerData.index,
    //             _txId,
    //             extendedCcExchangeRequests[_txId].remainedInputAmount,
    //             amount
    //         );
    //         return true;
    //     }

    //     return false;
    // }

    /// @notice Request BTC for failed exchange request
    /// @dev Users can get their BTC back if the request execution failed
    ///      and their request destination is different from the current chain
    /// @param _message ABI encode of (txId, scriptType, userScript, acrossRelayerFee)
    /// @param _r Signature r
    /// @param _s Signature s
    /// @param _v Signature v
    /// @param _lockerLockingScript Script hash of locker that user has sent BTC to it
    /// @return
    function withdrawFailedWrapAndSwap(
        bytes memory _message,
        bytes32 _r,
        bytes32 _s,
        uint8 _v,
        bytes calldata _lockerLockingScript
    ) external override nonReentrant returns (bool) {
        /* Check that:
           1. Request doesn't belong to the current chain
           2. Request execution has been failed
        */

        (bytes32 _txId, uint8 _scriptType, bytes memory _userScript, ) = abi
            .decode(_message, (bytes32, uint8, bytes, uint256));

        require(
            extendedCcExchangeRequests[_txId].chainId != chainId &&
                extendedCcExchangeRequests[_txId].isTransferredToOtherChain ==
                false,
            "ExchangeRouter: already processed"
        );
        extendedCcExchangeRequests[_txId].isTransferredToOtherChain = true;

        require(
            CcExchangeRouterLib._verifySig(_message, _r, _s, _v) ==
                ccExchangeRequests[_txId].recipientAddress,
            "ExchangeRouter: invalid signer"
        );

        // Burns teleBTC for user
        ITeleBTC(teleBTC).approve(
            burnRouter,
            extendedCcExchangeRequests[_txId].remainedInputAmount
        );

        IBurnRouter(burnRouter).unwrap(
            extendedCcExchangeRequests[_txId].remainedInputAmount,
            _userScript,
            ScriptTypes(_scriptType),
            _lockerLockingScript,
            0
        );

        return true;
    }

    /// @notice Retry for failed exchange request
    /// @dev Users can retry their failed exchange request if
    ///      their request destination is different from the current chain
    /// @param _message ABI encode of (txId, outputAmount, acrossRelayerFee, exchangePath)
    /// @param _r Signature r
    /// @param _s Signature s
    /// @param _v Signature v
    function retryFailedWrapAndSwap(
        bytes memory _message,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) external override nonReentrant returns (bool) {
        (
            bytes32 _txId,
            uint256 _outputAmount,
            uint256 _acrossRelayerFee,
            address[] memory path,
            bytes memory _lockerLockingScript
        ) = abi.decode(_message, (bytes32, uint256, uint256, address[], bytes));

        ccExchangeRequests[_txId].outputAmount = _outputAmount;
        ccExchangeRequest memory exchangeReq = ccExchangeRequests[_txId];
        // Use new output amount provided by user
        ccExchangeRequests[_txId].outputAmount = _outputAmount;
        extendedCcExchangeRequest memory extendedReq = extendedCcExchangeRequests[_txId];

        /* Check that:
           1. Request doesn't belong to the current chain
           2. Request execution has been failed
        */
        require(
            extendedCcExchangeRequests[_txId].chainId != chainId &&
            extendedCcExchangeRequests[_txId].isTransferredToOtherChain == false,
            "ExchangeRouter: already processed"
        );
        extendedCcExchangeRequests[_txId].isTransferredToOtherChain = true;

        require(
            CcExchangeRouterLib._verifySig(_message, _r, _s, _v) == exchangeReq.recipientAddress,
            "ExchangeRouter: invalid signer"
        );

        // Exchange teleBTC for desired exchange token
        (bool result, uint256[] memory amounts) = _swap(
            ICcExchangeRouter.swapArguments(
                extendedReq.chainId,
                _lockerLockingScript,
                exchangeReq,
                extendedReq,
                _txId,
                path,
                exchangeConnector[exchangeReq.appId]
            )
        );

        require(result, "ExchangeRouter: swap failed");

        // Send exchanged tokens to ETH
        _sendTokenToOtherChain(
            extendedCcExchangeRequests[_txId].chainId,
            path[path.length - 1],
            amounts[amounts.length - 1],
            exchangeReq.recipientAddress,
            _acrossRelayerFee
        );

        return true;
    }

    /// @notice Send tokens to the destination using Across
    function _sendTokenToOtherChain(
        uint256 _chainId,
        address _token,
        uint256 _amount,
        address _user,
        uint256 _acrossRelayerFee
    ) private {
        IERC20(_token).approve(across, _amount);

        SpokePoolInterface(across).deposit(
            _user,
            _token,
            _amount,
            getDestChainId(_chainId),
            int64(uint64(_acrossRelayerFee)),
            uint32(block.timestamp),
            "0x", // Null data
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
    }

    /// @notice Internal function for request belonging to the current chain
    function _wrapAndSwap(
        address _exchangeConnector,
        bytes memory _lockerLockingScript,
        bytes32 _txId,
        address[] memory _path
    ) internal {
        // try swapping with path provided by teleporter
        (bool result, ) = _swap(
            ICcExchangeRouter.swapArguments(
                chainId,
                _lockerLockingScript,
                ccExchangeRequests[_txId],
                extendedCcExchangeRequests[_txId],
                _txId,
                _path,
                _exchangeConnector
            )
        );

        if (!result) {
            // Sends teleBTC to recipient if exchange wasn't successful
            ITeleBTC(teleBTC).transfer(
                ccExchangeRequests[_txId].recipientAddress,
                extendedCcExchangeRequests[_txId].remainedInputAmount
            );
        }
    }

    /// @notice Internal function for request belonging chains other than the current chain
    function _wrapAndSwapToOtherChain(
        address _exchangeConnector,
        bytes memory _lockerLockingScript,
        bytes32 _txId,
        address[] memory _path,
        uint256 _acrossRelayerFee, // TODO fix in future: teleporter sets across relayer fee and use this as maximum amount of it
        uint256 _chainId
    ) private {
        (bool result, uint256[] memory amounts) = _swap(
            ICcExchangeRouter.swapArguments(
                _chainId,
                _lockerLockingScript,
                ccExchangeRequests[_txId],
                extendedCcExchangeRequests[_txId],
                _txId,
                _path,
                _exchangeConnector
            )
        );

        if (result) {
            // if swap is successfull, user will get desired tokens on destination chain
            extendedCcExchangeRequests[_txId].isTransferredToOtherChain = true;
            // Send exchanged tokens to ETH
            _sendTokenToOtherChain(
                extendedCcExchangeRequests[_txId].chainId,
                _path[_path.length - 1],
                amounts[amounts.length - 1],
                ccExchangeRequests[_txId].recipientAddress,
                _acrossRelayerFee
            );
        } else {
            // if swap fails, someone needs to call:
            // withdrawFailedWrapAndSwap: to burn minted telebtc and user gets them back
            // or
            // retryFailedWrapAndSwap: to retry swap and send swapped tokens to other chain
            // on current chain
            ITeleBTC(teleBTC).approve(
                _exchangeConnector,
                extendedCcExchangeRequests[_txId].remainedInputAmount
            );
        }
    }

    /// @notice Swap TeleBTC for the output token
    /// @dev First try to swap with the given path, if it fails,
    ///      try to swap with the default path (teleBTC -> output token)
    function _swap(ICcExchangeRouter.swapArguments memory swapArguments)
        private
        returns (bool result, uint256[] memory amounts)
    {
        if (
            swapArguments.destinationChainId == chainId ||
            isTokenSupported[swapArguments.destinationChainId][
                swapArguments._path[swapArguments._path.length - 1]
            ]
        ) {
            // Either the destination chain should be the current chain or
            // we should be able to send exchanged tokens to the destination chain

            // Gives allowance to exchange connector for swapping
            ITeleBTC(teleBTC).approve(
                swapArguments._exchangeConnector,
                swapArguments._extendedCcExchangeRequest.remainedInputAmount
            );

            if (
                IExchangeConnector(swapArguments._exchangeConnector)
                    .isPathValid(swapArguments._path)
            ) {
                require(
                    swapArguments._path[0] == teleBTC &&
                        swapArguments._path[swapArguments._path.length - 1] ==
                        swapArguments._ccExchangeRequest.path[
                            swapArguments._ccExchangeRequest.path.length - 1
                        ],
                    "CcExchangeRouter: invalid path"
                );
                (result, amounts) = IExchangeConnector(
                    swapArguments._exchangeConnector
                ).swap(
                        swapArguments
                            ._extendedCcExchangeRequest
                            .remainedInputAmount,
                        swapArguments._ccExchangeRequest.outputAmount,
                        swapArguments._path,
                        swapArguments.destinationChainId == chainId? swapArguments._ccExchangeRequest.recipientAddress: address(this),
                        block.timestamp,
                        true
                    );

                if (!result) {
                    (result, amounts) = IExchangeConnector(
                        swapArguments._exchangeConnector
                    ).swap(
                            swapArguments
                                ._extendedCcExchangeRequest
                                .remainedInputAmount,
                            swapArguments._ccExchangeRequest.outputAmount,
                            swapArguments._ccExchangeRequest.path,
                            swapArguments.destinationChainId == chainId? swapArguments._ccExchangeRequest.recipientAddress: address(this),
                            block.timestamp,
                            true
                        );
                }
            }
        } else {
            result = false;
        }

        if (result) {
            uint256 bridgeFee = (amounts[amounts.length - 1] *
                swapArguments._extendedCcExchangeRequest.bridgeFee) /
                MAX_BRIDGE_FEE;

            uint256[5] memory fees = [
                swapArguments._ccExchangeRequest.fee,
                swapArguments._extendedCcExchangeRequest.lockerFee,
                swapArguments._extendedCcExchangeRequest.protocolFee,
                swapArguments._extendedCcExchangeRequest.thirdPartyFee,
                bridgeFee
            ];

            emit NewWrapAndSwap(
                ILockersManager(lockers).lockerTargetAddress(
                    swapArguments._lockerLockingScript
                ),
                swapArguments._ccExchangeRequest.recipientAddress,
                [teleBTC, swapArguments._path[swapArguments._path.length - 1]], // [input token, output token]
                [amounts[0], amounts[amounts.length - 1] - bridgeFee], // [input amount, output amount]
                swapArguments._ccExchangeRequest.speed,
                _msgSender(), // Teleporter address
                swapArguments._txId,
                swapArguments._ccExchangeRequest.appId,
                swapArguments._extendedCcExchangeRequest.thirdParty,
                fees,
                swapArguments.destinationChainId
            );
        } else {
            // Handled situation where exchange fails
            uint256[5] memory fees = [
                swapArguments._ccExchangeRequest.fee,
                swapArguments._extendedCcExchangeRequest.lockerFee,
                swapArguments._extendedCcExchangeRequest.protocolFee,
                swapArguments._extendedCcExchangeRequest.thirdPartyFee,
                0
            ];
            emit FailedWrapAndSwap(
                ILockersManager(lockers).lockerTargetAddress(
                    swapArguments._lockerLockingScript
                ),
                swapArguments._ccExchangeRequest.recipientAddress,
                [teleBTC, swapArguments._path[swapArguments._path.length - 1]], // [input token, output token]
                [
                    swapArguments
                        ._extendedCcExchangeRequest
                        .remainedInputAmount,
                    0
                ], // [input amount, output amount]
                swapArguments._ccExchangeRequest.speed,
                _msgSender(), // Teleporter address
                swapArguments._txId,
                swapArguments._ccExchangeRequest.appId,
                swapArguments._extendedCcExchangeRequest.thirdParty,
                fees,
                swapArguments.destinationChainId
            );
        }
    }

    // /// @notice Checks that if request can be filled
    // /// @dev Request can be filled if
    // ///      1. Filling deadline has not been passed
    // ///      2. At least one filler exists
    // ///      3. Filled amount is greater than or equal of the requested amount
    // function _canFill(
    //     bytes32 _txId,
    //     address _token,
    //     uint256 _amount
    // ) private view returns (bool) {
    //     PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][_token];

    //     if (
    //         block.timestamp <= fillsData[_txId].startingTime + fillerWithdrawInterval &&
    //         _prefixFillSum.currentIndex > 0 &&
    //         _prefixFillSum.prefixSum[_prefixFillSum.currentIndex - 1] >= _amount
    //     ) {
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }

    /// @notice Executes the exchange request with filler
    // function _fillCcExchange(
    //     bytes memory _lockerLockingScript,
    //     bytes32 _txId,
    //     ccExchangeRequest memory _request
    // ) private {
    //     address outputToken = _request.path[_request.path.length - 1];

    //     FillData memory _txFillData;
    //     _txFillData.reqToken = outputToken;

    //     PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][outputToken];
    //     _txFillData.lastUsedIdx = _findlastUsedIdxOfFill(_prefixFillSum, _request.outputAmount);
    //     _txFillData.remainingAmountOfLastFill = _prefixFillSum.prefixSum[_txFillData.lastUsedIdx]
    //         - _request.outputAmount;

    //     // Saves the filling data
    //     fillsData[_txId] = _txFillData;

    //     uint _chainId = extendedCcExchangeRequests[_txId].chainId;
    //     if (_chainId == chainId) {
    //         if (outputToken == NATIVE_TOKEN) {
    //             Address.sendValue(
    //                 payable(_request.recipientAddress),
    //                 _request.outputAmount
    //             );
    //         } else {
    //             IERC20(outputToken).transfer(
    //                 _request.recipientAddress,
    //                 _request.outputAmount
    //             );
    //         }
    //     } else {
    //         _sendTokenToOtherChain(
    //             extendedCcExchangeRequests[_txId].chainId,
    //             _request.path[_request.path.length - 1],
    //             _request.outputAmount,
    //             _request.recipientAddress,
    //             extendedCcExchangeRequests[_txId].bridgeFee
    //         );
    //     }

    //     emit CCExchange(
    //         ILockersManager(lockers).getLockerTargetAddress(_lockerLockingScript),
    //         _request.recipientAddress,
    //         [teleBTC, outputToken], // [input token, output token]
    //         [extendedCcExchangeRequests[_txId].remainedInputAmount, _request.outputAmount], // [input amount, output amount]
    //         _request.speed,
    //         _msgSender(), // Teleporter address
    //         _request.fee,
    //         _txId,
    //         _request.appId
    //     );
    // }

    // function _findlastUsedIdxOfFill(
    //     PrefixFillSum memory _prefixFillSum,
    //     uint256 _amount
    // ) private pure returns(uint)  {
    //     uint[] memory sumArray = _prefixFillSum.prefixSum;
    //     int l = -1;
    //     int r = int(_prefixFillSum.currentIndex);
    //     while (r - l > 1) {
    //         int mid = (l + r) >> 1;
    //         if (sumArray[uint(mid)] >= _amount)
    //             r = mid;
    //         else
    //             l = mid;
    //     }
    //     return uint(r);
    // }

    /// @notice Mints teleBTC by calling lockers contract
    /// @param _lockerLockingScript Locker's locking script
    /// @param _txId The transaction ID of the request
    function _mintAndReduceFees(
        bytes memory _lockerLockingScript,
        bytes32 _txId
    ) private {
        // Mints teleBTC for cc exchange router
        uint256 mintedAmount = ILockersManager(lockers).mint(
            _lockerLockingScript,
            address(this),
            ccExchangeRequests[_txId].inputAmount
        );

        // Calculates fees
        extendedCcExchangeRequests[_txId].protocolFee =
            (ccExchangeRequests[_txId].inputAmount * protocolPercentageFee) /
            MAX_PROTOCOL_FEE;
        uint256 networkFee = ccExchangeRequests[_txId].fee;
        extendedCcExchangeRequests[_txId].thirdPartyFee =
            (ccExchangeRequests[_txId].inputAmount *
                thirdPartyFee[extendedCcExchangeRequests[_txId].thirdParty]) /
            MAX_PROTOCOL_FEE;
        extendedCcExchangeRequests[_txId].lockerFee =
            ccExchangeRequests[_txId].inputAmount -
            mintedAmount;

        // Pays Teleporter fee
        if (networkFee > 0) {
            ITeleBTC(teleBTC).transfer(_msgSender(), networkFee);
        }

        // Pays protocol fee
        if (extendedCcExchangeRequests[_txId].protocolFee > 0) {
            ITeleBTC(teleBTC).transfer(
                treasury,
                extendedCcExchangeRequests[_txId].protocolFee
            );
        }

        // Pays third party fee
        if (extendedCcExchangeRequests[_txId].thirdPartyFee > 0) {
            ITeleBTC(teleBTC).transfer(
                thirdPartyAddress[extendedCcExchangeRequests[_txId].thirdParty],
                extendedCcExchangeRequests[_txId].thirdPartyFee
            );
        }

        extendedCcExchangeRequests[_txId].remainedInputAmount =
            mintedAmount -
            extendedCcExchangeRequests[_txId].protocolFee -
            networkFee -
            extendedCcExchangeRequests[_txId].thirdPartyFee;
    }

    // /// @notice Internal setter for filler withdraw interval
    // function _setFillerWithdrawInterval(uint _fillerWithdrawInterval) private {
    //     emit NewFillerWithdrawInterval(fillerWithdrawInterval, _fillerWithdrawInterval);
    //     fillerWithdrawInterval = _fillerWithdrawInterval;
    // }

    /// @notice Internal setter for relay contract address
    function _setRelay(address _relay) private nonZeroAddress(_relay) {
        emit NewRelay(relay, _relay);
        relay = _relay;
    }

    /// @notice Internal setter for specialTeleporter address
    function _setSpecialTeleporter(address _specialTeleporter)
        private
        nonZeroAddress(_specialTeleporter)
    {
        emit NewSpecialTeleporter(specialTeleporter, _specialTeleporter);
        specialTeleporter = _specialTeleporter;
    }

    /// @notice Internal setter for lockers contract address
    function _setLockers(address _lockers) private nonZeroAddress(_lockers) {
        emit NewLockers(lockers, _lockers);
        lockers = _lockers;
    }

    /// @notice Internal setter for teleBTC contract address
    function _setTeleBTC(address _teleBTC) private nonZeroAddress(_teleBTC) {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
    }

    /// @notice Internal setter for protocol percentage fee
    function _setProtocolPercentageFee(uint256 _protocolPercentageFee) private {
        require(
            MAX_PROTOCOL_FEE >= _protocolPercentageFee,
            "CCExchangeRouter: fee is out of range"
        );
        emit NewProtocolPercentageFee(
            protocolPercentageFee,
            _protocolPercentageFee
        );
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice Internal setter for starting block number
    function _setStartingBlockNumber(uint256 _startingBlockNumber) private {
        require(
            _startingBlockNumber > startingBlockNumber,
            "CCExchangeRouter: low startingBlockNumber"
        );
        startingBlockNumber = _startingBlockNumber;
    }

    /// @notice Internal setter for treasury
    function _setTreasury(address _treasury) private nonZeroAddress(_treasury) {
        emit NewTreasury(treasury, _treasury);
        treasury = _treasury;
    }

    /// @notice Internal setter for across
    function _setAcross(address _across) private nonZeroAddress(_across) {
        emit AcrossUpdated(across, _across);
        across = _across;
    }

    /// @notice Internal setter for burnRouter
    function _setBurnRouter(address _burnRouter)
        private
        nonZeroAddress(_burnRouter)
    {
        emit BurnRouterUpdated(burnRouter, _burnRouter);
        burnRouter = _burnRouter;
    }

    /// @notice Internal setter for third party address
    function _setThirdPartyAddress(
        uint256 _thirdPartyId,
        address _thirdPartyAddress
    ) private {
        emit NewThirdPartyAddress(
            _thirdPartyId,
            thirdPartyAddress[_thirdPartyId],
            _thirdPartyAddress
        );
        thirdPartyAddress[_thirdPartyId] = _thirdPartyAddress;
    }

    /// @notice Internal setter for third party fee
    function _setThirdPartyFee(uint256 _thirdPartyId, uint256 _thirdPartyFee)
        private
    {
        emit NewThirdPartyFee(
            _thirdPartyId,
            thirdPartyFee[_thirdPartyId],
            _thirdPartyFee
        );
        thirdPartyFee[_thirdPartyId] = _thirdPartyFee;
    }

    /// @notice Internal setter for wrappedNativeToken
    function _setWrappedNativeToken(address _wrappedNativeToken) private {
        emit NewWrappedNativeToken(wrappedNativeToken, _wrappedNativeToken);
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @notice Internal setter for chain id mapping
    function _setChainIdMapping(
        uint256 _destinationChain,
        uint256 _mappedId
    ) private {
        emit NewChainIdMapping(_destinationChain, _mappedId);
        chainIdMapping[_mappedId] = chainIdStruct(
            chainId,
            _destinationChain
        );
    }
}
