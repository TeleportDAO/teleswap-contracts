// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

import "./interfaces/ICCExchangeRouter.sol";
import "./interfaces/IExchangeRouter.sol";
import "./interfaces/ICCTransferRouter.sol";
import "./interfaces/IInstantRouter.sol";
import "../pools/interfaces/IFastPool.sol";
import "../erc20/interfaces/IWrappedToken.sol";
import "../teleporter/interfaces/IBitcoinTeleporter.sol";
import "../libraries/BitcoinTxParser.sol";
import "../libraries/TeleportDAOLibrary.sol";
import "hardhat/console.sol";

contract CCExchangeRouter is ICCExchangeRouter {

    using SafeMath for uint;
    address ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
    mapping(uint => request) private requests;
    uint private lastRequest;
    address[] private parsedPath;
    address public override liquidityPoolFactory;
    address public override WAVAX;
    address public override exchangeRouter;
    address public override wrappedBitcoin;
    address public bitcoinTeleporter;
    address public ccTransferRouter;
    address public instantRouter;
    address public override owner;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor (address _exchangeRouter, address _bitcoinTeleporter, address _ccTransferRouter) {
        exchangeRouter = _exchangeRouter;
        liquidityPoolFactory = IExchangeRouter(exchangeRouter).liquidityPoolFactory();
        WAVAX = IExchangeRouter(exchangeRouter).WAVAX();
        lastRequest = 0;
        bitcoinTeleporter = _bitcoinTeleporter;
        ccTransferRouter = _ccTransferRouter;
        owner = msg.sender;
    }

    function changeOwner(address _owner) external override onlyOwner {
        owner = _owner;
    }

    function setBitcoinTeleporter (address _bitcoinTeleporter) external override onlyOwner {
        bitcoinTeleporter = _bitcoinTeleporter;
    }

    function setWrappedBitcoin (address _wrappedBitcoin) external override onlyOwner {
        wrappedBitcoin = _wrappedBitcoin;
    }

    function setCCTransferRouter (address _ccTransferRouter) external override onlyOwner {
        ccTransferRouter = _ccTransferRouter;
    }

    function setInstantRouter (address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
    }

    function setExchangeRouter (address _exchangeRouter) external override onlyOwner {
        exchangeRouter = _exchangeRouter;
        liquidityPoolFactory = IExchangeRouter(exchangeRouter).liquidityPoolFactory();
        WAVAX = IExchangeRouter(exchangeRouter).WAVAX();
    }
    // for executing "normal" and "fast" cross-chain exchange requests
    function ccExchange(
        bytes4 version,
        bytes memory vin,
        bytes calldata vout,
        bytes4 locktime,
        uint256 blockNumber,
        bytes calldata intermediateNodes,
        uint index,
        bool payWithTDT
    ) external override {
        uint256 currentRequest = lastRequest;
        require(
            parseBitcoinTransaction(vout),
            "Transaction data is not correct"
        );
        if (requests[currentRequest].deadline >= (block.number + 1)) { // deadline has not passed yet
            // mint wrapped token for cc exchange router
            mintWrappedBitcoin(
                version,
                vin,
                vout,
                locktime,
                blockNumber,
                intermediateNodes,
                index,
                payWithTDT
            );
            // pay teleporter fee
            IWrappedToken(wrappedBitcoin).transfer(
                requests[currentRequest].teleporterAddress,
                requests[currentRequest].teleporterFee
            );

            if (requests[currentRequest].isFixedToken == false && requests[currentRequest].exchangeToken != WAVAX) {
                // give allowance to exchangeRouter to transferFrom CCExchangeRouter
                IWrappedToken(wrappedBitcoin).approve(
                    exchangeRouter,
                    requests[currentRequest].remainedInputAmount
                );
                uint[] memory amounts;
                bool result;
                (amounts, result) = swapExactTokensForTokens(
                    requests[currentRequest].remainedInputAmount,
                    requests[currentRequest].exchangeAmount,
                    requests[currentRequest].path,
                    requests[currentRequest].exchangeRecipientAddress,
                    requests[currentRequest].deadline
                );
                if (result) {
                    emit CCExchange(
                        requests[currentRequest].exchangeRecipientAddress,
                        requests[currentRequest].path[0],
                        requests[currentRequest].path[requests[currentRequest].path.length-1],
                        requests[currentRequest].remainedInputAmount,
                        amounts[amounts.length-1],
                        requests[currentRequest].speed
                    );
                } else {
                    paybackToUser(
                        version,
                        vin,
                        vout,
                        locktime,
                        blockNumber,
                        intermediateNodes,
                        index,
                        payWithTDT,
                        currentRequest
                    );
                }
            }

            if (requests[currentRequest].isFixedToken == false && requests[currentRequest].exchangeToken == WAVAX) {
                // give allowance to exchangeRouter to transfer from CCExchangeRouter
                IWrappedToken(wrappedBitcoin).approve(
                    exchangeRouter,
                    requests[currentRequest].remainedInputAmount
                );
                uint[] memory amounts;
                bool result;
                (amounts, result) = swapExactTokensForAVAX(
                    requests[currentRequest].remainedInputAmount,
                    requests[currentRequest].exchangeAmount,
                    requests[currentRequest].path,
                    requests[currentRequest].exchangeRecipientAddress,
                    requests[currentRequest].deadline
                );
                if (result) {
                    emit CCExchange(
                        requests[currentRequest].exchangeRecipientAddress,
                        requests[currentRequest].path[0],
                        requests[currentRequest].path[requests[currentRequest].path.length-1],
                        requests[currentRequest].remainedInputAmount,
                        amounts[amounts.length-1],
                        requests[currentRequest].speed
                    );
                } else {
                    paybackToUser(
                        version,
                        vin,
                        vout,
                        locktime,
                        blockNumber,
                        intermediateNodes,
                        index,
                        payWithTDT,
                        currentRequest
                    );
                }

            }

        }

        if (requests[currentRequest].deadline < (block.number + 1)) { // deadline has passed
            paybackToUser(version, vin, vout, locktime, blockNumber, intermediateNodes, index, payWithTDT, currentRequest);
        }

    }

    function instantCCExchangeWithPermit(
        address signer,
        bytes memory signature,
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address receiver,
        uint deadline
    ) external override {
        uint[] memory amounts;
        bool result;
        (amounts, result) = IInstantRouter(instantRouter).instantCCExchangeWithPermit(
            signer,
            signature,
            amountIn,
            amountOutMin,
            path,
            receiver,
            deadline
        );
        emit CCExchange(
            receiver,
            path[0],
            path[path.length-1],
            amountIn,
            amounts[amounts.length-1],
            2 // 2 means instant
        );
    }

    function paybackToUser (
        bytes4 version,
        bytes memory vin,
        bytes calldata vout,
        bytes4 locktime,
        uint256 blockNumber,
        bytes calldata intermediateNodes,
        uint index,
        bool payWithTDT,
        uint currentRequest
    ) internal {
        // mint wrapped token for cc exchange router
        mintWrappedBitcoin(
            version,
            vin,
            vout,
            locktime,
            blockNumber,
            intermediateNodes,
            index,
            payWithTDT
        );
        // transfer wrapped tokens to user
        IWrappedToken(wrappedBitcoin).transfer(
            requests[currentRequest].exchangeRecipientAddress,
            requests[currentRequest].remainedInputAmount
        );
        // pay teleporter fee
        IWrappedToken(wrappedBitcoin).transfer(
            requests[currentRequest].teleporterAddress,
            requests[currentRequest].teleporterFee
        );
    }

    function parseBitcoinTransaction(bytes memory vout) internal returns (bool){
        bytes memory arbitraryData;
        // TODO: edit address for parseTxOutputs
        address desiredRecipient;
        desiredRecipient = IBitcoinTeleporter(bitcoinTeleporter).redeemScriptHash();
        (requests[lastRequest].bitcoinAmount, arbitraryData) = BitcoinTxParser.parseAmountForP2SH(vout, desiredRecipient);
        requests[lastRequest].exchangeAmount = BitcoinTxParser.parseExchangeAmount(arbitraryData);
        requests[lastRequest].isFixedToken = BitcoinTxParser.parseIsFixedToken(arbitraryData);
        requests[lastRequest].exchangeRecipientAddress = BitcoinTxParser.parseRecipientAddress(arbitraryData);
        requests[lastRequest].teleporterFee = BitcoinTxParser.parseTeleporterFee(arbitraryData);
        requests[lastRequest].exchangeToken = BitcoinTxParser.parseExchangeToken(arbitraryData);
        requests[lastRequest].path = [wrappedBitcoin, requests[lastRequest].exchangeToken];
        requests[lastRequest].teleporterAddress = msg.sender; //TODO: check who is the msg.sender? teleporter or dex?
        requests[lastRequest].deadline = BitcoinTxParser.parseDeadline(arbitraryData);
        requests[lastRequest].isExchange = BitcoinTxParser.parseIsExchange(arbitraryData);
        requests[lastRequest].speed = BitcoinTxParser.parseSpeed(arbitraryData);
        requests[lastRequest].remainedInputAmount = parseRemainedInputAmount(
            requests[lastRequest].bitcoinAmount,
            requests[lastRequest].teleporterFee,
            requests[lastRequest].speed
        );
        lastRequest = lastRequest + 1;
        return true;
    }

    function parseRemainedInputAmount(
        uint256 bitcoinAmount,
        uint256 teleporterFee,
        uint speed
    ) internal view returns (uint256) {

        if(speed == 0) { // normal cc exchange
            require(bitcoinAmount > teleporterFee, "Insufficient fund");
            return bitcoinAmount.sub(teleporterFee);
        }

        // FIXME: un-comment this part of code based on new cc transfer
        // if(speed == 1) { // fast cc exchange
        //     // get the fastFee from the fastPool
        //     address bitcoinFastPool;
        //     bitcoinFastPool = ICCTransferRouter(ccTransferRouter).bitcoinFastPool();
        //     uint fastFee = IFastPool(bitcoinFastPool).fastFee();
        //     uint bitcoinAmountAfterFastFee = bitcoinAmount*(100-fastFee)/100;
        //     require(bitcoinAmountAfterFastFee > teleporterFee, "Insufficient fund");
        //     return bitcoinAmountAfterFastFee.sub(teleporterFee);
        // }

        if(speed == 2) { // instant cc exchange
            require(bitcoinAmount > teleporterFee, "Insufficient fund");
            return bitcoinAmount.sub(teleporterFee);
        }
    }

    function mintWrappedBitcoin(
        bytes4 version,
        bytes memory vin,
        bytes memory vout,
        bytes4 locktime,
        uint256 blockNumber,
        bytes memory intermediateNodes,
        uint index,
        bool payWithTDT
    ) internal {
        //_WrappedToken = wrappedTokenContract;
        //require(_WrappedToken.mint(blockNumber, rawTransaction, encodedPath, rlpParentNodes) == ture);
        require(
            ICCTransferRouter(ccTransferRouter).ccTransfer(
                version,
                vin,
                vout,
                locktime,
                blockNumber,
                intermediateNodes,
                index
            // payWithTDT
            )
        );
    }

    // check slippage and deadline
    // make it modifier if good
    function checkConditions(uint256 requestNumber) internal returns (bool) {
        uint256[] memory amounts;
        if (requests[requestNumber].isFixedToken == false) {
            amounts = TeleportDAOLibrary.getAmountsOut(
                liquidityPoolFactory,
                requests[requestNumber].remainedInputAmount,
                requests[requestNumber].path
            );
            require(
                amounts[amounts.length - 1] >= requests[requestNumber].exchangeAmount,
                "exchangeRouter: INSUFFICIENT_OUTPUT_AMOUNT"
            );
        }
        if (requests[requestNumber].isFixedToken == true) {
            amounts = TeleportDAOLibrary.getAmountsIn(
                liquidityPoolFactory,
                requests[requestNumber].exchangeAmount,
                requests[requestNumber].path
            );
            require(
                amounts[0] <= requests[requestNumber].remainedInputAmount,
                "exchangeRouter: EXCESSIVE_INPUT_AMOUNT"
            );
        }
    }

    function bytesToAddress(bytes memory bys) internal pure returns (address) {
        address addr;
        assembly {
            addr := mload(add(bys, 20))
        }
        return addr;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
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

    function swapExactTokensForAVAX(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
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
