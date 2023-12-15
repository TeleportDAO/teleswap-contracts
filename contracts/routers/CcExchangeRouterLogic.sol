// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./CcExchangeRouterStorage.sol";
import "./interfaces/IBurnRouter.sol";
import "./interfaces/ICcExchangeRouter.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockers/interfaces/ILockers.sol";
import "../libraries/CcExchangeRouterLib.sol";
import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";

contract CcExchangeRouterLogic is CcExchangeRouterStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using BytesLib for bytes;

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CCExchangeRouter: zero address");
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

    /// @notice Setter for a supported exchange token
    function addSupportedExchangeToken(address _token) external override onlyOwner {
        emit ExchangeTokenAdded(_token);
        isExchangeTokenSupported[_token] = true;
    }

    /// @notice Remover for a supported exchange token
    function removeSupportedExchangeToken(address _token) external override onlyOwner {
        emit ExchangeTokenRemoved(_token);
        isExchangeTokenSupported[_token] = false;
    }

    /// @notice Checks if a request has been executed before
    /// @dev It prevents re-submitting an executed request
    /// @param _txId The transaction ID of request on Bitcoin 
    /// @return True if the cc exchange request has been already executed
    function isRequestUsed(bytes32 _txId) external view override returns (bool) {
        return ccExchangeRequests[_txId].isUsed ? true : false;
    }

    /// @notice Executes a cross-chain exchange request after checking its merkle inclusion proof
    /// @dev Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript Script hash of locker that user has sent BTC to it
    /// @return true 
    function ccExchange(
        TxAndProof memory _txAndProof,
        bytes calldata _lockerLockingScript,
        address[] memory _path,
        int64 _acrossRelayerFee
    ) external payable nonReentrant override virtual returns (bool) {
        // Basic checks
        require(_msgSender() == instantRouter, "CCExchangeRouter: invalid sender");
        require(_txAndProof.blockNumber >= startingBlockNumber, "CCExchangeRouter: old request");
        require(_txAndProof.locktime == bytes4(0), "CCExchangeRouter: non-zero locktime");

        // Checks that given script hash is locker
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCExchangeRouter: not locker"
        );

        // Extracts information from the request
        bytes32 txId = CcExchangeRouterLib.ccExchangeHelper(
            relay,
            _txAndProof,
            ccExchangeRequests,
            extendedCcExchangeRequests,
            teleBTC,
            wrappedNativeToken,
            MAX_PROTOCOL_FEE,
            _lockerLockingScript
        );

        uint _chainId = extendedCcExchangeRequests[txId].chainId;
        require(
            _chainId == chainId || _chainId == ethChainId,
            "CCExchangeRouter: wrong chain id"
        );

        ccExchangeRequest memory request = ccExchangeRequests[txId];
                
        if (
            request.speed == 1 && 
            _canFill(txId, request.path[1], request.outputAmount)
        ) {
            // Fills exchange request
            _fillCcExchange(_lockerLockingScript, txId, request);

            // TODO: FILL FOR ETH REQUEST
        } else {
            require(
                exchangeConnector[ccExchangeRequests[txId].appId] != address(0), 
                "CCExchange: invalid appId"
            );

            // Gets remained amount after reducing fees
            extendedCcExchangeRequests[txId].remainedInputAmount = _mintAndReduceFees(
                _lockerLockingScript, 
                txId
            );

            if (_chainId == chainId) {
                // Normal exchange request or a request which has not been filled
                _ccExchange(_lockerLockingScript, txId, _path);
            } else {
                _ccExchangeToEth(_lockerLockingScript, txId, _path, _acrossRelayerFee);
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
        address _token,
        uint _amount
    ) external override payable nonReentrant {
        require (_amount > 0,  "CCExchangeRouter: zero amount");
        require (
            fillersData[_txId][_msgSender()].amount == 0, 
            "CCExchangeRouter: already filled"
        );

        PrefixFillSum storage _prefixFillSum = prefixFillSums[_txId][_token];

        if (_token == NATIVE_TOKEN) {
            require(msg.value == _amount, "CCExchangeRouter: incorrect amount");
        } else {
            require(
                ERC20(_token).transferFrom(_msgSender(), address(this), _amount),
                "CCExchangeRouter: no allowance"
            ); 
        }

        if (_prefixFillSum.currentIndex == 0) {
            // ^ This is the first filling
            _prefixFillSum.prefixSum.push(0);
            _prefixFillSum.currentIndex = 1;
        }

        // Stores the filling info
        uint index = _prefixFillSum.currentIndex;
        fillersData[_txId][_msgSender()] = FillerData(_prefixFillSum.currentIndex, _token, _amount);

        // Updates the cumulative filling
        _prefixFillSum.prefixSum.push(_prefixFillSum.prefixSum[index - 1] + _amount);
        _prefixFillSum.currentIndex += 1;

        // TODO: comment? prefixFillSums[_txId][_token] = _prefixFillSum;

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
            _amount
        );
    }

    /// @notice Fillers can withdraw their unused tokens
    /// @param _txId Bitcoin request which filling belongs to
    /// @return true if withdrawing was successful
    function returnUnusedFill(
        bytes32 _txId
    ) external override nonReentrant returns (bool) {
        FillData memory fillData = fillsData[_txId];

        // To withdraw tokens, either request should have been processed or 
        // deadline for processing should has been passed
        require (
            ccExchangeRequests[_txId].inputAmount > 0 || 
                fillData.startingTime + fillerWithdrawInterval < block.timestamp, 
            "CCExchangeRouter: req not processed nor time not passed"
        );

        FillerData memory fillerData = fillersData[_txId][_msgSender()];
        
        // To withdraw token, either token should be wrong or token should have not been used
        if (fillData.reqToken != fillerData.token || fillData.lastUsedIdx < fillerData.index) {
            if (fillerData.token == NATIVE_TOKEN) {
                require(
                    payable(_msgSender()).send(fillerData.amount), 
                    "CCExchangeRouter: can't send Ether"
                );
            } else {
                require(
                    ERC20(fillerData.token).transfer(_msgSender(), fillerData.amount), 
                    "CCExchangeRouter: can't transfer token"
                );
            }
            fillersData[_txId][_msgSender()].amount = 0;

            emit FillTokensReturned(
                fillerData.amount,
                fillerData.token,
                _msgSender(),
                fillerData.index,
                _txId
            );
            return true;
        }

        // Last used filling may used partially, so filler can withdraw remaining amount
        if (
            fillData.lastUsedIdx == fillerData.index && 
            fillsData[_txId].isWithdrawnLastFill == false
        ) {
            if (fillerData.token == NATIVE_TOKEN) {
                require(
                    payable(_msgSender()).send(fillData.remainingAmountOfLastFill), 
                    "CCExchangeRouter: can't send Ether"
                );
            } else {
                require(
                    ERC20(fillerData.token).transfer(_msgSender(), fillData.remainingAmountOfLastFill), 
                    "CCExchangeRouter: can't transfer token"
                );
            }
            fillsData[_txId].isWithdrawnLastFill = true;

            emit FillTokensReturned(
                fillData.remainingAmountOfLastFill,
                fillerData.token,
                _msgSender(),
                fillerData.index,
                _txId
            );
            return true;
        }

        return false;
    }

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
            uint amount = teleBtcAmount[_txId] * fillerData.amount / ccExchangeRequests[_txId].outputAmount;
            require(
                ITeleBTC(teleBTC).transfer(_msgSender(), amount), 
                "CCExchangeRouter: can't transfer TeleBTC"
            );
            fillersData[_txId][_msgSender()].amount = 0;

            emit FillTeleBtcSent(
                fillerData.amount,
                0,
                fillerData.token,
                _msgSender(),
                fillerData.index,
                _txId,
                teleBtcAmount[_txId],
                amount
            );
            return true;
        }

        // We treat last used filling separately since part of it may only have been used
        if (fillData.lastUsedIdx == fillerData.index) {
            uint amount = (fillerData.amount - fillData.remainingAmountOfLastFill) 
                * teleBtcAmount[_txId] / ccExchangeRequests[_txId].outputAmount;
            require(
                ITeleBTC(teleBTC).transfer(_msgSender(), amount),
                "CCExchangeRouter: can't transfer TeleBTC"
            );
            fillersData[_txId][_msgSender()].amount = 0;

            emit FillTeleBtcSent(
                fillerData.amount,
                fillData.remainingAmountOfLastFill,
                fillerData.token,
                _msgSender(),
                fillerData.index,
                _txId,
                teleBtcAmount[_txId],
                amount
            );
            return true;
        }

        return false;
    }

    /// @notice ETH user whose exchange request failed can redeem teleBTC for native BTC
    /// @param _message TODO
    /// @return
    function withdrawFailedCcExchange(
        bytes memory _message,
        bytes32 _r,
        bytes32 _s,
        uint8 _v,
        bytes calldata _lockerLockingScript
    ) external nonReentrant override returns (bool) {
        require(_msgSender() == instantRouter, "CCExchange: invalid sender");

        // Note: BurnRouter checks the validity of script (no need to check it here)
        uint8 scriptType = _message.toUint8(0);
        uint8 userScriptLength = _message.toUint8(8);
        bytes32 txId = _message.toBytes32(16);
        bytes memory userScript = _message.slice(48, uint256(userScriptLength));

        require(
            CcExchangeRouterLib._verifySig(
                _message,
                _r,
                _s,
                _v,
                ccExchangeRequests[txId].recipientAddress
            ),
            "CCExchange: invalid signer"
        );

        // Burns teleBTC for user
        ITeleBTC(teleBTC).approve(
            burnRouter,
            extendedCcExchangeRequests[txId].remainedInputAmount
        );
        IBurnRouter(burnRouter).ccBurn(
            extendedCcExchangeRequests[txId].remainedInputAmount,
            userScript,
            ScriptTypes(scriptType),
            _lockerLockingScript
        );

        return true;
    }

    /// @notice ETH user whose exchange request failed can retry to exchange teleBTC for the desired token
    /// @param _message TODO
    /// @return
    function retryFailedCcExchange(
        bytes memory _message,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) external nonReentrant override returns (bool) {
        require(_msgSender() == instantRouter, "CCExchange: invalid sender");

        bytes32 txId = _message.toBytes32(0);
        uint256 outputAmount = _message.toUint256(32);
        uint256 deadline = _message.toUint256(64);
        int64 acrossRelayerFee = int64(_message.toUint64(96));

        ccExchangeRequest memory exchangeReq = ccExchangeRequests[txId];
        require(
            !extendedCcExchangeRequests[txId].isTransferedToEth, 
            "CCExchange: already processed"
        );
        extendedCcExchangeRequests[txId].isTransferedToEth = true;

        require(
            CcExchangeRouterLib._verifySig(
                _message,
                _r,
                _s,
                _v,
                exchangeReq.recipientAddress
            ),
            "CCExchangeRouter: invalid signer"
        );

        // Exchanges teleBTC for desired exchange token
        bool result;
        uint[] memory amounts;
        (result, amounts) = IExchangeConnector(exchangeConnector[exchangeReq.appId]).swap(
            extendedCcExchangeRequests[txId].remainedInputAmount,
            outputAmount,
            exchangeReq.path,
            address(this),
            deadline,
            true // Input token is fixed
        );
        require(result, "CCExchangeRouter: swap failed");

        // FIXME: add all requirement

        // Sends exchanged tokens to ETH
        _sendTokenToEth(
            exchangeReq.path[1], 
            amounts[amounts.length-1], 
            exchangeReq.recipientAddress,
            acrossRelayerFee
        );

        return true;
    }

    function _sendTokenToEth(
        address _token,
        uint _amount,
        address _user,
        int64 _acrossRelayerFee
    ) private {
        ERC20(_token).approve(
            across, 
            _amount
        );
        SpokePoolInterface(across).deposit(
            _user,
            _token,
            _amount,
            ethChainId,
            _acrossRelayerFee,
            uint32(block.timestamp),
            "0x", // Null data
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );  
    }

    /// @notice                          Executes a normal cross-chain exchange request
    /// @dev                             Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript      Locker's locking script    
    /// @param _txId                     Id of the transaction containing the user request
    function _ccExchange(
        bytes memory _lockerLockingScript, 
        bytes32 _txId,
        address[] memory _path
    ) internal {
        bool result;
        uint[] memory amounts;
        
        (result, amounts) = _swap(
            _lockerLockingScript,
            ccExchangeRequests[_txId],
            extendedCcExchangeRequests[_txId],
            _txId,
            ccExchangeRequests[_txId].recipientAddress,
            _path
        );

        if (!result) {
            // Sends teleBTC to recipient if exchange wasn't successful
            ITeleBTC(teleBTC).transfer(
                ccExchangeRequests[_txId].recipientAddress,
                extendedCcExchangeRequests[_txId].remainedInputAmount
            );
        }
    }

    /// @notice                          Executes a normal cross-chain exchange request
    /// @dev                             Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript      Locker's locking script    
    /// @param _txId                     Id of the transaction containing the user request
    function _ccExchangeToEth(
        bytes memory _lockerLockingScript, 
        bytes32 _txId,
        address[] memory _path,
        int64 _acrossRelayerFee
    ) private {
        bool result;
        uint[] memory amounts;
        
        (result, amounts) = _swap(
            _lockerLockingScript,
            ccExchangeRequests[_txId],
            extendedCcExchangeRequests[_txId],
            _txId, 
            address(this),
            _path
        );

        if (result) {
            // FIXME: add all requirement
            extendedCcExchangeRequests[_txId].isTransferedToEth = true;
            
            // Sends exchanged tokens to ETH
            _sendTokenToEth(
                ccExchangeRequests[_txId].path[1], 
                amounts[amounts.length-1], 
                ccExchangeRequests[_txId].recipientAddress,
                _acrossRelayerFee
            );
        }
    }

    function _swap(
        bytes memory _lockerLockingScript,
        ccExchangeRequest memory _ccExchangeRequest,
        extendedCcExchangeRequest memory _extendedCcExchangeRequest,
        bytes32 _txId,
        address _user,
        address[] memory _path
    ) private returns (bool result, uint[] memory amounts) {
        if (
            _extendedCcExchangeRequest.chainId == chainId ||
            isExchangeTokenSupported[_ccExchangeRequest.path[_ccExchangeRequest.path.length - 1]]
        ) {
            // ^ We should be able to send exchanged tokens to Ethereum
            // FIXME: in the case of failure TELEBTC will be stock in the contract, till its owner do something for it

            // Gives allowance to exchange connector to transfer from cc exchange router
            ITeleBTC(teleBTC).approve(
                exchangeConnector[_ccExchangeRequest.appId],
                _extendedCcExchangeRequest.remainedInputAmount
            );

            if (IExchangeConnector(exchangeConnector[_ccExchangeRequest.appId]).isPathValid(_ccExchangeRequest.path)) {
                (result, amounts) = IExchangeConnector(exchangeConnector[_ccExchangeRequest.appId]).swap(
                    _extendedCcExchangeRequest.remainedInputAmount,
                    _ccExchangeRequest.outputAmount,
                    _ccExchangeRequest.path,
                    _user,
                    _ccExchangeRequest.deadline,
                    true
                );
            } else {
                // Note: we only use the path provided by Teleporter if the default path
                //       doesn't exist (default path = [teleBTC, wrappedNativeToken, exchangeToken])
                require(
                    _path[0] == teleBTC && 
                    _path[_path.length - 1] == _ccExchangeRequest.path[_ccExchangeRequest.path.length - 1],
                    "CcExchangeRouter: invalid path"
                );
                (result, amounts) = IExchangeConnector(exchangeConnector[_ccExchangeRequest.appId]).swap(
                    _extendedCcExchangeRequest.remainedInputAmount,
                    _ccExchangeRequest.outputAmount,
                    _path,
                    _ccExchangeRequest.recipientAddress,
                    _ccExchangeRequest.deadline,
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
                    _ccExchangeRequest.path[0], 
                    _ccExchangeRequest.path[_ccExchangeRequest.path.length - 1]
                ], // [input token, output token]
                [amounts[0], amounts[amounts.length-1]], // [input amount, output amount]
                _ccExchangeRequest.speed,
                _msgSender(), // Teleporter address
                _ccExchangeRequest.fee,
                _txId,
                _ccExchangeRequest.appId
            );
        } else { // Handles situation when exchange was not successful
            // Revokes allowance
            ITeleBTC(teleBTC).approve(
                exchangeConnector[_ccExchangeRequest.appId],
                0
            );

            emit FailedCCExchange(
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                _ccExchangeRequest.recipientAddress,
                [
                    _ccExchangeRequest.path[0], 
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

    /// @notice Executes an exchange request with filler
    function _fillCcExchange(
        bytes memory _lockerLockingScript, 
        bytes32 _txId,
        ccExchangeRequest memory request
    ) private {
        // TODO add to doc
        // Gets remained amount after reducing fees
        uint remainedInputAmount = _mintAndReduceFees(_lockerLockingScript, _txId);

        FillData memory _txFillData;
        _txFillData.reqToken = request.path[1];

        PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][request.path[1]];
        _txFillData.lastUsedIdx = _findlastUsedIdxOfFill(_prefixFillSum, request.outputAmount);
        _txFillData.remainingAmountOfLastFill = _prefixFillSum.prefixSum[_txFillData.lastUsedIdx] 
            - request.outputAmount;

        // Saves the filling data and available teleBTC amount
        fillsData[_txId] = _txFillData;
        teleBtcAmount[_txId] = remainedInputAmount;
        
        if (request.path[1] == NATIVE_TOKEN) {
            Address.sendValue(
                payable(request.recipientAddress),
                request.outputAmount
            );
        } else {
            ERC20(request.path[1]).transfer(
                request.recipientAddress, 
                request.outputAmount
            );
        }

        emit CCExchange(
            ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
            request.recipientAddress,
            [request.path[0], request.path[1]], // [input token, output token]
            [remainedInputAmount, request.outputAmount], // [input amount, output amount]
            request.speed,
            _msgSender(), // Teleporter address
            request.fee,
            _txId,
            request.appId
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
    ) internal returns (uint _remainedAmount) {

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
            "CCExchangeRouter: fee is out of range"
        );
        emit NewProtocolPercentageFee(protocolPercentageFee, _protocolPercentageFee);
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice Internal setter for starting block number
    function _setStartingBlockNumber(uint _startingBlockNumber) private {
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
    function _setBurnRouter(address _burnRouter) private nonZeroAddress(_burnRouter) {
        emit BurnRouterUpdated(burnRouter, _burnRouter);
        burnRouter = _burnRouter;
    }
}
