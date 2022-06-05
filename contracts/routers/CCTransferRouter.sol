pragma solidity ^0.7.6;

import "../libraries/SafeMath.sol";
import "../libraries/BitcoinTxParser.sol";
import "./interfaces/ICCTransferRouter.sol";
import "./interfaces/ICCExchangeRouter.sol";
import "../erc20/interfaces/IWrappedToken.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../teleporter/interfaces/IBitcoinTeleporter.sol";
import "./interfaces/IInstantRouter.sol";
import "./interfaces/IFastRouter.sol";
import "./InstantRouter.sol";
import "./FastRouter.sol";
import "hardhat/console.sol";

contract CCTransferRouter is ICCTransferRouter {
    using SafeMath for uint256;
    address public bitcoinRelay;
    address public bitcoinTeleporter;
    mapping(bytes32 => wrapRequest) public wrapRequests;
    address public ccExchangeRouter;
    address public instantRouter;
    address public fastRouter;
    address public override wrappedBitcoin;
    address public override bitcoinFastPool;
    address public bitcoinInstantPool;
    uint public override normalConfirmationParameter;
    address public override owner;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor(
        address _bitcoinRelay,
        address _bitcoinTeleporter, 
        uint _normalConfirmationParameter
    ) public {
        bitcoinRelay = _bitcoinRelay;
        bitcoinTeleporter = _bitcoinTeleporter;
        normalConfirmationParameter = _normalConfirmationParameter;
        owner = msg.sender;
    }

    function changeOwner(address _owner) external override onlyOwner {
        owner = _owner;
    }

    function setNormalConfirmationParameter(uint _normalConfirmationParameter) external override onlyOwner {
        normalConfirmationParameter = _normalConfirmationParameter;
    }

    function setBitcoinRelay(address _bitcoinRelay) external override onlyOwner {
        bitcoinRelay = _bitcoinRelay;
    }
    
    function setFastRouter(address _fastRouter) external override onlyOwner {
        fastRouter = _fastRouter;
        bitcoinFastPool = IFastRouter(fastRouter).bitcoinFastPool();
    }

    function setInstantRouter(address _instantRouter) external override onlyOwner {
        instantRouter = _instantRouter;
        bitcoinInstantPool = IInstantRouter(instantRouter).bitcoinInstantPool();
    }

    function setCCExchangeRouter(address _ccExchangeRouter) external override onlyOwner {
        ccExchangeRouter = _ccExchangeRouter;
        // ICCExchangeRouter(ccExchangeRouter).setInstantRouter(instantRouter);
    }

    function setWrappedBitcoin(address _wrappedBitcoin) external override onlyOwner returns (bool) {
        wrappedBitcoin = _wrappedBitcoin;
        return true;
    }
    // TODO: add burn with permit
    // TODO: handle fast transactions that are not executed because the fast limit was reached (they can mint token after finalization)
    function ccTransfer(
        bytes4 version,
        bytes memory vin,
        bytes calldata vout,
        bytes4 locktime,
        uint256 blockNumber,
        bytes calldata intermediateNodes,
        uint index,
        bool payWithTDT
    ) external override returns (bool) {
        bytes32 txId = calculateTxId(version, vin, vout, locktime);
        txId = revertBytes32(txId);
        require(
            !wrapRequests[txId].isUsed,
            "Request has been used before"
        );
        saveWrapRequest(vout, blockNumber, intermediateNodes, index, txId);

        if (wrapRequests[txId].speed == 0) {
            // check that the block has received enough confirmations
            require(
                isConfirmed(
                    txId,
                    blockNumber,
                    intermediateNodes,
                    index,
                    payWithTDT,
                    normalConfirmationParameter
                ),
                "Transaction has not finalized"
            );
            require(normalCCTransfer(txId), "normal cc transfer was not successful");
            emit CCTransfer(
                wrapRequests[txId].recipientAddress, 
                wrappedBitcoin, 
                wrapRequests[txId].bitcoinAmount, 
                wrapRequests[txId].speed
            );
            return true;
        }

        if (wrapRequests[txId].speed == 1) {
            // if transaction has been already finalized, there is no need to borrow wrapped token from fast pool
            if (isConfirmed(txId, blockNumber, intermediateNodes, index, payWithTDT, normalConfirmationParameter) == true) {
                require(normalCCTransfer(txId), "fast cc transfer was not successful");
                wrapRequests[txId].isMinted = true; // wrapped token is minted
                emit CCTransfer(
                    wrapRequests[txId].recipientAddress, 
                    wrappedBitcoin, 
                    wrapRequests[txId].bitcoinAmount, 
                    0 // the token is wrapped normally
                );
            } else {            
                // check that the block has received enough confirmations
                require(
                    isConfirmed(
                        txId,
                        blockNumber,
                        intermediateNodes,
                        index,
                        payWithTDT,
                        getFastNeededConfirmations()
                    ),
                    "Transaction has not received enough confirmations"
                );
                require(fastCCTransfer(txId), "fast cc transfer was not successful");
                emit CCTransfer(
                    wrapRequests[txId].recipientAddress, 
                    wrappedBitcoin, 
                    wrapRequests[txId].bitcoinAmount, 
                    wrapRequests[txId].speed
                );
            }
            return true;
        }

        if (wrapRequests[txId].speed == 2) { // pay back instant loan
            // check that the block has received enough confirmations
            require(
                isConfirmed(
                    txId,
                    blockNumber,
                    intermediateNodes,
                    index,
                    payWithTDT,
                    normalConfirmationParameter
                ),
                "Transaction has not finalized"
            );
            require(instantCCTransfer(txId), "instant cc transfer was not successful");
            return true;
        }
    }

    function normalCCTransfer (bytes32 txId) internal returns(bool) {

        if (wrapRequests[txId].isExchange == true) {
            // require(msg.sender == ccExchangeRouter, "message sender is not cc exchange router");
            if (msg.sender == ccExchangeRouter) {
                IWrappedToken(wrappedBitcoin).mint(ccExchangeRouter, wrapRequests[txId].bitcoinAmount);
                return true;
            }

            if (msg.sender != ccExchangeRouter) { 
                // handle unpredicted cases that exchange request execution was not succesful, so we want to mint wrapped token for user
                // wrapped token can only be mint after passing of deadline
                require(wrapRequests[txId].deadline < block.number, "deadline has not passed yet");
                require(
                    wrapRequests[txId].teleporterFee <= wrapRequests[txId].bitcoinAmount,
                    "teleporter fee is too much"
                );
                if (wrapRequests[txId].teleporterFee > 0) {
                    IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee);
                }
                IWrappedToken(wrappedBitcoin).mint(
                    wrapRequests[txId].recipientAddress,
                    wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
                );
                return true;    
            }   
        } 

        if (wrapRequests[txId].isExchange == false) {
            require(
                wrapRequests[txId].teleporterFee < wrapRequests[txId].bitcoinAmount,
                "teleporter fee is too much"
            );
            if (wrapRequests[txId].teleporterFee > 0) {
                IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee);
            }
            IWrappedToken(wrappedBitcoin).mint(
                wrapRequests[txId].recipientAddress,
                wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
            );
            return true; 
        }
    }

    function fastCCTransfer (bytes32 txId) internal returns(bool) {
        // determine transer recipient
        if (wrapRequests[txId].isExchange == true) {
            if (msg.sender == ccExchangeRouter) {
                // borrow wrapped token from fast pool and transfer it to cc exchnage router
                require(
                    fastTransfer(ccExchangeRouter, wrapRequests[txId].bitcoinAmount, wrapRequests[txId].blockNumber),
                    "fast transfer was failed"
                );
                return true;
            }
            if (msg.sender != ccExchangeRouter) {
                // TODO
                return true;
            }
        }

        if (wrapRequests[txId].isExchange == false) {
            // TODO: handle failed fast transfer request (because the fast limit was reached)
            if (wrapRequests[txId].teleporterFee > 0) {
                // pay half of the teleporter fee now and rest of it after finalization
                require(
                    fastTransfer(
                        msg.sender,
                        wrapRequests[txId].teleporterFee/2,
                        wrapRequests[txId].blockNumber
                    ),
                "fast transfer to teleporter was failed"
                );
            }
            require(
                fastTransfer(
                    wrapRequests[txId].recipientAddress,
                    wrapRequests[txId].bitcoinAmount - wrapRequests[txId].teleporterFee,
                    wrapRequests[txId].blockNumber
                ),
                "fast transfer to user was failed"
            );
            return true;
        }
    }

    function instantCCTransfer (bytes32 txId) internal returns(bool) {

        require(
            wrapRequests[txId].teleporterFee < wrapRequests[txId].bitcoinAmount,
            "teleporter fee is too much"
        );
        if (wrapRequests[txId].teleporterFee > 0) {
            IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee);
        }
        // mint wrapped token for cc transfer router
        IWrappedToken(wrappedBitcoin).mint(
            address(this),
            wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
        );
        // give allowance to instant pool to transfer mint wrapped tokens
        IWrappedToken(wrappedBitcoin).approve(
            instantRouter,
            wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee)
        );
        // user wants to pay back the borrowed asset
        bool paybackResult = IInstantRouter(instantRouter).payBackInstantTransfer(
            wrapRequests[txId].bitcoinAmount.sub(wrapRequests[txId].teleporterFee),
            wrapRequests[txId].recipientAddress
        );
        return true;
    }

    function instantCCTransferWithPermit(
        address signer,
        bytes memory signature,
        address receiver, 
        uint instantTokenAmount,
        uint deadline
    ) public override returns(bool) {
        IInstantRouter(instantRouter).instantCCTransferWithPermit(
            signer, 
            signature, 
            receiver, 
            instantTokenAmount, 
            deadline
        );
        emit CCTransfer(
            receiver, 
            wrappedBitcoin, 
            instantTokenAmount, 
            2 // 2 means fast
        );
        return true;
    }

    function calculateTxId (
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime
    ) internal returns(bytes32) {
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return inputHash2;
    }

    function fastTransfer(
        address _recipient,
        uint amount,
        uint blockNumber
    ) internal returns (bool) {
        return
            IFastRouter(fastRouter).fastTransfer(
                _recipient,
                amount,
                blockNumber
            );
    }

    function mintAfterFinalization(bytes32 txId) public override returns (bool) {
        wrapRequest memory request;
        request = wrapRequests[txId];
        require(request.isUsed == true, "The reuqest has not been submitted before");
        require(request.isMinted == false, "The reuqest has been minted before");
        // only mint wrapped token after finalization
        require(
            isConfirmed(
                txId,
                request.blockNumber,
                request.intermediateNodes,
                request.index,
                true, // TODO: replace it
                normalConfirmationParameter
            ),
            "Transaction has not been finalized"
        );
        wrapRequests[txId].isMinted = true;

        IWrappedToken(wrappedBitcoin).mint(
            bitcoinFastPool, 
            wrapRequests[txId].bitcoinAmount - wrapRequests[txId].teleporterFee/2
        ); // mint for the bitcoin fast pool
        IWrappedToken(wrappedBitcoin).mint(msg.sender, wrapRequests[txId].teleporterFee/2); // mint for the teleporter
        emit PaybackFastLoan(
            wrapRequests[txId].recipientAddress, 
            wrapRequests[txId].bitcoinAmount - wrapRequests[txId].teleporterFee/2
        );
        return true;
    }

    function saveWrapRequest(
        bytes memory vout,
        uint blockNumber,
        bytes memory intermediateNodes,
        uint index,
        bytes32 txId
    ) internal {
        bytes memory arbitraryData;
        wrapRequest memory request;
        address desiredRecipient;
        desiredRecipient = IBitcoinTeleporter(bitcoinTeleporter).redeemScriptHash();
        (request.bitcoinAmount, arbitraryData) = BitcoinTxParser.parseAmountForP2SH(vout, desiredRecipient);
        request.recipientAddress = BitcoinTxParser.parseRecipientAddress(arbitraryData);
        request.teleporterFee = BitcoinTxParser.parseTeleporterFee(arbitraryData);
        request.isExchange = BitcoinTxParser.parseIsExchange(arbitraryData);
        request.speed = BitcoinTxParser.parseSpeed(arbitraryData);
        request.deadline = BitcoinTxParser.parseDeadline(arbitraryData);
        if (request.speed == 1) {
            // ~ if it is a fast request
            request.blockNumber = blockNumber;
            request.intermediateNodes = intermediateNodes;
            request.index = index;
        }
        if (request.speed == 2) {
            // ~ if it is an instant request
            request.exchangeToken = BitcoinTxParser.parseExchangeToken(arbitraryData);
            request.exchangeAmount = BitcoinTxParser.parseExchangeAmount(arbitraryData);
        }
        request.isUsed = true;
        wrapRequests[txId] = request;
    }

    function getFastNeededConfirmations() internal view returns(uint) {
        return IFastRouter(fastRouter).getNeededConfirmations();
    }
    
    function isConfirmed(
        bytes32 txId,
        uint256 blockNumber,
        bytes memory intermediateNodes,
        uint index,
        bool payWithTDT,
        uint neededConfirmations
    ) internal returns (bool) {
        // TODO: uncomment it
        // uint feeAmount;
        // IERC20(feeTokenAddress).transferFrom(msg.sender, address(this), feeAmount);
        return IBitcoinRelay(bitcoinRelay).checkTxProof(
                txId,
                blockNumber,
                intermediateNodes,
                index,
                payWithTDT,
                neededConfirmations
            );
    }

    function isRequestUsed(bytes32 txId) external view override returns(bool) {
        if (wrapRequests[txId].isUsed == true) {
            return true;
        } else {
            return false;
        }
    }

    function isRequestMinted(bytes32 txId) external view override returns(bool) {
        if (wrapRequests[txId].isMinted == true) {
            return true;
        } else {
            return false;
        }
    }

    function revertBytes32 (bytes32 input) internal returns(bytes32) {
        bytes memory temp;
        bytes32 result;
        for (uint i = 0; i < 32; i++) {
            temp = abi.encodePacked(temp, input[31-i]);
        }
        assembly {
            result := mload(add(temp, 32))
        }
        return result;
    }
}