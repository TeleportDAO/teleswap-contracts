pragma solidity 0.8.0;

import "../libraries/SafeMath.sol";
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
    using SafeMath for uint256;

    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override instantRouter;
    // TxId to CCTransferRequest structure
    mapping(bytes32 => ccTransferRequest) public ccTransferRequests;


    /// @notice                             Gives default params to initiate cc transfer router
    /// @dev
    /// @param _relay                       The Relay address to get data from source chain
    /// @param _lockers                     Lockers' contract address
    /// @param _teleBTC                     TeleportDAO BTC ERC20 token address
    constructor(address _relay, address _lockers, address _teleBTC) public {
        relay = _relay;
        lockers = _lockers;
        teleBTC = _teleBTC;
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
        console.log("ccTransfer...");
        bytes32 txId = NewTxHelper.calculateTxId(_version, _vin, _vout, _locktime);
        console.log("tx id calculated successfully");
        console.logBytes32(txId);
        require(
            !ccTransferRequests[txId].isUsed,
            "CCTransferRouter: CC transfer request has been used before"
        );
        // ccTransferRequests[txId].isUsed = true;
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

        console.log("ccTransfer _mintAndSend");
        console.log(ccTransferRequests[txId].speed);

        // Normal cc transfer request
        if (ccTransferRequests[txId].speed == 0) {
            require(_mintAndSend(lockerBitcoinDecodedAddress, txId), "CCTransferRouter: normal cc transfer was not successful");
            emit CCTransfer(
                ccTransferRequests[txId].recipientAddress,
                ccTransferRequests[txId].inputAmount,
                ccTransferRequests[txId].speed,
            // FIXME: set the correct fee in the event
                0
            );
            console.log("...ccTransfer");
            return true;
        }
        // Pay back instant loan
        if (ccTransferRequests[txId].speed == 1) {
            require(_payBackInstantLoan(lockerBitcoinDecodedAddress, txId), "CCTransferRouter: pay back was not successful");
            console.log("...ccTransfer");
            return true;
        }
    }

    /// @notice                             Mints the equivalent amount of locked tokens
    ///                                     shown in the request tx, and sends them to the user
    /// @dev                                The check amount for Teleporter fee can be adjusted
    /// @param _txId                        The transaction ID of the request
    /// @return                             True if minting and sending tokens passes
    // TODO: maybe its better to add lokerBitcoinDecodedAddress to the transfer request struct
    function _mintAndSend(address _lokerBitcoinDecodedAddress, bytes32 _txId) internal returns (bool) {
        // Pay fees
        if (ccTransferRequests[_txId].fee > 0) {
            // Mint wrapped tokens for Teleporter
            ILockers(lockers).mint(
                _lokerBitcoinDecodedAddress,
                msg.sender,
                ccTransferRequests[_txId].fee
            );
        }

        console.log("_mintAndSend ....");
        console.log("fee");
        console.log(ccTransferRequests[_txId].fee);
        console.log("recipientAddress");
        console.log(ccTransferRequests[_txId].recipientAddress);
        console.log("inputAmount");
        console.log(ccTransferRequests[_txId].inputAmount);

        // Mint wrapped tokens for user
        ILockers(lockers).mint(
            _lokerBitcoinDecodedAddress,
            ccTransferRequests[_txId].recipientAddress,
            ccTransferRequests[_txId].inputAmount.sub(ccTransferRequests[_txId].fee)
        );
        return true;
    }

    /// @notice                             Executes the paying back instant loan request
    /// @dev                                The check amount for Teleporter fee can be adjusted
    /// @param _txId                        The transaction ID of the request
    /// @return                             True if paying back passes
    function _payBackInstantLoan(address _lokerBitcoinDecodedAddress, bytes32 _txId) internal returns (bool) {
        // Pay fees
        if (ccTransferRequests[_txId].fee > 0) {
            ILockers(lockers).mint(
                _lokerBitcoinDecodedAddress,
                msg.sender,
                ccTransferRequests[_txId].fee
            );
        }
        uint remainedAmount = ccTransferRequests[_txId].inputAmount.sub(ccTransferRequests[_txId].fee);
        // Mint wrapped token for cc transfer router
        ILockers(lockers).mint(
            _lokerBitcoinDecodedAddress,
            address(this),
            remainedAmount
        );
        // Give allowance to instant router to transfer minted wrapped tokens
        ITeleBTC(teleBTC).approve(
            instantRouter,
            remainedAmount
        );
        // FIXME: Update when the instant router is updated
        // User wants to pay back borrowed tokens
        // IInstantRouter(instantRouter).payBackLoan(
        //     remainedAmount,
        //     ccTransferRequests[_txId].recipientAddress
        // );
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
        console.log("_saveCCTransferRequest...");
        // TODO: add parse chainId to check whether this is the correct target chain
        // indicated in the tx.
        bytes memory arbitraryData;
        ccTransferRequest memory request; //TODO: no need for this, set directly
        address desiredRecipient;
        uint percentageFee;
        // Get the multisig address where funds for requests need to go
        // TODO: check which lockers are available and check whether the money has been
        // transferred to an active locker
        // FIXME: how to get the redeemScriptHash from new lockers contract
        // desiredRecipient = ILockers(lockers).redeemScriptHash();

        require(
            ILockers(lockers).isLocker(_lockerBitcoinDecodedAddress),
            "CCTransferRouter: no locker with this bitcoin decoded addresss"
        );

        // Parse request tx data
        (request.inputAmount, arbitraryData) = NewTxHelper.parseAmountForP2PK(_vout, _lockerBitcoinDecodedAddress);
        console.log("request.inputAmount");
        console.log(request.inputAmount);
        console.log("arbitrary data parsed correctly");

        // Make sure request is for transfer (and not exchange)
        require(NewTxHelper.parseExchangeToken(arbitraryData) == address(0), "CCTransferRouter: request is exchange request");
        // Parse request tx data

        address asfdsfdsf = NewTxHelper.parseRecipientAddress(arbitraryData);
        console.log("parsed RecipientAddress");
        console.log(asfdsfdsf);

        console.log("before parsePercentageFee");
        percentageFee = NewTxHelper.parsePercentageFee(arbitraryData);

        console.log("percentageFee...");
        console.log(percentageFee);

        require(percentageFee >= 0 && percentageFee < 10000, "CCTransferRouter: percentage fee is not correct");
        request.fee = percentageFee.mul(request.inputAmount).div(10000);
        console.log("request.fee");
        console.log(request.fee);

        request.recipientAddress = NewTxHelper.parseRecipientAddress(arbitraryData);
        request.speed = NewTxHelper.parseSpeed(arbitraryData);
        // request.deadline = NewTxHelper.parseDeadline(arbitraryData);
        request.isUsed = true;
        // Save the request data
        ccTransferRequests[_txId] = request;

        console.log("..._saveCCTransferRequest");
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
}