// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./CcExchangeRouterStorage.sol";
import "./CcExchangeRouterStorageV2.sol";
import "./interfaces/IBurnRouter.sol";
import "./interfaces/ICcExchangeRouter.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockers/interfaces/ILockers.sol";
import "../libraries/CcExchangeRouterLib2.sol";
import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";

contract CcExchangeRouterLogic is CcExchangeRouterStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable, CcExchangeRouterStorageV2 {

    using BytesLib for bytes;

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "ExchangeRouter: zero address");
        _;
    }

    // Contract is payable
    receive() external payable {}

    /// @notice Gives default params to initiate cc exchange router
    /// @param _startingBlockNumber Requests that are included in a block older 
    ///                             than _startingBlockNumber cannot be executed
    /// @param _protocolPercentageFee Percentage amount of protocol fee (min: %0.01)
    /// @param _chainId Id of the target chain
    /// @param _relay The Relay address to validate data from source chain
    /// @param _lockers Lockers' contract address
    /// @param _teleBTC TeleportDAO BTC ERC20 token address
    /// @param _treasury Address of treasury that collects protocol fees
    function initialize(
        uint _startingBlockNumber,
        uint _protocolPercentageFee,
        uint _chainId,
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
        isChainSupported[chainId] = true;
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
    function setStartingBlockNumber(uint _startingBlockNumber) external override onlyOwner {
        _setStartingBlockNumber(_startingBlockNumber);
    }

    /// @notice Updates relay contract address
    function setRelay(address _relay) external override onlyOwner {
        _setRelay(_relay);
    }

    /// @notice                 Changes instantRouter contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instantRouter contract address
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        _setInstantRouter(_instantRouter);
    }

    /// @notice Updates lockers contract address
    function setLockers(address _lockers) external override onlyOwner {
        _setLockers(_lockers);
    }

    /// @notice Sets appId for an exchange connector
    /// @dev _exchangeConnector can be set to zero to inactive an app
    function setExchangeConnector(
        uint _appId, 
        address _exchangeConnector
    ) external override onlyOwner {
        exchangeConnector[_appId] = _exchangeConnector;
        emit SetExchangeConnector(_appId, _exchangeConnector);
    }

    /// @notice Updates teleBTC contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        _setTeleBTC(_teleBTC);
    }

    /// @notice Setter for protocol percentage fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        _setProtocolPercentageFee(_protocolPercentageFee);
    }

    /// @notice Setter for treasury
    function setTreasury(address _treasury) external override onlyOwner {
        _setTreasury(_treasury);
    }

    /// @notice Setter for filler withdraw interval
    /// @dev Assuming that filling is started at X, 
    ///      fillers cannot withdraw their funds before x + _fillerWithdrawInterval
    ///      (unless that filling is completed)
    function setFillerWithdrawInterval(uint _fillerWithdrawInterval) external override onlyOwner {
        _setFillerWithdrawInterval(_fillerWithdrawInterval);
    }

    /// @notice Setter for across
    function setAcross(address _across) external override onlyOwner {
        _setAcross(_across);
    }

    /// @notice Setter for burnRouters
    function setBurnRouter(address _burnRouter) external override onlyOwner {
        _setBurnRouter(_burnRouter);
    }

    /// @notice Adding a token
    function supportToken(address _token) external override onlyOwner {
        emit TokenAdded(_token);
        isTokenSupported[_token] = true;
    }

    /// @notice Removing a token
    function removeToken(address _token) external override onlyOwner {
        emit TokenRemoved(_token);
        isTokenSupported[_token] = false;
    }

    /// @notice Adding a new chainId
    function supportChain(uint _chainId) external override onlyOwner {
        emit ChainAdded(_chainId);
        isChainSupported[_chainId] = true;
    }

    /// @notice Removing a chainId
    function removeChain(uint _chainId) external override onlyOwner {
        emit ChainRemoved(_chainId);
        isChainSupported[_chainId] = false;
    }

    /// @notice Checks if a request has been executed before
    /// @dev It prevents re-submitting an executed request
    /// @param _txId The transaction ID of request on Bitcoin 
    /// @return True if the cc exchange request has been already executed
    function isRequestUsed(bytes32 _txId) external view override returns (bool) {
        return ccExchangeRequests[_txId].isUsed ? true : false;
    }

    function extractChainId(uint chainId) public view returns (uint, uint) {
        return (chainIdMapping[chainId].middleChain, chainIdMapping[chainId].destinationChain);
    }

    function extractDestinationChainId(uint chainId) public view returns (uint) {
        return chainIdMapping[chainId].destinationChain;
    }

    function setMappingChainId(uint middleChain, uint destinationChain, uint mappedId) public {
        chainIdMapping[mappedId] = chainIdStruct(
            middleChain, 
            destinationChain
        );
    }

    /// @notice Executes a cross-chain exchange request after checking its merkle inclusion proof
    /// @dev Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript Script hash of locker that user has sent BTC to it
    /// @param _path (Optional) Exchange path from teleBTC to the output token. This is used if 
    ///              the default path [teleBTC, wrappedNativeToken, outputToken] not exist or
    ///              exchanging using this path fails
    /// @return true 
    function ccExchange(
        TxAndProof memory _txAndProof,
        bytes calldata _lockerLockingScript,
        address[] memory _path
    ) external payable nonReentrant override virtual returns (bool) {
        // Basic checks
        require(_msgSender() == instantRouter, "ExchangeRouter: invalid sender"); // Only Teleporter can submit requests
        require(_txAndProof.blockNumber >= startingBlockNumber, "ExchangeRouter: old request");
        require(_txAndProof.locktime == bytes4(0), "ExchangeRouter: non-zero locktime");

        // Checks that the given script hash is locker
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "ExchangeRouter: not locker"
        );

        // Extracts information from the request
        bytes32 txId = CcExchangeRouterLib.ccExchangeHelper(
            _txAndProof,
            ccExchangeRequests,
            extendedCcExchangeRequests,
            teleBTC,
            wrappedNativeToken,
            MAX_PROTOCOL_FEE,
            _lockerLockingScript
        );

        // Checks if transaction has been finalized on Bitcoin
        require(
            CcExchangeRouterLib._isConfirmed(
                relay,
                txId,
                _txAndProof
            ),
            "ExchangeRouter: not finalized"
        );

        (uint middleChainId, uint destinationChainId) = extractChainId(extendedCcExchangeRequests[txId].chainId);

        require(middleChainId == chainId, "ExchangeRouter: wrong chain");

        require(
            isChainSupported[destinationChainId],
            "ExchangeRouter: invalid chain id"
        );

        ccExchangeRequest memory request = ccExchangeRequests[txId];
    
        address _exchangeConnector = exchangeConnector[request.appId];
        require(
            _exchangeConnector != address(0), 
            "ExchangeRouter: invalid appId"
        );

        // Finds remained amount after reducing fees
        extendedCcExchangeRequests[txId].remainedInputAmount = _mintAndReduceFees(
            _lockerLockingScript, 
            txId
        );
                
        if (
            request.speed == 1 && 
            _canFill(
                txId, 
                request.path[request.path.length - 1], // output token 
                request.outputAmount
            )
        ) {
            // Fills exchange request
            _fillCcExchange(
                _lockerLockingScript, 
                txId, 
                request
            );

        } else {
            if (destinationChainId == chainId) { // Requests that belongs to the current chain
                // Normal exchange request or a request which has not been filled
                _ccExchange(
                    _exchangeConnector, 
                    _lockerLockingScript, 
                    txId, 
                    _path
                );
            } else {
                _ccExchangeToOtherChain(
                    _exchangeConnector, 
                    _lockerLockingScript, 
                    txId, 
                    _path, 
                    extendedCcExchangeRequests[txId].acrossFeePercentage,
                    destinationChainId
                );
            }
        }

        return true;
    }

    /// @notice Filler fills an upcoming exchange request
    /// @param _txId Bitcoin request that filler wants to fill
    /// @param _token Address of exchange token in the request
    /// @param _amount Requested exchanging amount
    function fillTx(
        bytes32 _txId,
        address _recipient,
        address _token,
        uint _amount,
        uint _requestAmount
    ) external override payable nonReentrant {
        require (_amount > 0,  "ExchangeRouter: zero amount");
        require (
            fillersData[_txId][_msgSender()].amount == 0, 
            "ExchangeRouter: already filled"
        );

        PrefixFillSum storage _prefixFillSum = prefixFillSums[_txId][_token];

        if (_prefixFillSum.currentIndex == 0) {
            // ^ This is the first filling
            _prefixFillSum.prefixSum.push(0);
            _prefixFillSum.currentIndex = 1;
        }

        // Stores the filling info
        uint index = _prefixFillSum.currentIndex;

        if (_requestAmount > _prefixFillSum.prefixSum[index]) {
            uint fillAmount = _requestAmount - _prefixFillSum.prefixSum[index];

            if (_token == NATIVE_TOKEN) {
                require(msg.value >= fillAmount, "ExchangeRouter: incorrect amount");
                (bool sentToRecipient, bytes memory data1) = _recipient.call{value: fillAmount}("");
                (bool sentToFiller, bytes memory data2) = _msgSender().call{value: fillAmount}("");
                require(
                    sentToRecipient == true && sentToFiller == true,
                    "ExchangeRouter: failed to transfer native token"
                );
            } else {
                require(
                    IERC20(_token).transferFrom(_msgSender(), _recipient, fillAmount),
                    "ExchangeRouter: no allowance"
                ); 
            }

            fillersData[_txId][_msgSender()] = FillerData(_prefixFillSum.currentIndex, _token, fillAmount);

            // Updates the cumulative filling
            _prefixFillSum.prefixSum.push(_prefixFillSum.prefixSum[index - 1] + fillAmount);
            _prefixFillSum.currentIndex += 1;

            if (fillsData[_txId].startingTime == 0) {  
                // ^ No one has filled before
                fillsData[_txId].startingTime = block.timestamp;

                emit FillStarted(
                    _txId, 
                    block.timestamp
                );
            }

            emit NewFill(
                _msgSender(),
                _txId, 
                _token,
                fillAmount
            );
        }
    }

    /// @notice Fillers can withdraw their unused tokens
    /// @param _txId Bitcoin request which filling belongs to
    /// @return true if withdrawing was successful
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

    /// @notice Filler whose tokens has been used gets teleBTC
    /// @param _txId Bitcoin request which filling belongs to
    /// @return true if withdrawing was successful
    function getTeleBtcForFill(
       bytes32 _txId
    ) external override nonReentrant returns (bool) {
        FillData memory fillData = fillsData[_txId];
        FillerData memory fillerData = fillersData[_txId][_msgSender()];
        
        if (fillData.lastUsedIdx > fillerData.index) {
            // ^ This filling has been fully used
            uint amount = extendedCcExchangeRequests[_txId].remainedInputAmount 
                * fillerData.amount / ccExchangeRequests[_txId].outputAmount;
            require(
                ITeleBTC(teleBTC).transfer(_msgSender(), amount), 
                "ExchangeRouter: can't transfer TeleBTC"
            );
            fillersData[_txId][_msgSender()].amount = 0;

            emit FillTeleBtcSent(
                fillerData.amount,
                0,
                fillerData.token,
                _msgSender(),
                fillerData.index,
                _txId,
                extendedCcExchangeRequests[_txId].remainedInputAmount,
                amount
            );
            return true;
        }

        // We treat last used filling separately since part of it may only have been used
        if (fillData.lastUsedIdx == fillerData.index) {
            uint amount = (fillerData.amount - fillData.remainingAmountOfLastFill) 
                * extendedCcExchangeRequests[_txId].remainedInputAmount / ccExchangeRequests[_txId].outputAmount;
            require(
                ITeleBTC(teleBTC).transfer(_msgSender(), amount),
                "ExchangeRouter: can't transfer TeleBTC"
            );
            fillersData[_txId][_msgSender()].amount = 0;

            emit FillTeleBtcSent(
                fillerData.amount,
                fillData.remainingAmountOfLastFill,
                fillerData.token,
                _msgSender(),
                fillerData.index,
                _txId,
                extendedCcExchangeRequests[_txId].remainedInputAmount,
                amount
            );
            return true;
        }

        return false;
    }

    /// @notice ETH user whose request failed can redeem teleBTC for native BTC
    /// @return
    function withdrawFailedCcExchange(
        bytes32 _txId,
        uint8 _scriptType,
        bytes memory _userScript,
        uint _acrossRelayerFee,
        bytes32 _r,
        bytes32 _s,
        uint8 _v,
        bytes calldata _lockerLockingScript
    ) external nonReentrant override returns (bool) {
        require(_msgSender() == instantRouter, "ExchangeRouter: invalid sender");

        /* Checks that:
           1. Request doesn't belong to the current chain
           2. Request execution has been failed
        */
        require(
            extendedCcExchangeRequests[_txId].chainId != chainId
            && extendedCcExchangeRequests[_txId].isTransferredToEth == false,
            "ExchangeRouter: already processed"
        );
        extendedCcExchangeRequests[_txId].isTransferredToEth = true;

        require(
            CcExchangeRouterLib._verifySig(
                _hashMsg(
                    abi.encodePacked(_txId, _scriptType, _userScript, _acrossRelayerFee)
                ),
                _r,
                _s,
                _v
            ) == ccExchangeRequests[_txId].recipientAddress,
            "ExchangeRouter: invalid signer"
        );

        // Burns teleBTC for user
        ITeleBTC(teleBTC).approve(
            burnRouter,
            extendedCcExchangeRequests[_txId].remainedInputAmount
        );

        IBurnRouter(burnRouter).ccBurn(
            extendedCcExchangeRequests[_txId].remainedInputAmount,
            _userScript,
            ScriptTypes(_scriptType),
            _lockerLockingScript
        );

        return true;
    }

    /// @notice ETH user whose exchange request failed can retry 
    ///         to exchange teleBTC for the desired token
    function retryFailedCcExchange(
        bytes32 _txId,
        uint256 _outputAmount,
        uint _acrossRelayerFee,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) external nonReentrant override returns (bool) {
        require(_msgSender() == instantRouter, "ExchangeRouter: invalid sender");

        ccExchangeRequest memory exchangeReq = ccExchangeRequests[_txId];

        /* Checks that:
           1. Request doesn't belong to the current chain
           2. Request execution has been failed
        */
        require(
            extendedCcExchangeRequests[_txId].chainId != chainId
            && extendedCcExchangeRequests[_txId].isTransferredToEth == false, 
            "ExchangeRouter: already processed"
        );
        extendedCcExchangeRequests[_txId].isTransferredToEth = true;

        require(
            CcExchangeRouterLib._verifySig(
                _hashMsg(
                    abi.encodePacked(_txId, _outputAmount, _acrossRelayerFee)
                ),
                _r,
                _s,
                _v
            ) == exchangeReq.recipientAddress,
            "ExchangeRouter: invalid signer"
        );

        // Exchanges teleBTC for desired exchange token
        (bool result, uint[] memory amounts) = IExchangeConnector(exchangeConnector[exchangeReq.appId]).swap(
            extendedCcExchangeRequests[_txId].remainedInputAmount,
            _outputAmount,
            exchangeReq.path,
            address(this), // Sends tokens to this contract
            block.timestamp,
            true // Input token is fixed
        );
        require(result, "ExchangeRouter: swap failed");

        // Sends exchanged tokens to ETH
        _sendTokenToOtherChain(
            extendedCcExchangeRequests[_txId].chainId,
            exchangeReq.path[exchangeReq.path.length - 1], 
            amounts[amounts.length - 1], 
            exchangeReq.recipientAddress,
            _acrossRelayerFee
        );

        return true;
    }

    /// @notice Finds hash of the message that user should have signed
    function _hashMsg(
        bytes memory _data
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32", 
                keccak256(_data)
            )
        );
    }

    /// @notice Sends tokens to the destination using across
    function _sendTokenToOtherChain(
        uint _chainId,
        address _token,
        uint _amount,
        address _user,
        uint _acrossRelayerFee
    ) private {
        IERC20(_token).approve(
            across, 
            _amount
        );
        SpokePoolInterface(across).deposit(
            _user,
            _token,
            _amount,
            extractDestinationChainId(_chainId),
            int64(uint64(_acrossRelayerFee)),
            uint32(block.timestamp),
            "0x", // Null data
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );  
    }

    /// @notice Executes the exchange request
    /// @dev Mints teleBTC for user if exchanging is not successful
    function _ccExchange(
        address _exchangeConnector,
        bytes memory _lockerLockingScript, 
        bytes32 _txId,
        address[] memory _path
    ) internal {
        // bool result;
        // uint[] memory amounts;
        
        (bool result, uint[] memory amounts) = _swap(
            true,
            _lockerLockingScript,
            ccExchangeRequests[_txId],
            extendedCcExchangeRequests[_txId],
            _txId,
            _path,
            _exchangeConnector
        );

        if (!result) {
            address[] memory alterPath1 = new address[](2);
            alterPath1[0] = teleBTC;
            alterPath1[1] = _path[_path.length - 1];

            (bool result, uint[] memory amounts) = _swap(
                true,
                _lockerLockingScript,
                ccExchangeRequests[_txId],
                extendedCcExchangeRequests[_txId],
                _txId,
                alterPath1,
                _exchangeConnector
            );
            if (!result) {
                // Sends teleBTC to recipient if exchange wasn't successful
                ITeleBTC(teleBTC).transfer(
                    ccExchangeRequests[_txId].recipientAddress,
                    extendedCcExchangeRequests[_txId].remainedInputAmount
                );
            }
        }
    }

    /// @notice                          Executes a normal cross-chain exchange request
    /// @dev                             Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript      Locker's locking script    
    /// @param _txId                     Id of the transaction containing the user request
    function _ccExchangeToOtherChain(
        address _exchangeConnector,
        bytes memory _lockerLockingScript, 
        bytes32 _txId,
        address[] memory _path,
        uint _acrossRelayerFee, // TODO be max not exact
        uint chainId
    ) private {
        (bool result, uint[] memory amounts) = _swap(
            false,
            _lockerLockingScript,
            ccExchangeRequests[_txId],
            extendedCcExchangeRequests[_txId],
            _txId, 
            _path,
            _exchangeConnector
        );

        if (result) {
            extendedCcExchangeRequests[_txId].isTransferredToEth = true;
            // Send exchanged tokens to ETH
            _sendTokenToOtherChain(
                extendedCcExchangeRequests[_txId].chainId,
                ccExchangeRequests[_txId].path[ccExchangeRequests[_txId].path.length - 1], 
                amounts[amounts.length-1], 
                ccExchangeRequests[_txId].recipientAddress,
                _acrossRelayerFee // TODO fix in future
            );
        } else {
            // send telebtc to polygon address
            ITeleBTC(teleBTC).transfer(
                ccExchangeRequests[_txId].recipientAddress, 
                extendedCcExchangeRequests[_txId].remainedInputAmount
            );
        }
    }

    function _swap(
        bool _isCurrentChain,
        bytes memory _lockerLockingScript,
        ccExchangeRequest memory _ccExchangeRequest,
        extendedCcExchangeRequest memory _extendedCcExchangeRequest,
        bytes32 _txId,
        address[] memory _path,
        address _exchangeConnector
    ) private returns (bool result, uint[] memory amounts) {
        if (
            _isCurrentChain ||
            isTokenSupported[_ccExchangeRequest.path[_ccExchangeRequest.path.length - 1]]
        ) {
            // Either the destination chain should be the current chain or 
            // we should be able to send exchanged tokens to the destination chain

            // Gives allowance to exchange connector for swapping
            ITeleBTC(teleBTC).approve(
                _exchangeConnector,
                _extendedCcExchangeRequest.remainedInputAmount
            );

            if (
                IExchangeConnector(_exchangeConnector).isPathValid(_ccExchangeRequest.path)
            ) {
                require(
                    _path[0] == teleBTC && 
                    _path[_path.length - 1] == _ccExchangeRequest.path[_ccExchangeRequest.path.length - 1],
                    "CcExchangeRouter: invalid path"
                );
                (result, amounts) = IExchangeConnector(_exchangeConnector).swap(
                    _extendedCcExchangeRequest.remainedInputAmount,
                    _ccExchangeRequest.outputAmount,
                    _path,
                    _ccExchangeRequest.recipientAddress,
                    block.timestamp,
                    true
                );
            }
        } else {
            result = false;
        }

        if (result) {
            emit CCExchange(
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                _ccExchangeRequest.recipientAddress,
                [
                    teleBTC, 
                    _ccExchangeRequest.path[_ccExchangeRequest.path.length - 1]
                ], // [input token, output token]
                [amounts[0], amounts[amounts.length-1]], // [input amount, output amount]
                _ccExchangeRequest.speed,
                _msgSender(), // Teleporter address
                _ccExchangeRequest.fee,
                _txId,
                _ccExchangeRequest.appId
            );
        } else { // Handles situation where exchange was not successful
            emit FailedCCExchange(
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                _ccExchangeRequest.recipientAddress,
                [
                    teleBTC, 
                    _ccExchangeRequest.path[_ccExchangeRequest.path.length - 1]
                ], // [input token, output token]
                [_extendedCcExchangeRequest.remainedInputAmount, 0], // [input amount, output amount]
                _ccExchangeRequest.speed,
                _msgSender(), // Teleporter address
                _ccExchangeRequest.fee,
                _txId,
                _ccExchangeRequest.appId
            );
        }
    }

    /// @notice Checks that if request can be filled
    /// @dev Request can be filled if 
    ///      1. Filling deadline has not been passed
    ///      2. At least one filler exists
    ///      3. Filled amount is greater than or equal of the requested amount
    function _canFill(
        bytes32 _txId, 
        address _token, 
        uint256 _amount
    ) private view returns (bool) {
        PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][_token];

        if (
            block.timestamp <= fillsData[_txId].startingTime + fillerWithdrawInterval &&
            _prefixFillSum.currentIndex > 0 &&
            _prefixFillSum.prefixSum[_prefixFillSum.currentIndex - 1] >= _amount
        ) {
            return true;
        } else {
            return false;
        }
    }

    /// @notice Executes the exchange request with filler
    function _fillCcExchange(
        bytes memory _lockerLockingScript, 
        bytes32 _txId,
        ccExchangeRequest memory _request
    ) private {
        address outputToken = _request.path[_request.path.length - 1];

        FillData memory _txFillData;
        _txFillData.reqToken = outputToken;

        PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][outputToken];
        _txFillData.lastUsedIdx = _findlastUsedIdxOfFill(_prefixFillSum, _request.outputAmount);
        _txFillData.remainingAmountOfLastFill = _prefixFillSum.prefixSum[_txFillData.lastUsedIdx] 
            - _request.outputAmount;

        // Saves the filling data
        fillsData[_txId] = _txFillData;
        
        uint _chainId = extendedCcExchangeRequests[_txId].chainId;
        if (_chainId == chainId) {
            if (outputToken == NATIVE_TOKEN) {
                Address.sendValue(
                    payable(_request.recipientAddress),
                    _request.outputAmount
                );
            } else {
                IERC20(outputToken).transfer(
                    _request.recipientAddress, 
                    _request.outputAmount
                );
            }
        } else {
            _sendTokenToOtherChain(
                extendedCcExchangeRequests[_txId].chainId,
                _request.path[_request.path.length - 1], 
                _request.outputAmount, 
                _request.recipientAddress,
                extendedCcExchangeRequests[_txId].acrossFeePercentage
            );
        }

        emit CCExchange(
            ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
            _request.recipientAddress,
            [teleBTC, outputToken], // [input token, output token]
            [extendedCcExchangeRequests[_txId].remainedInputAmount, _request.outputAmount], // [input amount, output amount]
            _request.speed,
            _msgSender(), // Teleporter address
            _request.fee,
            _txId,
            _request.appId
        );
    }

    function _findlastUsedIdxOfFill(
        PrefixFillSum memory _prefixFillSum, 
        uint256 _amount
    ) private pure returns(uint)  {
        uint[] memory sumArray = _prefixFillSum.prefixSum;
        int l = -1;
        int r = int(_prefixFillSum.currentIndex);
        while (r - l > 1) {
            int mid = (l + r) >> 1;
            if (sumArray[uint(mid)] >= _amount)
                r = mid;
            else
                l = mid;
        }
        return uint(r);
    }

    /// @notice Mints teleBTC by calling lockers contract
    /// @param _lockerLockingScript Locker's locking script
    /// @param _txId The transaction ID of the request
    /// @return _remainedAmount Amount of teleBTC that user receives 
    ///                         after reducing all fees (protocol, locker, teleporter)
    function _mintAndReduceFees(
        bytes memory _lockerLockingScript,
        bytes32 _txId
    ) private returns (uint _remainedAmount) {

        // Mints teleBTC for cc exchange router
        uint mintedAmount = ILockers(lockers).mint(
            _lockerLockingScript,
            address(this),
            ccExchangeRequests[_txId].inputAmount
        );

        // Calculates fees
        uint protocolFee = ccExchangeRequests[_txId].inputAmount*protocolPercentageFee/MAX_PROTOCOL_FEE;
        uint teleporterFee = ccExchangeRequests[_txId].fee;

        // Pays Teleporter fee
        if (teleporterFee > 0) {
            ITeleBTC(teleBTC).transfer(_msgSender(), teleporterFee);
        }

        // Pays protocol fee
        if (protocolFee > 0) {
            ITeleBTC(teleBTC).transfer(treasury, protocolFee);
        }

        _remainedAmount = mintedAmount - protocolFee - teleporterFee;
    }

    /// @notice Internal setter for filler withdraw interval
    function _setFillerWithdrawInterval(uint _fillerWithdrawInterval) private {
        emit NewFillerWithdrawInterval(fillerWithdrawInterval, _fillerWithdrawInterval);
        fillerWithdrawInterval = _fillerWithdrawInterval;
    }

    /// @notice Internal setter for relay contract address
    function _setRelay(address _relay) private nonZeroAddress(_relay) {
        emit NewRelay(relay, _relay);
        relay = _relay;
    }

    /// @notice Internal setter for instantRouter contract address
    function _setInstantRouter(address _instantRouter) private nonZeroAddress(_instantRouter) {
        emit NewInstantRouter(instantRouter, _instantRouter);
        instantRouter = _instantRouter;
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
    function _setProtocolPercentageFee(uint _protocolPercentageFee) private {
        require(
            MAX_PROTOCOL_FEE >= _protocolPercentageFee,
            "ExchangeRouter: fee is out of range"
        );
        emit NewProtocolPercentageFee(protocolPercentageFee, _protocolPercentageFee);
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice Internal setter for starting block number
    function _setStartingBlockNumber(uint _startingBlockNumber) private {
        require(
            _startingBlockNumber > startingBlockNumber,
            "ExchangeRouter: low startingBlockNumber"
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
    function _setBurnRouter(address _burnRouter) private nonZeroAddress(_burnRouter) {
        emit BurnRouterUpdated(burnRouter, _burnRouter);
        burnRouter = _burnRouter;
    }
}
