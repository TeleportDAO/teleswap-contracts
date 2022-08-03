// SPDX-License-Identifier: <SPDX-License>
pragma solidity 0.8.0;

import "./interfaces/ICCExchangeRouter.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "./interfaces/IInstantRouter.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockers/interfaces/ILockers.sol";
import "../libraries/NewTxHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract CCExchangeRouter is ICCExchangeRouter, Ownable, ReentrancyGuard {

    using SafeMath for uint;

    // Public variables
    uint public override chainId;
    address public override relay;
    address public override instantRouter;
    address public override lockers;

    // TODO: how to set them?
    address public wrappedNativeToken;

    address public override teleBTC;
    mapping(uint => address) public override exchangeConnector;

    // Private variables
    mapping(bytes32 => ccExchangeRequest) private ccExchangeRequests;

    constructor(uint _chainId, address _lockers, address _relay, address _teleBTC) {
        chainId = _chainId;
        relay = _relay;
        lockers = _lockers;
        teleBTC = _teleBTC;
    }


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

    function setExchangeConnector(uint _appId, address _exchangeConnector) external override onlyOwner {
        exchangeConnector[_appId] = _exchangeConnector;
    }

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
        uint _index,
        address lockerBitcoinDecodedAddress
    ) external nonReentrant override returns (bool) {
        // Calculates transaction id
        bytes32 txId = NewTxHelper.calculateTxId(_version, _vin, _vout, _locktime);

        // Checks that the request has not been processed before
        require(
            !ccExchangeRequests[txId].isUsed,
            "CCExchangeRouter: the request has been used before"
        );

        // Extracts information from the request
        _saveCCExchangeRequest(lockerBitcoinDecodedAddress, _vout, txId);

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
            require(
                _normalCCExchange(lockerBitcoinDecodedAddress, txId), 
                "CCExchangeRouter: normal cc exchange was not successful"
            );
            return true;
        }

        // Pay back instant loan
        if (ccExchangeRequests[txId].speed == 1) {
            require(
                _payBackInstantLoan(lockerBitcoinDecodedAddress, txId), 
                "CCExchangeRouter: paying back instant loan was not successful"
            );
            return true;
        }
    }

    /// @notice            Executes a normal cross-chain exchange request
    /// @dev               Mints wrapped token for user if exchanging is not successful
    /// @param _txId       Id of the transaction containing the user request
    /// @return
    function _normalCCExchange(address lockerBitcoinDecodedAddress, bytes32 _txId) internal returns (bool) {
        // Pays fee to teleporter
        if (ccExchangeRequests[_txId].fee > 0) {

            // Mints wrapped tokens for teleporter
            ILockers(lockers).mint(
                lockerBitcoinDecodedAddress,
                msg.sender,
                ccExchangeRequests[_txId].fee
            );
        }
        
        // Mints remained wrapped tokens for cc exchange router
        uint remainedInputAmount = ccExchangeRequests[_txId].inputAmount.sub(ccExchangeRequests[_txId].fee);
        ILockers(lockers).mint(
            lockerBitcoinDecodedAddress,
            address(this),
            remainedInputAmount
        );

        
        bool result;
        uint[] memory amounts;

        // Gets exchnage connector address
        address _exchangeConnector = exchangeConnector[ccExchangeRequests[_txId].appId];

        // Gives allowance to exchange connector to transfer from cc exchange router
        ITeleBTC(teleBTC).approve(
            _exchangeConnector,
            remainedInputAmount
        );

        if (_exchangeConnector != address(0)) {
            // Exchanges minted teleBTC for output token
            (result, amounts) = IExchangeConnector(_exchangeConnector).swap(
                remainedInputAmount,
                ccExchangeRequests[_txId].outputAmount,
                ccExchangeRequests[_txId].path,
                ccExchangeRequests[_txId].recipientAddress,
                ccExchangeRequests[_txId].deadline,
                ccExchangeRequests[_txId].isFixedToken
            );
        } else {
            result = false;
        }

        if (result) {
            // Emits CCExchange if exchange was successful
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
            // Sends teleBTC to recipient if exchange was unsuccessful
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
    function _payBackInstantLoan(address lockerBitcoinDecodedAddress, bytes32 _txId) internal returns (bool) {
        // Pays fee to teleporter
        if (ccExchangeRequests[_txId].fee > 0) {
            // Mints wrapped tokens for teleporter
            ILockers(lockers).mint(
                lockerBitcoinDecodedAddress,
                msg.sender,
                ccExchangeRequests[_txId].fee
            );
        }
        uint remainedAmount = ccExchangeRequests[_txId].inputAmount.sub(ccExchangeRequests[_txId].fee);
        // Mints wrapped token for cc exchange router
        ILockers(lockers).mint(
            lockerBitcoinDecodedAddress,
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
    function _saveCCExchangeRequest(
        address _lockerBitcoinDecodedAddress,
        bytes memory _vout,
        bytes32 _txId
    ) internal returns (bool) {

        ccExchangeRequest memory request; //TODO: no need for this, set directly
        bytes memory arbitraryData;
        address desiredRecipient;
        address exchangeToken;
        uint percentageFee;
        
        // Checks that given bitcoin address is locker
        require(
            ILockers(lockers).isLocker(_lockerBitcoinDecodedAddress),
            "CCExchangeRouter: no locker with the bitcoin decoded addresss exists"
        );
        
        // Extracts value and opreturn from transaction
        (request.inputAmount, arbitraryData) = NewTxHelper.parseAmountForP2PK(_vout, _lockerBitcoinDecodedAddress);

        // Checks that the request belongs to this chain
        require(chainId == NewTxHelper.parseChainId(arbitraryData), "CCExchangeRouter: chain id is not correct");

        request.appId = NewTxHelper.parseAppId(arbitraryData);
        require(NewTxHelper.parseExchangeToken(arbitraryData) != address(0), "CCExchangeRouter: request is transfer request");
        // FIXME: adding the following method to the txHelper library
        // request.outputAmount = TxHelper.parseOutputAmount(arbitraryData);
        request.outputAmount = NewTxHelper.parseExchangeOutputAmount(arbitraryData);

        if (NewTxHelper.parseIsFixedToken(arbitraryData) == 0) {
            request.isFixedToken = false ;
        } else {
            request.isFixedToken = true ;
        }

        request.recipientAddress = NewTxHelper.parseRecipientAddress(arbitraryData);
        exchangeToken = NewTxHelper.parseExchangeToken(arbitraryData);

        // We assume that the path length is two
        address[] memory thePath = new address[](2);
        thePath[0] = teleBTC;
        thePath[1] = exchangeToken;
        request.path = thePath;

        request.deadline = NewTxHelper.parseDeadline(arbitraryData);

        // TODO: fix the fee to use percent instead of
        // Calculates fee
        percentageFee = NewTxHelper.parsePercentageFee(arbitraryData);
        require(percentageFee >= 0 && percentageFee < 10000, "CCExchangeRouter: percentage fee is not correct");
        request.fee = percentageFee.mul(request.inputAmount).div(10000);

        request.speed = NewTxHelper.parseSpeed(arbitraryData);
        
        request.isUsed = true;

        // Saves request
        ccExchangeRequests[_txId] = request;

        return true;
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
}
