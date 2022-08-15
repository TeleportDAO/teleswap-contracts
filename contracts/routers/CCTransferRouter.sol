// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/TxHelper.sol";
import "./interfaces/ICCTransferRouter.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "./interfaces/IInstantRouter.sol";
import "../lockers/interfaces/ILockers.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract CCTransferRouter is ICCTransferRouter, Ownable, ReentrancyGuard {

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CCTransferRouter: address is zero");
        _;
    }

    // Public variables
    uint public override startingBlockNumber;
    uint public override chainId;
    uint public override appId;
    uint public override protocolPercentageFee; // A number between 0 to 10000
    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override instantRouter;
    address public override treasury;
    mapping(bytes32 => ccTransferRequest) public ccTransferRequests; // TxId to CCTransferRequest structure

    /// @notice                             Gives default params to initiate cc transfer router
    /// @param _startingBlockNumber         Requests that are included in a block older than _startingBlockNumber cannot be executed
    /// @param _protocolPercentageFee       Percentage amount of protocol fee (min: %0.01)
    /// @param _chainId                     Id of the underlying chain
    /// @param _appId                       Id of ccTransfer dApp
    /// @param _relay                       The Relay address to validate data from source chain
    /// @param _lockers                     Lockers' contract address
    /// @param _teleBTC                     TeleportDAO BTC ERC20 token address
    /// @param _treasury                    Address of treasury that collects protocol fees
    constructor(
        uint _startingBlockNumber,
        uint _protocolPercentageFee,
        uint _chainId,
        uint _appId,
        address _relay,
        address _lockers,
        address _teleBTC,
        address _treasury
    ) {
        startingBlockNumber = _startingBlockNumber;
        protocolPercentageFee = _protocolPercentageFee;
        require(10000 >= _protocolPercentageFee, "CCTransferRouter: invalid percentage fee");
        chainId = _chainId;
        appId = _appId;
        relay = _relay;
        lockers = _lockers;
        teleBTC = _teleBTC;
        treasury = _treasury;
    }

    /// @notice                             Setter for protocol percentage fee
    /// @dev                                Only owner can call this
    /// @param _protocolPercentageFee       Percentage amount of protocol fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        require(
            10000 >= _protocolPercentageFee,
            "CCTransferRouter: protocol fee is out of range"
        );
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice                             Setter for relay
    /// @param _relay                       Address of the relay contract
    function setRelay(address _relay) external override nonZeroAddress(_relay) onlyOwner {
        relay = _relay;
    }

    /// @notice                             Setter for relay
    /// @param _lockers                     Address of the lockers contract
    function setLockers(address _lockers) external override nonZeroAddress(_lockers) onlyOwner {
        lockers = _lockers;
    }

    /// @notice                             Setter for instant router
    /// @param _instantRouter               Address of the instant router contract
    function setInstantRouter(address _instantRouter) external override nonZeroAddress(_instantRouter) onlyOwner {
        instantRouter = _instantRouter;
    }

    /// @notice                             Setter for teleBTC
    /// @param _teleBTC                     TeleportDAO BTC ERC20 token address
    function setTeleBTC(address _teleBTC) external override nonZeroAddress(_teleBTC) onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                             Setter for treasury
    /// @param _treasury                    Treasury address
    function setTreasury(address _treasury) external override nonZeroAddress(_treasury) onlyOwner {
        treasury = _treasury;
    }

    /// @notice                             Check if the request has been executed before
    /// @dev                                This is to avoid re-submitting a used request
    /// @param _txId                        The txId of request on the source chain
    /// @return                             True if the request has been executed
    function isRequestUsed(bytes32 _txId) external view override returns (bool) {
        return ccTransferRequests[_txId].isUsed ? true : false;
    }

    /// @notice                             Executes the cross chain transfer request
    /// @dev                                Validates the transfer request, then,
    ///                                     if speed is 1, the request is instant
    ///                                     which pays back the loan,
    ///                                     if the speed is 0, it is a normal transfer
    /// @param _version                     Version of the Bitcoin transaction
    /// @param _vin                         Transaction inputs
    /// @param _vout                        Transaction outputs
    /// @param _locktime                    Bitcoin transaction locktime
    /// @param _blockNumber                 The block number of the request tx
    /// @param _intermediateNodes           Merkle proof for tx
    /// @param _index                       Index of tx in the block
    /// @param _lockerScriptHash            Script hash of locker that user has sent BTC to it
    /// @return                             True if the transfer is successful
    function ccTransfer(
        // Bitcoin tx
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        // Bitcoin block number
        uint256 _blockNumber,
        // Merkle proof
        bytes calldata _intermediateNodes,
        uint _index,
        address _lockerScriptHash
    ) external payable nonReentrant nonZeroAddress(_lockerScriptHash) override returns (bool) {
        require(_blockNumber >= startingBlockNumber, "CCTransferRouter: request is too old");

        // Finds txId on the source chain
        bytes32 txId = TxHelper.calculateTxId(_version, _vin, _vout, _locktime);

        require(
            !ccTransferRequests[txId].isUsed,
            "CCTransferRouter: request has been used before"
        );

        // Extracts information from the request
        _saveCCTransferRequest(_lockerScriptHash, _vout, txId);

        // Checks if tx has been confirmed on source chain
        require(
            _isConfirmed(
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "CCTransferRouter: transaction has not been finalized yet"
        );

        // Normal cc transfer request
        if (ccTransferRequests[txId].speed == 0) {
            uint receivedAmount = _sendTeleBTC(_lockerScriptHash, txId);
            emit CCTransfer(
                ccTransferRequests[txId].recipientAddress,
                ccTransferRequests[txId].inputAmount,
                receivedAmount,
                ccTransferRequests[txId].speed,
                msg.sender,
                ccTransferRequests[txId].fee
            );
            return true;
        } else {
            // Pays back instant loan (ccTransferRequests[txId].speed == 1)
            uint receivedAmount = _payBackInstantLoan(_lockerScriptHash, txId);
            emit CCTransfer(
                ccTransferRequests[txId].recipientAddress,
                ccTransferRequests[txId].inputAmount,
                receivedAmount,
                ccTransferRequests[txId].speed,
                msg.sender,
                ccTransferRequests[txId].fee
            );
            return true;
        }
    }

    /// @notice                             Sends minted teleBTC to the user
    /// @param _lockerScriptHash            Locker's script hash
    /// @param _txId                        The transaction ID of the request
    /// @return _remainedAmount             Amount of teleBTC that user receives after reducing fees
    function _sendTeleBTC(address _lockerScriptHash, bytes32 _txId) private returns (uint _remainedAmount) {
        // Gets remained amount after reducing fees
        _remainedAmount = _mintAndReduceFees(_lockerScriptHash, _txId);

        // Transfers rest of tokens to recipient
        ITeleBTC(teleBTC).transfer(
            ccTransferRequests[_txId].recipientAddress,
            _remainedAmount
        );
    }

    /// @notice                             Executes the paying back instant loan request
    /// @param _lockerScriptHash            Locker's script hash
    /// @param _txId                        The transaction ID of the request
    /// @return _remainedAmount             Amount of teleBTC that user receives after reducing fees
    function _payBackInstantLoan(
        address _lockerScriptHash, 
        bytes32 _txId
    ) private returns (uint _remainedAmount) {

        // Gets remained amount after reducing fees
        _remainedAmount = _mintAndReduceFees(_lockerScriptHash, _txId);

        // Gives allowance to instant router to transfer remained teleBTC
        ITeleBTC(teleBTC).approve(
            instantRouter,
            _remainedAmount
        );

        // Pays back instant loan
        IInstantRouter(instantRouter).payBackLoan(
            ccTransferRequests[_txId].recipientAddress,
            _remainedAmount
        );
    }

    /// @notice                             Parses and saves the request tx
    /// @dev                                Checks that user has sent BTC to a valid locker
    /// @param _lockerScriptHash            Locker's script hash
    /// @param _vout                        The outputs of the tx
    /// @param _txId                        The txID of the request
    function _saveCCTransferRequest(
        address _lockerScriptHash,
        bytes memory _vout,
        bytes32 _txId
    ) private {

        require(
            ILockers(lockers).isLocker(_lockerScriptHash),
            "CCTransferRouter: no locker with the given script hash exists"
        );

        // Extracts value and opreturn data from request
        ccTransferRequest memory request; // Defines it to save gas
        bytes memory arbitraryData;
        (request.inputAmount, arbitraryData) = TxHelper.parseValueAndData(_vout, _lockerScriptHash);

        // Checks that input amount is not zero
        require(request.inputAmount > 0, "CCTransferRouter: input amount is zero");

        // Checks chain id and app id
        require(TxHelper.parseChainId(arbitraryData) == chainId, "CCTransferRouter: chain id is not correct");
        require(TxHelper.parseAppId(arbitraryData) == appId, "CCTransferRouter: app id is not correct");

        // Calculates fee
        uint percentageFee = TxHelper.parsePercentageFee(arbitraryData);
        require(percentageFee < 10000, "CCTransferRouter: percentage fee is out of range");
        request.fee = percentageFee*request.inputAmount/10000;

        // Parses recipient address and request speed
        request.recipientAddress = TxHelper.parseRecipientAddress(arbitraryData);
        request.speed = TxHelper.parseSpeed(arbitraryData);
        require(request.speed == 0 || request.speed == 1, "CCTransferRouter: speed is out of range");

        // Marks the request as used
        request.isUsed = true;

        // Saves the request data
        ccTransferRequests[_txId] = request;
    }

    /// @notice                             Checks if tx has been finalized on source chain
    /// @dev                                Pays relay fee using included ETH in the transaction
    /// @param _txId                        The request tx
    /// @param _blockNumber                 The block number of the tx
    /// @param _intermediateNodes           Merkle proof for tx
    /// @param _index                       Index of tx in the block
    /// @return                             True if the tx is finalized on the source chain
    function _isConfirmed(
        bytes32 _txId,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) private returns (bool) {
        // Calculates fee amount
        uint feeAmount = IBitcoinRelay(relay).getBlockHeaderFee(_blockNumber, 0); // Index 0 is for finalized blocks
        require(msg.value >= feeAmount, "CCTransferRouter: paid fee is not sufficient");

        // Calls relay contract (transfers all msg.value to it)
        bytes memory data = Address.functionCallWithValue(
            relay,
            abi.encodeWithSignature(
                "checkTxProof(bytes32,uint256,bytes,uint256)",
                _txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            feeAmount
        );
        
        // Sends extra ETH back to msg.sender
        Address.sendValue(payable(msg.sender), msg.value - feeAmount);

        return abi.decode(data, (bool));
    }

    /// @notice                       Mints teleBTC by calling lockers contract
    /// @param _lockerScriptHash      Locker's script hash
    /// @param _txId                  The transaction ID of the request
    /// @return _remainedAmount       Amount of teleBTC that user receives after reducing all fees (protocol, locker, teleporter)
    function _mintAndReduceFees(
        address _lockerScriptHash,
        bytes32 _txId
    ) private returns (uint _remainedAmount) {

        // Mints teleBTC for cc transfer router
        // Lockers contract gets locker's fee
        uint mintedAmount = ILockers(lockers).mint(
            _lockerScriptHash,
            address(this),
            ccTransferRequests[_txId].inputAmount
        );

        // Calculates fees
        uint protocolFee = ccTransferRequests[_txId].inputAmount*protocolPercentageFee/10000;
        uint teleporterFee = ccTransferRequests[_txId].fee;

        // Pays Teleporter fee
        if (teleporterFee > 0) {
            ITeleBTC(teleBTC).transfer(msg.sender, teleporterFee);
        }

        // Pays protocol fee
        if (protocolFee > 0) {
            ITeleBTC(teleBTC).transfer(treasury, protocolFee);
        }

        _remainedAmount = mintedAmount - protocolFee - teleporterFee;
    }
}