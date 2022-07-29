pragma solidity 0.8.0;

import "../libraries/SafeMath.sol";
// import "../libraries/BitcoinTxParser.sol";
// import "../libraries/TxHelper.sol";
import "../libraries/NewTxHelper.sol";
import "./interfaces/ICCTransferRouter.sol";
// import "./interfaces/ICCExchangeRouter.sol";
import "../erc20/interfaces/IWrappedToken.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
// import "../teleporter/interfaces/IBitcoinTeleporter.sol";
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


    // address public bitcoinRelay;
    // address public bitcoinTeleporter;
    // mapping(bytes32 => wrapRequest) public wrapRequests;
    // address public ccExchangeRouter;
    // address public instantRouter;
    // address public fastRouter;
    // address public override wrappedBitcoin;
    // address public override bitcoinFastPool;
    // address public bitcoinInstantPool;
    // uint public override normalConfirmationParameter;
    // address public override owner;

    // modifier onlyOwner {
    //     require(msg.sender == owner);
    //     _;
    // }

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

    // constructor(
    //     address _bitcoinRelay,
    //     address _bitcoinTeleporter,
    //     uint _normalConfirmationParameter
    // ) public {
    //     bitcoinRelay = _bitcoinRelay;
    //     bitcoinTeleporter = _bitcoinTeleporter;
    //     normalConfirmationParameter = _normalConfirmationParameter;
    //     owner = msg.sender;
    // }

    // function changeOwner(address _owner) external override onlyOwner {
    //     owner = _owner;
    // }

    // function setNormalConfirmationParameter(uint _normalConfirmationParameter) external override onlyOwner {
    //     normalConfirmationParameter = _normalConfirmationParameter;
    // }

    // function setBitcoinRelay(address _bitcoinRelay) external override onlyOwner {
    //     bitcoinRelay = _bitcoinRelay;
    // }

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

    // function setFastRouter(address _fastRouter) external override onlyOwner {
    //     fastRouter = _fastRouter;
    //     bitcoinFastPool = IFastRouter(fastRouter).bitcoinFastPool();
    // }

    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
        // bitcoinInstantPool = IInstantRouter(instantRouter).bitcoinInstantPool();
    }

    // function setCCExchangeRouter(address _ccExchangeRouter) external override onlyOwner {
    //     ccExchangeRouter = _ccExchangeRouter;
    //     // ICCExchangeRouter(ccExchangeRouter).setInstantRouter(instantRouter);
    // }

    // function setWrappedBitcoin(address _wrappedBitcoin) external override onlyOwner returns (bool) {
    //     wrappedBitcoin = _wrappedBitcoin;
    //     return true;
    // }

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
        uint _index
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
        _saveCCTransferRequest(_vout, txId);
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
            require(_mintAndSend(txId), "CCTransferRouter: normal cc transfer was not successful");
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
            require(_payBackInstantLoan(txId), "CCTransferRouter: pay back was not successful");
            console.log("...ccTransfer");
            return true;
        }
    }

    /// @notice                             Mints the equivalent amount of locked tokens
    ///                                     shown in the request tx, and sends them to the user
    /// @dev                                The check amount for Teleporter fee can be adjusted
    /// @param _txId                        The transaction ID of the request
    /// @return                             True if minting and sending tokens passes
    function _mintAndSend(bytes32 _txId) internal returns (bool) {
        // Pay fees
        if (ccTransferRequests[_txId].fee > 0) {
            // Mint wrapped tokens for Teleporter
            ITeleBTC(teleBTC).mint(
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
        ITeleBTC(teleBTC).mint(
            ccTransferRequests[_txId].recipientAddress,
            ccTransferRequests[_txId].inputAmount.sub(ccTransferRequests[_txId].fee)
        );
        return true;
    }

    /// @notice                             Executes the paying back instant loan request
    /// @dev                                The check amount for Teleporter fee can be adjusted
    /// @param _txId                        The transaction ID of the request
    /// @return                             True if paying back passes
    function _payBackInstantLoan(bytes32 _txId) internal returns (bool) {
        // Pay fees
        if (ccTransferRequests[_txId].fee > 0) {
            ITeleBTC(teleBTC).mint(
                msg.sender,
                ccTransferRequests[_txId].fee
            );
        }
        uint remainedAmount = ccTransferRequests[_txId].inputAmount.sub(ccTransferRequests[_txId].fee);
        // Mint wrapped token for cc transfer router
        ITeleBTC(teleBTC).mint(
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
        desiredRecipient = ILockers(lockers).redeemScriptHash();
        // Parse request tx data
        (request.inputAmount, arbitraryData) = NewTxHelper.parseAmountForP2PK(_vout, desiredRecipient);
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


    // TODO: add burn with permit
    // TODO: handle fast transactions that are not executed because the fast limit was reached (they can mint token after finalization)
    // function ccTransfer(
    //     bytes4 version,
    //     bytes memory vin,
    //     bytes calldata vout,
    //     bytes4 locktime,
    //     uint256 blockNumber,
    //     bytes calldata intermediateNodes,
    //     uint index,
    //     bool payWithTDT
    // ) external override returns (bool) {
    //     bytes32 txId = calculateTxId(version, vin, vout, locktime);
    //     txId = revertBytes32(txId);
    //     require(
    //         !wrapRequests[txId].isUsed,
    //         "Request has been used before"
    //     );
    //     saveWrapRequest(vout, blockNumber, intermediateNodes, index, txId);

    //     if (wrapRequests[txId].speed == 0) {
    //         // check that the block has received enough confirmations
    //         require(
    //             isConfirmed(
    //                 txId,
    //                 blockNumber,
    //                 intermediateNodes,
    //                 index,
    //                 payWithTDT,
    //                 normalConfirmationParameter
    //             ),
    //             "Transaction has not finalized"
    //         );
    //         require(normalCCTransfer(txId), "normal cc transfer was not successful");
    //         emit CCTransfer(
    //             wrapRequests[txId].recipientAddress,
    //             wrappedBitcoin,
    //             wrapRequests[txId].bitcoinAmount,
    //             wrapRequests[txId].speed
    //         );
    //         return true;
    //     }

    //     if (wrapRequests[txId].speed == 1) {
    //         // if transaction has been already finalized, there is no need to borrow wrapped token from fast pool
    //         if (isConfirmed(txId, blockNumber, intermediateNodes, index, payWithTDT, normalConfirmationParameter) == true) {
    //             require(normalCCTransfer(txId), "fast cc transfer was not successful");
    //             wrapRequests[txId].isMinted = true; // wrapped token is minted
    //             emit CCTransfer(
    //                 wrapRequests[txId].recipientAddress,
    //                 wrappedBitcoin,
    //                 wrapRequests[txId].bitcoinAmount,
    //                 0 // the token is wrapped normally
    //             );
    //         } else {
    //             // check that the block has received enough confirmations
    //             require(
    //                 isConfirmed(
    //                     txId,
    //                     blockNumber,
    //                     intermediateNodes,
    //                     index,
    //                     payWithTDT,
    //                     getFastNeededConfirmations()
    //                 ),
    //                 "Transaction has not received enough confirmations"
    //             );
    //             require(fastCCTransfer(txId), "fast cc transfer was not successful");
    //             emit CCTransfer(
    //                 wrapRequests[txId].recipientAddress,
    //                 wrappedBitcoin,
    //                 wrapRequests[txId].bitcoinAmount,
    //                 wrapRequests[txId].speed
    //             );
    //         }
    //         return true;
    //     }

    //     if (wrapRequests[txId].speed == 2) { // pay back instant loan
    //         // check that the block has received enough confirmations
    //         require(
    //             isConfirmed(
    //                 txId,
    //                 blockNumber,
    //                 intermediateNodes,
    //                 index,
    //                 payWithTDT,
    //                 normalConfirmationParameter
    //             ),
    //             "Transaction has not finalized"
    //         );
    //         require(instantCCTransfer(txId), "instant cc transfer was not successful");
    //         return true;
    //     }
    // }

    // function normalCCTransfer (bytes32 txId) internal returns(bool) {

    //     if (wrapRequests[txId].isExchange == true) {
    //         // require(msg.sender == ccExchangeRouter, "message sender is not cc exchange router");
    //         if (msg.sender == ccExchangeRouter) {
    //             IWrappedToken(wrappedBitcoin).mint(ccExchangeRouter, wrapRequests[txId].bitcoinAmount);
    //             return true;
    //         }

    //         if (msg.sender != ccExchangeRouter) {
    //             // handle unpredicted cases that exchange request execution was not succesful, so we want to mint wrapped token for user
    //             // wrapped token can only be mint after passing of deadline
    //             require(wrapRequests[txId].deadline < block.number, "deadline has not passed yet");
    //             require(
    //                 wrapRequests[txId].teleporterFee <= wrapRequests[txId].bitcoinAmount,
    //                 "teleporter fee is too much"
    //             );
    //             if (wrapRequests[txId].teleporterFee > 0) {
    //                 IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee);
    //             }
    //             IWrappedToken(wrappedBitcoin).mint(
    //                 wrapRequests[txId].recipientAddress,
    //                 wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
    //             );
    //             return true;
    //         }
    //     }

    //     if (wrapRequests[txId].isExchange == false) {
    //         require(
    //             wrapRequests[txId].teleporterFee < wrapRequests[txId].bitcoinAmount,
    //             "teleporter fee is too much"
    //         );
    //         if (wrapRequests[txId].teleporterFee > 0) {
    //             IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee);
    //         }
    //         IWrappedToken(wrappedBitcoin).mint(
    //             wrapRequests[txId].recipientAddress,
    //             wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
    //         );
    //         return true;
    //     }
    // }

    // function fastCCTransfer (bytes32 txId) internal returns(bool) {
    //     // determine transer recipient
    //     if (wrapRequests[txId].isExchange == true) {
    //         if (msg.sender == ccExchangeRouter) {
    //             // borrow wrapped token from fast pool and transfer it to cc exchnage router
    //             require(
    //                 fastTransfer(ccExchangeRouter, wrapRequests[txId].bitcoinAmount, wrapRequests[txId].blockNumber),
    //                 "fast transfer was failed"
    //             );
    //             return true;
    //         }
    //         if (msg.sender != ccExchangeRouter) {
    //             // TODO
    //             return true;
    //         }
    //     }

    //     if (wrapRequests[txId].isExchange == false) {
    //         // TODO: handle failed fast transfer request (because the fast limit was reached)
    //         if (wrapRequests[txId].teleporterFee > 0) {
    //             // pay half of the teleporter fee now and rest of it after finalization
    //             require(
    //                 fastTransfer(
    //                     msg.sender,
    //                     wrapRequests[txId].teleporterFee/2,
    //                     wrapRequests[txId].blockNumber
    //                 ),
    //                 "fast transfer to teleporter was failed"
    //             );
    //         }
    //         require(
    //             fastTransfer(
    //                 wrapRequests[txId].recipientAddress,
    //                 wrapRequests[txId].bitcoinAmount - wrapRequests[txId].teleporterFee,
    //                 wrapRequests[txId].blockNumber
    //             ),
    //             "fast transfer to user was failed"
    //         );
    //         return true;
    //     }
    // }

    // function instantCCTransfer (bytes32 txId) internal returns(bool) {

    //     require(
    //         wrapRequests[txId].teleporterFee < wrapRequests[txId].bitcoinAmount,
    //         "teleporter fee is too much"
    //     );
    //     if (wrapRequests[txId].teleporterFee > 0) {
    //         IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee);
    //     }
    //     // mint wrapped token for cc transfer router
    //     IWrappedToken(wrappedBitcoin).mint(
    //         address(this),
    //         wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
    //     );
    //     // give allowance to instant pool to transfer mint wrapped tokens
    //     IWrappedToken(wrappedBitcoin).approve(
    //         instantRouter,
    //         wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
    //     );
    //     // user wants to pay back the borrowed asset
    //     bool paybackResult = IInstantRouter(instantRouter).payBackInstantTransfer(
    //         wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee),
    //         wrapRequests[txId].recipientAddress
    //     );
    //     return true;
    // }

    // function instantCCTransferWithPermit(
    //     address signer,
    //     bytes memory signature,
    //     address receiver,
    //     uint instantTokenAmount,
    //     uint deadline
    // ) public override returns(bool) {
    //     IInstantRouter(instantRouter).instantCCTransferWithPermit(
    //         signer,
    //         signature,
    //         receiver,
    //         instantTokenAmount,
    //         deadline
    //     );
    //     emit CCTransfer(
    //         receiver,
    //         wrappedBitcoin,
    //         instantTokenAmount,
    //         2 // 2 means fast
    //     );
    //     return true;
    // }

    // function calculateTxId (
    //     bytes4 _version,
    //     bytes memory _vin,
    //     bytes calldata _vout,
    //     bytes4 _locktime
    // ) internal returns(bytes32) {
    //     bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
    //     bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
    //     return inputHash2;
    // }

    // function fastTransfer(
    //     address _recipient,
    //     uint amount,
    //     uint blockNumber
    // ) internal returns (bool) {
    //     return
    //     IFastRouter(fastRouter).fastTransfer(
    //         _recipient,
    //         amount,
    //         blockNumber
    //     );
    // }

    // function mintAfterFinalization(bytes32 txId) public override returns (bool) {
    //     wrapRequest memory request;
    //     request = wrapRequests[txId];
    //     require(request.isUsed == true, "The request has not been submitted before");
    //     require(request.isMinted == false, "The request has been minted before");
    //     // only mint wrapped token after finalization
    //     require(
    //         isConfirmed(
    //             txId,
    //             request.blockNumber,
    //             request.intermediateNodes,
    //             request.index,
    //             true, // TODO: replace it
    //             normalConfirmationParameter
    //         ),
    //         "Transaction has not been finalized"
    //     );
    //     wrapRequests[txId].isMinted = true;

    //     IWrappedToken(wrappedBitcoin).mint(
    //         bitcoinFastPool,
    //         wrapRequests[txId].bitcoinAmount - wrapRequests[txId].teleporterFee/2
    //     ); // mint for the bitcoin fast pool
    //     IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee/2); // mint for the teleporter
    //     emit PaybackFastLoan(
    //         wrapRequests[txId].recipientAddress,
    //         wrapRequests[txId].bitcoinAmount - wrapRequests[txId].teleporterFee/2
    //     );
    //     return true;
    // }

    // function saveWrapRequest(
    //     bytes memory vout,
    //     uint blockNumber,
    //     bytes memory intermediateNodes,
    //     uint index,
    //     bytes32 txId
    // ) internal {
    //     bytes memory arbitraryData;
    //     wrapRequest memory request;
    //     address desiredRecipient;
    //     desiredRecipient = IBitcoinTeleporter(bitcoinTeleporter).redeemScriptHash();
    //     (request.bitcoinAmount, arbitraryData) = BitcoinTxParser.parseAmountForP2SH(vout, desiredRecipient);
    //     request.recipientAddress = BitcoinTxParser.parseRecipientAddress(arbitraryData);
    //     request.teleporterFee = BitcoinTxParser.parseTeleporterFee(arbitraryData);
    //     request.isExchange = BitcoinTxParser.parseIsExchange(arbitraryData);
    //     request.speed = BitcoinTxParser.parseSpeed(arbitraryData);
    //     request.deadline = BitcoinTxParser.parseDeadline(arbitraryData);
    //     if (request.speed == 1) {
    //         // ~ if it is a fast request
    //         request.blockNumber = blockNumber;
    //         request.intermediateNodes = intermediateNodes;
    //         request.index = index;
    //     }
    //     if (request.speed == 2) {
    //         // ~ if it is an instant request
    //         request.exchangeToken = BitcoinTxParser.parseExchangeToken(arbitraryData);
    //         request.exchangeAmount = BitcoinTxParser.parseExchangeAmount(arbitraryData);
    //     }
    //     request.isUsed = true;
    //     wrapRequests[txId] = request;
    // }

    // function getFastNeededConfirmations() internal view returns(uint) {
    //     return IFastRouter(fastRouter).getNeededConfirmations();
    // }

    // function isConfirmed(
    //     bytes32 txId,
    //     uint256 blockNumber,
    //     bytes memory intermediateNodes,
    //     uint index,
    //     bool payWithTDT,
    //     uint neededConfirmations
    // ) internal returns (bool) {
    //     // TODO: uncomment it
    //     // uint feeAmount;
    //     // IERC20(feeTokenAddress).transferFrom(msg.sender, address(this), feeAmount);
    //     return IBitcoinRelay(bitcoinRelay).checkTxProof(
    //         txId,
    //         blockNumber,
    //         intermediateNodes,
    //         index
    //     // payWithTDT,
    //     // neededConfirmations
    //     );
    // }

    // function isRequestUsed(bytes32 txId) external view override returns(bool) {
    //     if (wrapRequests[txId].isUsed == true) {
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }

    // function isRequestMinted(bytes32 txId) external view override returns(bool) {
    //     if (wrapRequests[txId].isMinted == true) {
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }

    // function revertBytes32 (bytes32 input) internal returns(bytes32) {
    //     bytes memory temp;
    //     bytes32 result;
    //     for (uint i = 0; i < 32; i++) {
    //         temp = abi.encodePacked(temp, input[31-i]);
    //     }
    //     assembly {
    //         result := mload(add(temp, 32))
    //     }
    //     return result;
    // }
}