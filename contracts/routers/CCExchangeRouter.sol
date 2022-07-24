// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

import "./interfaces/ICCExchangeRouter.sol";
import "./interfaces/IExchangeRouter.sol";
// import "./interfaces/ICCTransferRouter.sol";
import "./interfaces/IInstantRouter.sol";
// import "../pools/interfaces/IFastPool.sol";
// import "../erc20/interfaces/IWrappedToken.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockers/interfaces/ILockers.sol";
import "../libraries/TxHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "../teleporter/interfaces/IBitcoinTeleporter.sol";
// import "../libraries/BitcoinTxParser.sol";
// import "../libraries/TeleportDAOLibrary.sol";
import "hardhat/console.sol";

contract CCExchangeRouter is ICCExchangeRouter, Ownable, ReentrancyGuard {

    using SafeMath for uint;

    // address ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    // mapping(uint => request) private requests;
    // uint private lastRequest;
    // address[] private parsedPath;
    // address public override liquidityPoolFactory;
    // address public override WAVAX;
    // address public override exchangeRouter;
    // address public override wrappedBitcoin;
    // address public bitcoinTeleporter;
    // address public ccTransferRouter;
    // address public instantRouter;
    // address public override owner;

    // modifier onlyOwner {
    //     require(msg.sender == owner);
    //     _;
    // }

    // Public variables
    address public override relay;
    address public override instantRouter;
    address public override lockers;

    // TODO: how to set them?
    address public wrappedNativeToken;
    address public exchangeRouter;

    address public override teleBTC;
    mapping(uint => address) public override exchangeConnectors;

    // Private variables
    mapping(bytes32 => ccExchangeRequest) private ccExchangeRequests;

    constructor(address _lockers, address _relay, address _teleBTC) {
        // wrappedNativeToken = IExchangeRouter(exchangeRouter).wrappedNativeToken();
        relay = _relay;
        lockers = _lockers;
        teleBTC = _teleBTC;
    }

    // constructor (address _exchangeRouter, address _bitcoinTeleporter, address _ccTransferRouter) {
    //     exchangeRouter = _exchangeRouter;
    //     liquidityPoolFactory = IExchangeRouter(exchangeRouter).liquidityPoolFactory();
    //     WAVAX = IExchangeRouter(exchangeRouter).WAVAX();
    //     lastRequest = 0;
    //     bitcoinTeleporter = _bitcoinTeleporter;
    //     ccTransferRouter = _ccTransferRouter;
    //     owner = msg.sender;
    // }

    /// @notice         Changes relay contract address
    /// @dev            Only owner can call this
    /// @param _relay   The new relay contract address
    function setRelay(address _relay) external override onlyOwner {
        relay = _relay;
    }

    /// @notice                 Changes instantRouter contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instantRouter contract address
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
    }

    /// @notice                 Changes lockers contract address
    /// @dev                    Only owner can call this
    /// @param _lockers         The new lockers contract address
    function setLockers(address _lockers) external override onlyOwner {
        lockers = _lockers;
    }

    // function changeOwner(address _owner) external override onlyOwner {
    //     owner = _owner;
    // }

    // function setBitcoinTeleporter (address _bitcoinTeleporter) external override onlyOwner {
    //     bitcoinTeleporter = _bitcoinTeleporter;
    // }

    // function setWrappedBitcoin (address _wrappedBitcoin) external override onlyOwner {
    //     wrappedBitcoin = _wrappedBitcoin;
    // }

    // function setCCTransferRouter (address _ccTransferRouter) external override onlyOwner {
    //     ccTransferRouter = _ccTransferRouter;
    // }

    // function setInstantRouter (address _instantRouter) external override onlyOwner {
    //     instantRouter = _instantRouter;
    // }

     function setExchangeRouter (address _exchangeRouter) external override onlyOwner {
         exchangeRouter = _exchangeRouter;
//         liquidityPoolFactory = IExchangeRouter(exchangeRouter).liquidityPoolFactory();
//         WAVAX = IExchangeRouter(exchangeRouter).WAVAX();
     }
    // // for executing "normal" and "fast" cross-chain exchange requests
    // function ccExchange(
    //     bytes4 version,
    //     bytes memory vin,
    //     bytes calldata vout,
    //     bytes4 locktime,
    //     uint256 blockNumber,
    //     bytes calldata intermediateNodes,
    //     uint index,
    //     bool payWithTDT
    // ) external override {
    //     uint256 currentRequest = lastRequest;
    //     require(
    //         parseBitcoinTransaction(vout),
    //         "Transaction data is not correct"
    //     );
    //     if (requests[currentRequest].deadline >= (block.number + 1)) { // deadline has not passed yet
    //         // mint wrapped token for cc exchange router
    //         mintWrappedBitcoin(
    //             version,
    //             vin,
    //             vout,
    //             locktime,
    //             blockNumber,
    //             intermediateNodes,
    //             index,
    //             payWithTDT
    //         );
    //         // pay teleporter fee
    //         IWrappedToken(wrappedBitcoin).transfer(
    //             requests[currentRequest].teleporterAddress,
    //             requests[currentRequest].teleporterFee
    //         );

    //         if (requests[currentRequest].isFixedToken == false && requests[currentRequest].exchangeToken != WAVAX) {
    //             // give allowance to exchangeRouter to transferFrom CCExchangeRouter
    //             IWrappedToken(wrappedBitcoin).approve(
    //                 exchangeRouter,
    //                 requests[currentRequest].remainedInputAmount
    //             );
    //             uint[] memory amounts;
    //             bool result;
    //             (amounts, result) = swapExactTokensForTokens(
    //                 requests[currentRequest].remainedInputAmount,
    //                 requests[currentRequest].exchangeAmount,
    //                 requests[currentRequest].path,
    //                 requests[currentRequest].exchangeRecipientAddress,
    //                 requests[currentRequest].deadline
    //             );
    //             if (result) {
    //                 emit CCExchange(
    //                     requests[currentRequest].exchangeRecipientAddress,
    //                     requests[currentRequest].path[0],
    //                     requests[currentRequest].path[requests[currentRequest].path.length-1],
    //                     requests[currentRequest].remainedInputAmount,
    //                     amounts[amounts.length-1],
    //                     requests[currentRequest].speed
    //                 );
    //             } else {
    //                 paybackToUser(
    //                     version,
    //                     vin,
    //                     vout,
    //                     locktime,
    //                     blockNumber,
    //                     intermediateNodes,
    //                     index,
    //                     payWithTDT,
    //                     currentRequest
    //                 );
    //             }
    //         }

    //         if (requests[currentRequest].isFixedToken == false && requests[currentRequest].exchangeToken == WAVAX) {
    //             // give allowance to exchangeRouter to transfer from CCExchangeRouter
    //             IWrappedToken(wrappedBitcoin).approve(
    //                 exchangeRouter,
    //                 requests[currentRequest].remainedInputAmount
    //             );
    //             uint[] memory amounts;
    //             bool result;
    //             (amounts, result) = swapExactTokensForAVAX(
    //                 requests[currentRequest].remainedInputAmount,
    //                 requests[currentRequest].exchangeAmount,
    //                 requests[currentRequest].path,
    //                 requests[currentRequest].exchangeRecipientAddress,
    //                 requests[currentRequest].deadline
    //             );
    //             if (result) {
    //                 emit CCExchange(
    //                     requests[currentRequest].exchangeRecipientAddress,
    //                     requests[currentRequest].path[0],
    //                     requests[currentRequest].path[requests[currentRequest].path.length-1],
    //                     requests[currentRequest].remainedInputAmount,
    //                     amounts[amounts.length-1],
    //                     requests[currentRequest].speed
    //                 );
    //             } else {
    //                 paybackToUser(
    //                     version,
    //                     vin,
    //                     vout,
    //                     locktime,
    //                     blockNumber,
    //                     intermediateNodes,
    //                     index,
    //                     payWithTDT,
    //                     currentRequest
    //                 );
    //             }

    //         }

    //     }

    //     if (requests[currentRequest].deadline < (block.number + 1)) { // deadline has passed
    //         paybackToUser(version, vin, vout, locktime, blockNumber, intermediateNodes, index, payWithTDT, currentRequest);
    //     }

    // }


    /// @notice                 Changes wrapped token contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new wrapped token contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                             Check if the cc exchange request is done before
    /// @dev                                This is to avoid re-submitting a used request
    /// @param _txId                        The source chain transaction ID requested to be excahnged
    /// @return                             True if the cc exchange request is previously done
    function isRequestUsed(bytes32 _txId) external view override returns (bool) {
        return ccExchangeRequests[_txId].isUsed ? true : false;
    }

    /// @notice                     Executes a cross-chain exchange request after checking its merkle inclusion proof
    /// @dev                        Mints wrapped token for user if exchanging is not successful
    /// @param _version             Version of the transaction containing the user request
    /// @param _vin                 Inputs of the transaction containing the user request
    /// @param _vout                Outputs of the transaction containing the user request
    /// @param _locktime            Lock time of the transaction containing the user request
    /// @param _blockNumber         Height of the block containing the user request
    /// @param _intermediateNodes   Merkle inclusion proof for transaction containing the user request
    /// @param _index               Index of transaction containing the user request in the block
    /// @return
    function ccExchange(
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes calldata _intermediateNodes,
        uint _index
    ) external nonReentrant override returns (bool) {
        bytes32 txId = TxHelper.calculateTxId(_version, _vin, _vout, _locktime);
        require(
            !ccExchangeRequests[txId].isUsed,
            "CCExchangeRouter: the request has been used before"
        );
        ccExchangeRequests[txId].isUsed = true;
        _saveCCExchangeRequest(_vout, txId);
        // Check if transaction has been confirmed on source chain
        require(
            _isConfirmed(
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "CCExchangeRouter: transaction has not been finalized on source chain yet"
        );
        // Normal cc exchange request
        if (ccExchangeRequests[txId].speed == 0) {
            require(_normalCCExchange(txId), "CCExchangeRouter: normal cc exchange was not successful");
            return true;
        }
        // Pay back instant loan
        if (ccExchangeRequests[txId].speed == 1) {
            require(_payBackInstantLoan(txId), "CCExchangeRouter: paying back instant loan was not successful");
            return true;
        }
    }

    /// @notice            Executes a normal cross-chain exchange request
    /// @dev               Mints wrapped token for user if exchanging is not successful
    /// @param _txId       Id of the transaction containing the user request
    /// @return
    function _normalCCExchange(bytes32 _txId) internal returns (bool) {
        // Pays fee to teleporter
        if (ccExchangeRequests[_txId].fee > 0) {
            // Mints wrapped tokens for teleporter
            ITeleBTC(teleBTC).mint(
                msg.sender,
                ccExchangeRequests[_txId].fee
            );
        }
        uint remainedInputAmount = ccExchangeRequests[_txId].inputAmount.sub(ccExchangeRequests[_txId].fee);
        // Mints remained wrapped tokens for cc exchange router
        ITeleBTC(teleBTC).mint(
            address(this),
            remainedInputAmount
        );

        // Checks exchange conditions before executing it
        if (_checkExchangeConditions(remainedInputAmount, _txId)) {
            // Gives allowance to exchange router to transfer from cc exchange router
            ITeleBTC(teleBTC).approve(
                exchangeRouter,
                remainedInputAmount
            );
            uint[] memory amounts;
            if (
                ccExchangeRequests[_txId].isFixedToken == false &&
                ccExchangeRequests[_txId].path[ccExchangeRequests[_txId].path.length-1] != wrappedNativeToken
            ) {
                (amounts,) = _swapExactTokensForTokens(
                    remainedInputAmount,
                    ccExchangeRequests[_txId].outputAmount,
                    ccExchangeRequests[_txId].path,
                    ccExchangeRequests[_txId].recipientAddress,
                    ccExchangeRequests[_txId].deadline
                );
            }

            if (
                ccExchangeRequests[_txId].isFixedToken == false &&
                ccExchangeRequests[_txId].path[ccExchangeRequests[_txId].path.length-1] == wrappedNativeToken
            ) {
                (amounts,) = _swapExactTokensForAVAX(
                    remainedInputAmount,
                    ccExchangeRequests[_txId].outputAmount,
                    ccExchangeRequests[_txId].path,
                    ccExchangeRequests[_txId].recipientAddress,
                    ccExchangeRequests[_txId].deadline
                );
            }

            emit CCExchange(
                ccExchangeRequests[_txId].recipientAddress,
                ccExchangeRequests[_txId].path[0],
                ccExchangeRequests[_txId].path[ccExchangeRequests[_txId].path.length-1],
                remainedInputAmount,
                amounts[amounts.length-1],
                ccExchangeRequests[_txId].speed,
                ccExchangeRequests[_txId].fee
            );
        } else {
            // Mints wrapped token for recipient if exchange was failed
            ITeleBTC(teleBTC).transfer(
                ccExchangeRequests[_txId].recipientAddress,
                remainedInputAmount
            );
            emit FailedCCExchange(
                ccExchangeRequests[_txId].recipientAddress,
                remainedInputAmount
            );
        }
        return true;
    }

    /// @notice            Executes an instant cross-chain exchange request
    /// @dev               Mints wrapped token for instant router contract
    /// @param _txId       Id of the transaction containing the user request
    /// @return            True if paying back loan is successful
    function _payBackInstantLoan(bytes32 _txId) internal returns (bool) {
        // Pays fee to teleporter
        if (ccExchangeRequests[_txId].fee > 0) {
            // Mints wrapped tokens for teleporter
            ITeleBTC(teleBTC).mint(
                msg.sender,
                ccExchangeRequests[_txId].fee
            );
        }
        uint remainedAmount = ccExchangeRequests[_txId].inputAmount.sub(ccExchangeRequests[_txId].fee);
        // Mints wrapped token for cc exchange router
        ITeleBTC(teleBTC).mint(
            address(this),
            remainedAmount
        );
        // Gives allowance to instant router to transfer minted wrapped tokens
        ITeleBTC(teleBTC).approve(
            instantRouter,
            remainedAmount
        );
        // FIXME: Update when the instant router is updated
        // Calls instant router to pay back the borrowed tokens
        // IInstantRouter(instantRouter).payBackLoan(
        //     ccExchangeRequests[_txId].recipientAddress,
        //     remainedAmount
        // );
        return true;
    }

    /// @notice            Extracts data from the request and records it
    /// @dev               Finds how many tokens has been sent to lockers' multisig address
    /// @param _vout       Outputs of the transaction containing the user request
    /// @param _txId       Id of the transaction containing the user request
    /// @return            True if recording the request is successful
    function _saveCCExchangeRequest(bytes memory _vout, bytes32 _txId) internal returns (bool) {
        ccExchangeRequest memory request; //TODO: no need for this, set directly
        bytes memory arbitraryData;
        address desiredRecipient;
        address exchangeToken;

        // FIXME: change the following line
        desiredRecipient = ILockers(lockers).redeemScriptHash();

        (request.inputAmount, arbitraryData) = TxHelper.parseAmountForP2SH(_vout, desiredRecipient);
        require(!TxHelper.parseIsExchange(arbitraryData), "CCExchangeRouter: request is transfer request");
        // FIXME: adding the following method to the txHelper library
        // request.outputAmount = TxHelper.parseOutputAmount(arbitraryData);
        request.isFixedToken = TxHelper.parseIsFixedToken(arbitraryData);
        request.recipientAddress = TxHelper.parseRecipientAddress(arbitraryData);
        exchangeToken = TxHelper.parseExchangeToken(arbitraryData);
        // We assume that the path length is two
        address[] memory thePath = new address[](2);
        thePath[0] = teleBTC;
        thePath[1] = exchangeToken;
        // request.path = [teleBTC, exchangeToken];
        request.path = thePath;
        request.deadline = TxHelper.parseDeadline(arbitraryData);
        request.speed = TxHelper.parseSpeed(arbitraryData);
        ccExchangeRequests[_txId] = request;
        return true;
    }

    /// @notice                           Checks if exchanging can happen successfully
    /// @dev                              Avoids reverting the request by exchange router
    /// @param _remainedInputAmount       Remained input amount after reducing the teleporter fee
    /// @param _txId                      Id of the transaction containing the user request
    /// @return                           True if exchange conditions are satisfied
    function _checkExchangeConditions(uint _remainedInputAmount, bytes32 _txId) internal returns (bool) {
        // Checks deadline has not passed
        if (ccExchangeRequests[_txId].deadline < block.number) {
            return false;
        }

        (uint reserveIn, uint reserveOut) = IExchangeRouter(exchangeRouter).getReserves(
            ccExchangeRequests[_txId].path[0],
            ccExchangeRequests[_txId].path[1]
        );
        // Checks that enough liquidity for output token exists
        if (ccExchangeRequests[_txId].outputAmount < reserveOut) {
            return false;
        }
        // Checks that the input amount is enough
        if (ccExchangeRequests[_txId].isFixedToken == false) {
            uint requiredAmountIn = IExchangeRouter(exchangeRouter).getAmountIn(
                ccExchangeRequests[_txId].outputAmount,
                reserveIn,
                reserveOut
            );
            return _remainedInputAmount >= requiredAmountIn ? true : false;
        }
        // TODO: if isFixedToken == true
    }


    /// @notice                         Checks inclusion of the transaction in the specified block
    /// @dev                            Calls the relay contract to check Merkle inclusion proof
    /// @param _txId                    Id of the transaction
    /// @param _blockNumber             Height of the block containing the transaction
    /// @param _intermediateNodes       Merkle inclusion proof for the transaction
    /// @param _index                   Index of transaction in the block
    /// @return                         True if the transaction was included in the block
    function _isConfirmed (
        bytes32 _txId,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) internal returns (bool) {
        // TODO: uncomment it
        // uint feeAmount;
        // IERC20(feeTokenAddress).transferFrom(_teleporterAddress, address(this), feeAmount);
        return IBitcoinRelay(relay).checkTxProof(
            _txId,
            _blockNumber,
            _intermediateNodes,
            _index
        );
    }


    // function instantCCExchangeWithPermit(
    //     address signer,
    //     bytes memory signature,
    //     uint amountIn,
    //     uint amountOutMin,
    //     address[] memory path,
    //     address receiver,
    //     uint deadline
    // ) external override {
    //     uint[] memory amounts;
    //     bool result;
    //     (amounts, result) = IInstantRouter(instantRouter).instantCCExchangeWithPermit(
    //         signer,
    //         signature,
    //         amountIn,
    //         amountOutMin,
    //         path,
    //         receiver,
    //         deadline
    //     );
    //     emit CCExchange(
    //         receiver,
    //         path[0],
    //         path[path.length-1],
    //         amountIn,
    //         amounts[amounts.length-1],
    //         2 // 2 means instant
    //     );
    // }

    // function paybackToUser (
    //     bytes4 version,
    //     bytes memory vin,
    //     bytes calldata vout,
    //     bytes4 locktime,
    //     uint256 blockNumber,
    //     bytes calldata intermediateNodes,
    //     uint index,
    //     bool payWithTDT,
    //     uint currentRequest
    // ) internal {
    //     // mint wrapped token for cc exchange router
    //     mintWrappedBitcoin(
    //         version,
    //         vin,
    //         vout,
    //         locktime,
    //         blockNumber,
    //         intermediateNodes,
    //         index,
    //         payWithTDT
    //     );
    //     // transfer wrapped tokens to user
    //     IWrappedToken(wrappedBitcoin).transfer(
    //         requests[currentRequest].exchangeRecipientAddress,
    //         requests[currentRequest].remainedInputAmount
    //     );
    //     // pay teleporter fee
    //     IWrappedToken(wrappedBitcoin).transfer(
    //         requests[currentRequest].teleporterAddress,
    //         requests[currentRequest].teleporterFee
    //     );
    // }

    // function parseBitcoinTransaction(bytes memory vout) internal returns (bool){
    //     bytes memory arbitraryData;
    //     // TODO: edit address for parseTxOutputs
    //     address desiredRecipient;
    //     desiredRecipient = IBitcoinTeleporter(bitcoinTeleporter).redeemScriptHash();
    //     (requests[lastRequest].bitcoinAmount, arbitraryData) = BitcoinTxParser.parseAmountForP2SH(vout, desiredRecipient);
    //     requests[lastRequest].exchangeAmount = BitcoinTxParser.parseExchangeAmount(arbitraryData);
    //     requests[lastRequest].isFixedToken = BitcoinTxParser.parseIsFixedToken(arbitraryData);
    //     requests[lastRequest].exchangeRecipientAddress = BitcoinTxParser.parseRecipientAddress(arbitraryData);
    //     requests[lastRequest].teleporterFee = BitcoinTxParser.parseTeleporterFee(arbitraryData);
    //     requests[lastRequest].exchangeToken = BitcoinTxParser.parseExchangeToken(arbitraryData);
    //     requests[lastRequest].path = [wrappedBitcoin, requests[lastRequest].exchangeToken];
    //     requests[lastRequest].teleporterAddress = msg.sender; //TODO: check who is the msg.sender? teleporter or dex?
    //     requests[lastRequest].deadline = BitcoinTxParser.parseDeadline(arbitraryData);
    //     requests[lastRequest].isExchange = BitcoinTxParser.parseIsExchange(arbitraryData);
    //     requests[lastRequest].speed = BitcoinTxParser.parseSpeed(arbitraryData);
    //     requests[lastRequest].remainedInputAmount = parseRemainedInputAmount(
    //         requests[lastRequest].bitcoinAmount,
    //         requests[lastRequest].teleporterFee,
    //         requests[lastRequest].speed
    //     );
    //     lastRequest = lastRequest + 1;
    //     return true;
    // }

    // function parseRemainedInputAmount(
    //     uint256 bitcoinAmount,
    //     uint256 teleporterFee,
    //     uint speed
    // ) internal view returns (uint256) {

    //     if(speed == 0) { // normal cc exchange
    //         require(bitcoinAmount > teleporterFee, "Insufficient fund");
    //         return bitcoinAmount.sub(teleporterFee);
    //     }

    //     // FIXME: un-comment this part of code based on new cc transfer
    //     // if(speed == 1) { // fast cc exchange
    //     //     // get the fastFee from the fastPool
    //     //     address bitcoinFastPool;
    //     //     bitcoinFastPool = ICCTransferRouter(ccTransferRouter).bitcoinFastPool();
    //     //     uint fastFee = IFastPool(bitcoinFastPool).fastFee();
    //     //     uint bitcoinAmountAfterFastFee = bitcoinAmount*(100-fastFee)/100;
    //     //     require(bitcoinAmountAfterFastFee > teleporterFee, "Insufficient fund");
    //     //     return bitcoinAmountAfterFastFee.sub(teleporterFee);
    //     // }

    //     if(speed == 2) { // instant cc exchange
    //         require(bitcoinAmount > teleporterFee, "Insufficient fund");
    //         return bitcoinAmount.sub(teleporterFee);
    //     }
    // }

    // function mintWrappedBitcoin(
    //     bytes4 version,
    //     bytes memory vin,
    //     bytes memory vout,
    //     bytes4 locktime,
    //     uint256 blockNumber,
    //     bytes memory intermediateNodes,
    //     uint index,
    //     bool payWithTDT
    // ) internal {
    //     //_WrappedToken = wrappedTokenContract;
    //     //require(_WrappedToken.mint(blockNumber, rawTransaction, encodedPath, rlpParentNodes) == ture);
    //     require(
    //         ICCTransferRouter(ccTransferRouter).ccTransfer(
    //             version,
    //             vin,
    //             vout,
    //             locktime,
    //             blockNumber,
    //             intermediateNodes,
    //             index
    //         // payWithTDT
    //         )
    //     );
    // }

    // check slippage and deadline
    // make it modifier if good
    // function checkConditions(uint256 requestNumber) internal returns (bool) {
    //     uint256[] memory amounts;
    //     if (requests[requestNumber].isFixedToken == false) {
    //         amounts = TeleportDAOLibrary.getAmountsOut(
    //             liquidityPoolFactory,
    //             requests[requestNumber].remainedInputAmount,
    //             requests[requestNumber].path
    //         );
    //         require(
    //             amounts[amounts.length - 1] >= requests[requestNumber].exchangeAmount,
    //             "exchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT"
    //         );
    //     }
    //     if (requests[requestNumber].isFixedToken == true) {
    //         amounts = TeleportDAOLibrary.getAmountsIn(
    //             liquidityPoolFactory,
    //             requests[requestNumber].exchangeAmount,
    //             requests[requestNumber].path
    //         );
    //         require(
    //             amounts[0] <= requests[requestNumber].remainedInputAmount,
    //             "exchangeRouter: EXCESSIVE_INPUT_AMOUNT"
    //         );
    //     }
    // }

    // function bytesToAddress(bytes memory bys) internal pure returns (address) {
    //     address addr;
    //     assembly {
    //         addr := mload(add(bys, 20))
    //     }
    //     return addr;
    // }

    function _swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) internal returns(uint[] memory amounts, bool result) {
        (amounts, result) = IExchangeRouter(exchangeRouter).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    // TODO: this function does not exist in the exchangeRouter. why?
    // function _fromDEX_swapTokensForExactTokensSupportingFeeOnTransferTokens(
    //     uint amountIn,
    //     uint amountOutMin,
    //     address[] memory path,
    //     address to
    // ) internal {

    // }

    // TODO: internal functions cannot be payable
    // function _fromDEX_swapExactAVAXForTokensSupportingFeeOnTransferTokens(
    //     uint amountOutMin,
    //     address[] memory path,
    //     address to
    // ) internal payable {

    // }

    function _swapExactTokensForAVAX(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) internal returns(uint[] memory amounts, bool result) {
        (amounts, result) = IExchangeRouter(exchangeRouter).swapExactTokensForAVAX(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }
}
