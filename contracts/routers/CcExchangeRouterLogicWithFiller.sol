// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./CcExchangeRouterLogic.sol";
import "hardhat/console.sol";
import "./interfaces/ICcTransferRouter.sol";
import "../libraries/RequestHelper.sol";
import "../lockers/interfaces/ILockers.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "@teleportdao/btc-evm-bridge/contracts/libraries/BitcoinHelper.sol";
import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CcExchangeRouterLogicWithFiller is CcExchangeRouterLogic {

	event NewFillerWithdrawInterval(
        uint oldFillerWithdrawInterval, 
        uint newFillerWithdrawInterval
    );

    event NewFill(
        address filler,
        bytes32 txId, 
        address token,
        uint amount
    );

    event TxIdFillStart(
        bytes32 txId,
        uint time
    );

    // TODO add matic
    // TODO just one Filler data

    struct FillerData {
        uint index;
        address token;
        uint amount;
    }

    struct TXFillData {
        uint startingTime;
        address choosedToken;
        uint affectingIndex;
        uint remainingAmountOfLastFill;
        bool remainingAmountOfLastFillIsWithdrawn;
    }

    struct PrefixFillSum {
        uint[] prefixSum;
        uint currentIndex;
    }

    mapping (bytes32 => mapping (address => FillerData)) public fillersData;
    mapping (bytes32 => mapping (address => PrefixFillSum)) public prefixFillSums;
    mapping (bytes32 => TXFillData) public txsFillData;
    mapping (bytes32 => uint) public remainedInputAmounts;

    // get sure to set after deploying the contract
    uint public fillerWithdrawInterval;

    function setFillerWithdrawInterval(uint _fillerWithdrawInterval) external onlyOwner {
        _setFillerWithdrawInterval(_fillerWithdrawInterval);
    }

    function _setFillerWithdrawInterval(uint _fillerWithdrawInterval) private {
        emit NewFillerWithdrawInterval(fillerWithdrawInterval, _fillerWithdrawInterval);
        fillerWithdrawInterval = _fillerWithdrawInterval;
    }

    function fillTx(
        bytes32 txId,
        address token,
        uint amount
    ) external nonReentrant returns (bool) {
        PrefixFillSum storage _prefixFillSum = prefixFillSums[txId][token];
        require(
            ERC20(token).transferFrom(_msgSender(), address(this), amount),
            "CCExchangeRouter: Unable to transfer token to contract"
        ); 

        if (_prefixFillSum.currentIndex == 0) {
            _prefixFillSum.prefixSum.push(0);
            _prefixFillSum.currentIndex = 1;
        }

        uint index = _prefixFillSum.currentIndex;

        fillersData[txId][_msgSender()] = FillerData(_prefixFillSum.currentIndex, token, amount);

        _prefixFillSum.prefixSum.push(_prefixFillSum.prefixSum[index - 1] + amount);
        _prefixFillSum.currentIndex += 1;

        prefixFillSums[txId][token] = _prefixFillSum;

        if (txsFillData[txId].startingTime == 0) {  
            txsFillData[txId].startingTime = block.timestamp;

            emit TxIdFillStart (
                txId, 
                block.timestamp
            );
        }

        emit NewFill (
            _msgSender(),
            txId, 
            token,
            amount
        );
    }

    function returnUnusedFills (
        bytes32 txId
    ) external nonReentrant returns (bool) {
        TXFillData memory txFillData = txsFillData[txId];
        require (
            ccExchangeRequests[txId].inputAmount > 0 || txFillData.startingTime + fillerWithdrawInterval < block.timestamp, 
            "CCExchangeRouter: request is not proccessed yet or time interval for withdraw is not passed"
        );

        FillerData memory fillerData = fillersData[txId][_msgSender()];
        
        if (txFillData.choosedToken != fillerData.token || txFillData.affectingIndex < fillerData.index) {
            require(
                ERC20(fillerData.token).transfer(_msgSender(), fillerData.amount), 
                "CCExchangeRouter: can't transfer token"
            );
            fillersData[txId][_msgSender()].amount = 0;
            return true;
        }

        if (txFillData.affectingIndex == fillerData.index && txsFillData[txId].remainingAmountOfLastFillIsWithdrawn == false) {
            require(
                ERC20(fillerData.token).transfer(_msgSender(), txFillData.remainingAmountOfLastFill), 
                "CCExchangeRouter: can't transfer token"
            );
            txsFillData[txId].remainingAmountOfLastFillIsWithdrawn = true;
            return true;
        }
        return false;
    }

    function receiveFillBenefit (
       bytes32 txId
    ) external nonReentrant returns (bool) {
        TXFillData memory txFillData = txsFillData[txId];
        FillerData memory fillerData = fillersData[txId][_msgSender()];
        if (txFillData.affectingIndex > fillerData.index && fillersData[txId][_msgSender()].amount > 0) {
            uint amount = fillerData.amount * remainedInputAmounts[txId] / ccExchangeRequests[txId].outputAmount ;
            require(
                ITeleBTC(teleBTC).transfer(_msgSender(), amount), 
                "CCExchangeRouter: can't transfer TeleBTC"
            );
            fillersData[txId][_msgSender()].amount = 0;
            return true;
        }

        if (txFillData.affectingIndex == fillerData.index && fillersData[txId][_msgSender()].amount > 0) {
            uint amount = (fillerData.amount - txFillData.remainingAmountOfLastFill)  * remainedInputAmounts[txId] / ccExchangeRequests[txId].outputAmount;
            require(
                ITeleBTC(teleBTC).transfer(_msgSender(), amount),
                "CCExchangeRouter: can't transfer TeleBTC"
            );
            fillersData[txId][_msgSender()].amount = 0;
            return true;
        }
        return false;
    }

    /// @notice                     Executes a cross-chain exchange request after checking its merkle inclusion proof
    /// @dev                        Mints teleBTC for user if exchanging is not successful
    /// @param _version             Version of the transaction containing the user request
    /// @param _vin                 Inputs of the transaction containing the user request
    /// @param _vout                Outputs of the transaction containing the user request
    /// @param _locktime            Lock time of the transaction containing the user request
    /// @param _blockNumber         Height of the block containing the user request
    /// @param _intermediateNodes   Merkle inclusion proof for transaction containing the user request
    /// @param _index               Index of transaction containing the user request in the block
    /// @param _lockerLockingScript    Script hash of locker that user has sent BTC to it
    /// @return
    function ccExchange(
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes calldata _intermediateNodes,
        uint _index,
        bytes calldata _lockerLockingScript
    ) external payable nonReentrant override returns (bool) {
        //TODO?
        // require(_msgSender() == instantRouter, "CCExchangeRouter: invalid sender");
        require(_blockNumber >= startingBlockNumber, "CCExchangeRouter: request is too old");

        // Calculates transaction id
        bytes32 txId = BitcoinHelper.calculateTxId(_version, _vin, _vout, _locktime);

        // Checks that the request has not been processed before
        require(
            !ccExchangeRequests[txId].isUsed,
            "CCExchangeRouter: the request has been used before"
        );

        require(_locktime == bytes4(0), "CCExchangeRouter: lock time is non-zero");

        // Extracts information from the request
        _saveCCExchangeRequest(_lockerLockingScript, _vout, txId);

        console.logBytes32(txId);
        // Check if transaction has been confirmed on source chain
        require(
            _isConfirmed(
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "CCExchangeRouter: transaction has not been finalized yet"
        );
        
        ccExchangeRequest memory request = ccExchangeRequests[txId];
        if (
            request.speed == 1 && 
            _canFill(txId, request.path[1], request.outputAmount) && 
            block.timestamp <= txsFillData[txId].startingTime + fillerWithdrawInterval
        ) {
            // Fill cc exchange request
            _fillCCExchange(_lockerLockingScript, txId, request);
        } else {
            // Normal cc exchange request
            _normalCCExchange(_lockerLockingScript, txId);
        }

        return true;
    }

    function _canFill(bytes32 _txId, address token, uint256 amount) private returns(bool){
        PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][token];
        return _prefixFillSum.prefixSum[_prefixFillSum.currentIndex - 1] >= amount;
    }

    function _findAffectingIndexOfFill(PrefixFillSum memory _prefixFillSum, uint256 amount) private returns(uint)  {
        uint[] memory sumArray = _prefixFillSum.prefixSum;
        int l = -1;
        int r = int(_prefixFillSum.currentIndex);
        while (r - l > 1) {
            int mid = (l + r) >> 1;
            if (sumArray[uint(mid)] >= amount)
                r = mid;
            else
                l = mid;
        }
        return uint(r);
    }


    /// @notice                          Executes a exchange request with filler
    /// @param _lockerLockingScript      Locker's locking script    
    /// @param _txId                     Id of the transaction containing the user request
    function _fillCCExchange(bytes memory _lockerLockingScript, bytes32 _txId, ccExchangeRequest memory request) private {
        // Gets remained amount after reducing fees
        //TODO add to doc
        uint remainedInputAmount = _mintAndReduceFees(_lockerLockingScript, _txId);

        TXFillData memory _txFillData;
        _txFillData.choosedToken = request.path[1];

        PrefixFillSum memory _prefixFillSum = prefixFillSums[_txId][request.path[1]];
        _txFillData.affectingIndex = _findAffectingIndexOfFill(_prefixFillSum, request.outputAmount);
        _txFillData.remainingAmountOfLastFill = _prefixFillSum.prefixSum[_txFillData.affectingIndex] - request.outputAmount;

        bool result = ERC20(request.path[1]).transfer(request.recipientAddress, request.outputAmount);

        if (result) {
            txsFillData[_txId] = _txFillData;
            remainedInputAmounts[_txId] = remainedInputAmount;

            emit CCExchange(
                _lockerLockingScript,
                0,
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                request.recipientAddress,
                [request.path[0], request.path[1]], // input token // output token
                [remainedInputAmount, request.outputAmount], // input amount // output amount
                request.speed,
                _msgSender(), // Teleporter address
                request.fee,
                _txId,
                request.appId
            );
 
        } else {
            _txFillData.affectingIndex = 0;
            _txFillData.remainingAmountOfLastFill = 0;
            txsFillData[_txId] = _txFillData;

            // Sends teleBTC to recipient if exchange wasn't successful
            ITeleBTC(teleBTC).transfer(
                request.recipientAddress,
                remainedInputAmount
            );

            emit FailedCCExchange(
                _lockerLockingScript,
                0,
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                request.recipientAddress,
                [request.path[0], request.path[1]], // input token // output token
                [remainedInputAmount, 0],// input amount //  output amount
                request.speed,
                _msgSender(), // Teleporter address
                request.fee,
                _txId,
                request.appId
            );
        }
    }
}