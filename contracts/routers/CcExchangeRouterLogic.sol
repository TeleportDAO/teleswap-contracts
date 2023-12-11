// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./CcExchangeRouterStorage.sol";
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

contract CcExchangeRouterLogic is CcExchangeRouterStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable {

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
        address _treasury
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
        bytes calldata _lockerLockingScript
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
            chainId,
            teleBTC,
            MAX_PROTOCOL_FEE,
            _lockerLockingScript
        );

        ccExchangeRequest memory request = ccExchangeRequests[txId];
                
        if (
            request.speed == 1 && 
            _canFill(txId, request.path[1], request.outputAmount)
        ) {
            // Fills exchange request
            _fillCcExchange(_lockerLockingScript, txId, request);
        } else {
            // Normal exchange request or a request which has not been filled
            _normalCcExchange(_lockerLockingScript, txId);
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

    // TODO event
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
            return true;
        }

        return false;
    }

    /// @notice                          Executes a normal cross-chain exchange request
    /// @dev                             Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript      Locker's locking script    
    /// @param _txId                     Id of the transaction containing the user request
    function _normalCcExchange(bytes memory _lockerLockingScript, bytes32 _txId) internal {
        // Gets remained amount after reducing fees
        uint remainedInputAmount = _mintAndReduceFees(_lockerLockingScript, _txId);

        bool result;
        uint[] memory amounts;

        // Gets exchange connector address
        address _exchangeConnector = exchangeConnector[ccExchangeRequests[_txId].appId];
        require(_exchangeConnector != address(0), "CCExchangeRouter: app id doesn't exist");

        // Gives allowance to exchange connector to transfer from cc exchange router
        ITeleBTC(teleBTC).approve(
            _exchangeConnector,
            remainedInputAmount
        );
        
        ccExchangeRequest memory theCCExchangeReq = ccExchangeRequests[_txId];

        if (IExchangeConnector(_exchangeConnector).isPathValid(theCCExchangeReq.path)) {
            // Exchanges minted teleBTC for output token
            (result, amounts) = IExchangeConnector(_exchangeConnector).swap(
                remainedInputAmount,
                theCCExchangeReq.outputAmount,
                theCCExchangeReq.path,
                theCCExchangeReq.recipientAddress,
                theCCExchangeReq.deadline,
                theCCExchangeReq.isFixedToken
            );
        } else {
            // Exchanges minted teleBTC for output token via wrappedNativeToken
            // note: path is [teleBTC, wrappedNativeToken, outputToken]
            address[] memory _path = new address[](3);
            _path[0] = theCCExchangeReq.path[0];
            _path[1] = IExchangeConnector(_exchangeConnector).wrappedNativeToken();
            _path[2] = theCCExchangeReq.path[1];

            (result, amounts) = IExchangeConnector(_exchangeConnector).swap(
                remainedInputAmount,
                theCCExchangeReq.outputAmount,
                _path,
                theCCExchangeReq.recipientAddress,
                theCCExchangeReq.deadline,
                theCCExchangeReq.isFixedToken
            );
        }

        if (result) {
            // Emits CCExchange if exchange was successful
            emit CCExchange(
                _lockerLockingScript,
                0,
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                theCCExchangeReq.recipientAddress,
                [theCCExchangeReq.path[0], theCCExchangeReq.path[1]], // [input token, output token]
                [amounts[0], amounts[amounts.length-1]], // [input amount, output amount]
                theCCExchangeReq.speed,
                _msgSender(), // Teleporter address
                theCCExchangeReq.fee,
                _txId,
                theCCExchangeReq.appId
            );

            // Transfers rest of teleBTC to recipientAddress (if input amount is not fixed)
            if (theCCExchangeReq.isFixedToken == false) {
                ITeleBTC(teleBTC).transfer(
                    theCCExchangeReq.recipientAddress,
                    remainedInputAmount - amounts[0]
                );
            }
        } else {
            // Handles situation when exchange was not successful

            // Revokes allowance
            ITeleBTC(teleBTC).approve(
                _exchangeConnector,
                0
            );

            // Sends teleBTC to recipient if exchange wasn't successful
            ITeleBTC(teleBTC).transfer(
                theCCExchangeReq.recipientAddress,
                remainedInputAmount
            );

            emit FailedCCExchange(
                _lockerLockingScript,
                0,
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                theCCExchangeReq.recipientAddress,
                [theCCExchangeReq.path[0], theCCExchangeReq.path[1]], // [input token, output token]
                [remainedInputAmount, 0],// [input amount, output amount]
                theCCExchangeReq.speed,
                _msgSender(), // Teleporter address
                theCCExchangeReq.fee,
                _txId,
                theCCExchangeReq.appId
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
            _lockerLockingScript,
            0,
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
}
