pragma solidity 0.8.0;

import "../libraries/NewTxHelper.sol";
import "./interfaces/ICCTransferRouter.sol";
import "../erc20/interfaces/IWrappedToken.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "./interfaces/IInstantRouter.sol";
import "../lockers/interfaces/ILockers.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract CCTransferRouter is ICCTransferRouter, Ownable, ReentrancyGuard {
    // Public variables
    uint public override chainId;
    uint public override appId;
    uint public override protocolPercentageFee; // A number between 0 to 10000
    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override instantRouter;
    address public override treasury;
    // TxId to CCTransferRequest structure
    mapping(bytes32 => ccTransferRequest) public ccTransferRequests;

    /// @notice                             Gives default params to initiate cc transfer router
    /// @param _protocolPercentageFee       Percentage amount of protocol fee (min: %0.01) 
    /// @param _chainId                     Id of the underlying chain
    /// @param _appId                       Id of ccTransfer dApp
    /// @param _relay                       The Relay address to get data from source chain
    /// @param _lockers                     Lockers' contract address
    /// @param _teleBTC                     TeleportDAO BTC ERC20 token address
    /// @param _treasury                    Address of treasury that collects fees
    constructor(
        uint _protocolPercentageFee,
        uint _chainId,
        uint _appId,
        address _relay, 
        address _lockers, 
        address _teleBTC,
        address _treasury
    ) public {
        protocolPercentageFee = _protocolPercentageFee;
        chainId = _chainId;
        appId = _appId;
        relay = _relay;
        lockers = _lockers;
        teleBTC = _teleBTC;
        treasury = _treasury;
    }

    /// @notice                             Setter for protocol percentage fee
    /// @param _protocolPercentageFee       Percentage amount of protocol fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        require(
            _protocolPercentageFee >= 0 && 10000 >= _protocolPercentageFee, 
            "CCTransferRouter: fee is out of range"
        );
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice                             Setter for relay
    /// @param _relay                       Address of the relay contract
    function setRelay(address _relay) external override onlyOwner {
        relay = _relay;
    }

    /// @notice                             Setter for relay
    /// @param _lockers                       Address of the lockers
    function setLockers(address _lockers) external override onlyOwner {
        lockers = _lockers;
    }

    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
    }

    /// @notice                             Setter for teleBTC
    /// @param _teleBTC                     TeleportDAO BTC ERC20 token address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                             Setter for treasury
    /// @param _treasury                    Treasury address
    function setTreasury(address _treasury) external override onlyOwner {
        treasury = _treasury;
    }

    /// @notice                             Check if the wrap request is done before
    /// @dev                                This is to avoid re-submitting a used request
    /// @param _txId                        The source chain transaction ID requested to be wrapped
    /// @return                             True if the wrap request is previously done
    function isRequestUsed(bytes32 _txId) external view override returns (bool) {
        return ccTransferRequests[_txId].isUsed ? true : false;
    }

    /// @notice                             Executes the cross chain transfer request
    /// @dev                                Validates the transfer request, then,
    ///                                     if speed is 1, the request is instant
    ///                                     and this is paying back the loan,
    ///                                     if the speed is 0, it is a normal transfer
    /// @param _version                     Version of the Bitcoin transaction
    /// @param _vin                         Transaction inputs
    /// @param _vout                        Transaction outputs
    /// @param _locktime                    Bitcoin transaction locktime
    /// @param _blockNumber                 The block number of the request tx
    /// @param _intermediateNodes           Part of the Merkle proof for the request tx
    /// @param _index                       Part of the Merkle proof for the request tx
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
        address lockerBitcoinDecodedAddress
    ) external nonReentrant override returns (bool) {
        bytes32 txId = NewTxHelper.calculateTxId(_version, _vin, _vout, _locktime);

        require(
            !ccTransferRequests[txId].isUsed,
            "CCTransferRouter: CC transfer request has been used before"
        );
        
        // Extracts information from the request
        _saveCCTransferRequest(lockerBitcoinDecodedAddress, _vout, txId);

        // Check if tx has been confirmed on source chain
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
            require(
                _mintAndSend(lockerBitcoinDecodedAddress, txId), 
                "CCTransferRouter: normal cc transfer was not successful"
            );
            emit CCTransfer(
                ccTransferRequests[txId].recipientAddress,
                ccTransferRequests[txId].inputAmount,
                ccTransferRequests[txId].speed,
            // FIXME: set the correct fee in the event
                0
            );
            return true;
        }

        // Pays back instant loan
        if (ccTransferRequests[txId].speed == 1) {
            require(
                _payBackInstantLoan(lockerBitcoinDecodedAddress, txId), 
                "CCTransferRouter: pay back was not successful"
            );
            return true;
        }
    }

    /// @notice                             Mints the equivalent amount of locked tokens
    ///                                     shown in the request tx, and sends them to the user
    /// @dev                                The check amount for Teleporter fee can be adjusted
    /// @param _txId                        The transaction ID of the request
    /// @return                             True if minting and sending tokens passes
    // TODO: maybe its better to add lokerBitcoinDecodedAddress to the transfer request struct
    function _mintAndSend(address _lockerBitcoinDecodedAddress, bytes32 _txId) internal returns (bool) {
        // Gets remained amount after reducing fees
        uint remainedAmount = _mintAndReduceFees(_lockerBitcoinDecodedAddress, _txId);
        
        // Transfers rest of tokens to recipient
        ITeleBTC(teleBTC).transfer(
            ccTransferRequests[_txId].recipientAddress,
            remainedAmount
        );

        return true;
    }

    /// @notice                             Executes the paying back instant loan request
    /// @dev                                The check amount for Teleporter fee can be adjusted
    /// @param _txId                        The transaction ID of the request
    /// @return                             True if paying back passes
    function _payBackInstantLoan(address _lockerBitcoinDecodedAddress, bytes32 _txId) internal returns (bool) {
        
        // Gets remained amount after reducing fees
        uint remainedAmount = _mintAndReduceFees(_lockerBitcoinDecodedAddress, _txId);

        // Gives allowance to instant router to transfer remained teleBTC
        ITeleBTC(teleBTC).approve(
            instantRouter,
            remainedAmount
        );

        // Pays back instant loan
        IInstantRouter(instantRouter).payBackLoan(
            ccTransferRequests[_txId].recipientAddress,
            remainedAmount
        );

        return true;
    }

    /// @notice                             Parses and saves the request tx
    /// @dev                                Parses data from tx
    /// @param _vout                        The outputs of the request tx
    /// @param _txId                        The tx ID of the request
    function _saveCCTransferRequest(
        address _lockerBitcoinDecodedAddress,
        bytes memory _vout,
        bytes32 _txId
    ) internal {
        bytes memory arbitraryData;
        ccTransferRequest memory request; // Defines it to save gas
        address desiredRecipient;
        uint percentageFee;

        require(
            ILockers(lockers).isLocker(_lockerBitcoinDecodedAddress),
            "CCTransferRouter: no locker with the bitcoin decoded addresss exists"
        );

        // Extracts value and opreturn data from request
        (request.inputAmount, arbitraryData) = NewTxHelper.parseAmountForP2PK(_vout, _lockerBitcoinDecodedAddress);
        
        // Checks that input amount is not zero
        require(request.inputAmount > 0, "CCTransferRouter: input amount is zero");
        
        // Checks chain id and app id
        require(NewTxHelper.parseChainId(arbitraryData) == chainId, "CCTransferRouter: chain id is not correct");
        require(NewTxHelper.parseAppId(arbitraryData) == appId, "CCTransferRouter: app id is not correct");

        // Calculates fee
        percentageFee = NewTxHelper.parsePercentageFee(arbitraryData);
        require(percentageFee >= 0 && percentageFee < 10000, "CCTransferRouter: percentage fee is not correct");
        request.fee = percentageFee*request.inputAmount/10000;

        request.recipientAddress = NewTxHelper.parseRecipientAddress(arbitraryData);
        request.speed = NewTxHelper.parseSpeed(arbitraryData);
        require(request.speed == 0 || request.speed == 1, "CCTransferRouter: speed is not correct");
        
        // Marks the request as used
        request.isUsed = true;

        // Saves the request data
        ccTransferRequests[_txId] = request;
    }

    /// @notice                             Checks if the request tx is included and confirmed on source chain
    /// @dev                                Asks relay if the included data is correct
    /// @param _txId                        The request tx
    /// @param _blockNumber                 The block number of the request tx
    /// @param _intermediateNodes           Part of the Merkle proof for the request tx
    /// @param _index                       Part of the Merkle proof for the request tx
    /// @return                             True if the tx is confirmed on the source chain
    function _isConfirmed(
        bytes32 _txId,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) internal returns (bool) {
        // TODO: uncomment it
        // uint feeAmount;
        // IERC20(feeTokenAddress).transferFrom(msg.sender, address(this), feeAmount);
        return IBitcoinRelay(relay).checkTxProof(
            _txId,
            _blockNumber,
            _intermediateNodes,
            _index
        );
    }

    /// @notice                               Checks if the request tx is included and confirmed on source chain
    /// @param _lockerBitcoinDecodedAddress    The request tx
    /// @param _txId                          The request tx
    /// @return _remainedAmount               True if the tx is confirmed on the source chain
    function _mintAndReduceFees(
        address _lockerBitcoinDecodedAddress, 
        bytes32 _txId
    ) internal returns (uint _remainedAmount) {

        // Mints teleBTC for cc transfer router
        uint mintedAmount = ILockers(lockers).mint(
            _lockerBitcoinDecodedAddress,
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

        _remainedAmount = mintedAmount - protocolFee - teleporterFee;
    }
}