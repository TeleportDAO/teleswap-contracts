// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./EthCcExchangeRouterStorage.sol";
import "./interfaces/IEthCcExchangeRouter.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../lockers/interfaces/ILockers.sol";
import "../libraries/RequestHelper.sol";
import "@teleportdao/btc-evm-bridge/contracts/libraries/BitcoinHelper.sol";
import "@teleportdao/btc-evm-bridge/contracts/relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";
import "./interfaces/IBurnRouter.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";


contract EthCcExchangeRouterLogic is IEthCcExchangeRouter, EthCcExchangeRouterStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using BytesLib for bytes;

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CCExchangeRouter: address is zero");
        _;
    }

    /// @notice                             Gives default params to initiate cc exchange router
    /// @param _startingBlockNumber         Requests that are included in a block older than _startingBlockNumber cannot be executed
    /// @param _protocolPercentageFee       Percentage amount of protocol fee (min: %0.01)
    /// @param _chainId                     Id of the underlying chain
    /// @param _relay                       The Relay address to validate data from source chain
    /// @param _lockers                     Lockers' contract address
    /// @param _teleBTC                     TeleportDAO BTC ERC20 token address
    /// @param _treasury                    Address of treasury that collects protocol fees
    function initialize(
        uint _startingBlockNumber,
        uint _protocolPercentageFee,
        uint _chainId,
        address _lockers,
        address _relay,
        address _teleBTC,
        address _treasury,
        address[] memory _supportedTokens,
        address _across,
        address _burnRouter
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

        for (uint i = 0; i < _supportedTokens.length; i++) {
            _addSupportedExchangeToken(_supportedTokens[i]);
        }

        _setAcross(_across);

        _setBurnRouter(_burnRouter);
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice Setter for starting block number
    function setStartingBlockNumber(uint _startingBlockNumber) external override onlyOwner {
        _setStartingBlockNumber(_startingBlockNumber);
    }

    /// @notice         Changes relay contract address
    /// @dev            Only owner can call this
    /// @param _relay   The new relay contract address
    function setRelay(address _relay) external override onlyOwner {
        _setRelay(_relay);
    }

    /// @notice                 Changes instantRouter contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instantRouter contract address
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        _setInstantRouter(_instantRouter);
    }

    /// @notice                 Changes lockers contract address
    /// @dev                    Only owner can call this
    /// @param _lockers         The new lockers contract address
    function setLockers(address _lockers) external override onlyOwner {
        _setLockers(_lockers);
    }

    /// @notice                     Sets appId for an exchange connector
    /// @dev                        Only owner can call this. _exchangeConnector can be set to zero to inactive an app
    /// @param _appId               AppId of exchange connector
    /// @param _exchangeConnector   Address of exchange connector
    function setExchangeConnector(
        uint _appId, 
        address _exchangeConnector
    ) external override onlyOwner {
        exchangeConnector[_appId] = _exchangeConnector;
        emit SetExchangeConnector(_appId, _exchangeConnector);
    }

    /// @notice                 Changes teleBTC contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new teleBTC contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        _setTeleBTC(_teleBTC);
    }

    /// @notice                             Setter for protocol percentage fee
    /// @dev                    Only owner can call this
    /// @param _protocolPercentageFee       Percentage amount of protocol fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        _setProtocolPercentageFee(_protocolPercentageFee);
    }

    /// @notice                    Setter for treasury
    /// @dev                       Only owner can call this
    /// @param _treasury           Treasury address
    function setTreasury(address _treasury) external override onlyOwner {
        _setTreasury(_treasury);
    }

    /// @notice                    Setter for a supported exchange token
    /// @dev                       Only owner can call this
    /// @param _token              Exchange token address
    function addSupportedExchangeToken(address _token) external override onlyOwner {
        _addSupportedExchangeToken(_token);
    }

    /// @notice                    Remover for a supported exchange token
    /// @dev                       Only owner can call this
    /// @param _token           Exchange token address
    function removeSupportedExchangeToken(address _token) external override onlyOwner {
        _removeSupportedExchangeToken(_token);
    }


    /// @notice                    Setter for across
    /// @dev                       Only owner can call this
    /// @param _across             Across address
    function updateAcross(address _across) external override onlyOwner {
        _setAcross(_across);
    }

    /// @notice                    Setter for burnRouter
    /// @dev                       Only owner can call this
    /// @param _burnRouter         BurnRouter address
    function updateBurnRouter(address _burnRouter) external override onlyOwner {
        _setBurnRouter(_burnRouter);
    }

    /// @notice         Internal setter for relay contract address
    /// @param _relay   The new relay contract address
    function _setRelay(address _relay) private nonZeroAddress(_relay) {
        emit NewRelay(relay, _relay);
        relay = _relay;
    }

    /// @notice                 Internal setter for instantRouter contract address
    /// @param _instantRouter   The new instantRouter contract address
    function _setInstantRouter(address _instantRouter) private nonZeroAddress(_instantRouter) {
        emit NewInstantRouter(instantRouter, _instantRouter);
        instantRouter = _instantRouter;
    }

    /// @notice                 Internal setter for lockers contract address
    /// @param _lockers         The new lockers contract address
    function _setLockers(address _lockers) private nonZeroAddress(_lockers) {
        emit NewLockers(lockers, _lockers);
        lockers = _lockers;
    }

    /// @notice                 Internal setter for teleBTC contract address
    /// @param _teleBTC         The new teleBTC contract address
    function _setTeleBTC(address _teleBTC) private nonZeroAddress(_teleBTC) {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
    }

    /// @notice                             Internal setter for protocol percentage fee
    /// @param _protocolPercentageFee       Percentage amount of protocol fee
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

    /// @notice                    Internal setter for treasury
    /// @param _treasury           Treasury address
    function _setTreasury(address _treasury) private nonZeroAddress(_treasury) {
        emit NewTreasury(treasury, _treasury);
        treasury = _treasury;
    }


    /// @notice                    Internal setter for a supported exchange token
    /// @param _token              Supported exchange token address
    function _addSupportedExchangeToken(address _token) private nonZeroAddress(_token) {
        emit ExchangeTokenAdded(_token);
        isExchangeTokenSupported[_token] = true;
    }

    /// @notice                    Internal remover for a supported exchange token
    /// @param _token           Supported exchange token address
    function _removeSupportedExchangeToken(address _token) private nonZeroAddress(_token) {
        emit ExchangeTokenRemoved(_token);
        isExchangeTokenSupported[_token] = false;
    }

    /// @notice                    Internal setter for across
    /// @param _across             Across address
    function _setAcross(address _across) private nonZeroAddress(_across) {
        emit AcrossUpdated(across, _across);
        across = _across;
    }

    /// @notice                    Internal setter for burnRouter
    /// @param _burnRouter         BurnRouter address
    function _setBurnRouter(address _burnRouter) private nonZeroAddress(_burnRouter) {
        emit BurnRouterUpdated(burnRouter, _burnRouter);
        burnRouter = _burnRouter;
    }

    /// @notice                             Check if the cc exchange request has been executed before
    /// @dev                                It prevents re-submitting an executed request
    /// @param _txId                        The transaction ID of request on source chain 
    /// @return                             True if the cc exchange request has been already executed
    function isRequestUsed(bytes32 _txId) external view override returns (bool) {
        return ccExchangeRequests[_txId].isUsed ? true : false;
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
        require(_msgSender() == instantRouter, "CCExchangeRouter: invalid sender");
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

        // Normal cc exchange request
        _normalCCExchange(_lockerLockingScript, txId);

        return true;
    }

    /// @notice                          Executes a normal cross-chain exchange request
    /// @dev                             Mints teleBTC for user if exchanging is not successful
    /// @param _lockerLockingScript      Locker's locking script    
    /// @param _txId                     Id of the transaction containing the user request
    function _normalCCExchange(bytes memory _lockerLockingScript, bytes32 _txId) private {
        // Gets remained amount after reducing fees
        uint remainedInputAmount = _mintAndReduceFees(_lockerLockingScript, _txId);

        ccExchangeRequests[_txId].remainedInputAmount = remainedInputAmount;

        bool result;
        uint[] memory amounts;

        // Gets exchange connector address
        address _exchangeConnector = exchangeConnector[ccExchangeRequests[_txId].appId];
        require(_exchangeConnector != address(0), "CCExchangeRouter: app id doesn't exist");
        
        ethCcExchangeRequest memory theCCExchangeReq = ccExchangeRequests[_txId];

        if (!isExchangeTokenSupported[theCCExchangeReq.path[1]]) {
            // FIXME: in the case of failure TELEBTC will be stock in the contract, till its owner do something for it

            emit FailedCCExchange(
                _lockerLockingScript,
                0,
                ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                theCCExchangeReq.recipientAddress,
                [theCCExchangeReq.path[0], theCCExchangeReq.path[1]], // input token // output token
                [remainedInputAmount, 0],// input amount //  output amount
                theCCExchangeReq.speed,
                _msgSender(), // Teleporter address
                theCCExchangeReq.fee,
                _txId,
                theCCExchangeReq.appId
            );

        } else {
            // Gives allowance to exchange connector to transfer from cc exchange router
            ITeleBTC(teleBTC).approve(
                _exchangeConnector,
                remainedInputAmount
            );

            // TODO: swap fucntion of IExchangeConnector is doing the exact thing, so it's a duplicate
            if (IExchangeConnector(_exchangeConnector).isPathValid(theCCExchangeReq.path)) {
                // Exchanges minted teleBTC for output token
                (result, amounts) = IExchangeConnector(_exchangeConnector).swap(
                    remainedInputAmount,
                    theCCExchangeReq.outputAmount,
                    theCCExchangeReq.path,
                    // theCCExchangeReq.recipientAddress,
                    // get all the tokens
                    address(this),
                    theCCExchangeReq.deadline,
                    // theCCExchangeReq.isFixedToken
                    // we shold use all the input
                    true
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
                    // theCCExchangeReq.recipientAddress,
                    // get all the tokens
                    address(this),
                    theCCExchangeReq.deadline,
                    // theCCExchangeReq.isFixedToken
                    // We should use all the input
                    true
                );
            }

            if (result) {
                // Emits CCExchange if exchange was successful
                emit CCExchange(
                    _lockerLockingScript,
                    0,
                    ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                    theCCExchangeReq.recipientAddress,
                    [theCCExchangeReq.path[0], theCCExchangeReq.path[1]], // input token // output token
                    [amounts[0], amounts[amounts.length-1]], // input amount // output amount
                    theCCExchangeReq.speed,
                    _msgSender(), // Teleporter address
                    theCCExchangeReq.fee,
                    _txId,
                    theCCExchangeReq.appId
                );

                // FIXME: add all requirement
                ITeleBTC(theCCExchangeReq.path[1]).approve(
                    across, 
                    amounts[amounts.length-1]
                );

                ccExchangeRequests[_txId].isTransferedToEth = true;

                bytes memory nullData;

                SpokePoolInterface(across).deposit(
                    theCCExchangeReq.recipientAddress,
                    theCCExchangeReq.path[1],
                    amounts[amounts.length-1],
                    // eth chain id
                    1,
                    // FIXME: decide relayer percentage fee to be updatable or not
                    1000000,
                    uint32(block.timestamp),
                    nullData,
                    115792089237316195423570985008687907853269984665640564039457584007913129639935
                );

                // Transfers rest of teleBTC to recipientAddress (if input amount is not fixed)
                // FIXME: convert all input TeleBTC to the desired token
                // if (theCCExchangeReq.isFixedToken == false) {
                //     ITeleBTC(teleBTC).transfer(
                //         theCCExchangeReq.recipientAddress,
                //         remainedInputAmount - amounts[0]
                //     );
                // }

            } else {
                // Handles situation when exchange was not successful

                // FIXME: how to handle the failed situation

                // Revokes allowance
                ITeleBTC(teleBTC).approve(
                    _exchangeConnector,
                    0
                );

                // Sends teleBTC to recipient if exchange wasn't successful
                // ITeleBTC(teleBTC).transfer(
                //     theCCExchangeReq.recipientAddress,
                //     remainedInputAmount
                // );

                // FIXME: in the case of failure TELEBTC will be stock in the contract, till its owner do something for it

                emit FailedCCExchange(
                    _lockerLockingScript,
                    0,
                    ILockers(lockers).getLockerTargetAddress(_lockerLockingScript),
                    theCCExchangeReq.recipientAddress,
                    [theCCExchangeReq.path[0], theCCExchangeReq.path[1]], // input token // output token
                    [remainedInputAmount, 0],// input amount //  output amount
                    theCCExchangeReq.speed,
                    _msgSender(), // Teleporter address
                    theCCExchangeReq.fee,
                    _txId,
                    theCCExchangeReq.appId
                );
            }
        }
    }

    /// @notice                             Parses and saves the request
    /// @dev                                Checks that user has sent BTC to a valid locker
    /// @param _lockerLockingScript         Locker's locking script
    /// @param _vout                        The outputs of the tx
    /// @param _txId                        The txID of the request
    function _saveCCExchangeRequest(
        bytes memory _lockerLockingScript,
        bytes memory _vout,
        bytes32 _txId
    ) private {

        // Checks that given script hash is locker
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCExchangeRouter: no locker with give script hash exists"
        );

        // Extracts value and opreturn data from request
        ethCcExchangeRequest memory request; // Defines it to save gas

        bytes memory arbitraryData;
        (request.inputAmount, arbitraryData) = BitcoinHelper.parseValueAndDataHavingLockingScriptBigPayload(
            _vout, 
            _lockerLockingScript
        );

        require(arbitraryData.length == 79, "CCExchangeRouter: invalid len");

        // Checks that input amount is not zero
        require(request.inputAmount > 0, "CCExchangeRouter: input amount is zero");

        // Checks that the request belongs to this chain
        require(chainId == RequestHelper.parseChainId(arbitraryData), "CCExchangeRouter: chain id is not correct");
        request.appId = RequestHelper.parseAppId(arbitraryData);
        
        address exchangeToken = RequestHelper.parseExchangeToken(arbitraryData);

        request.outputAmount = RequestHelper.parseExchangeOutputAmount(arbitraryData);

        // FIXME: only support the option that use all the input
        request.isFixedToken = true ;
        // if (RequestHelper.parseIsFixedToken(arbitraryData) == 0) {
        //     request.isFixedToken = false ;
        // } else {
        //     request.isFixedToken = true ;
        // }

        request.recipientAddress = RequestHelper.parseRecipientAddress(arbitraryData);

        // note: we assume that the path length is two
        address[] memory thePath = new address[](2);
        thePath[0] = teleBTC;
        thePath[1] = exchangeToken;
        request.path = thePath;

        request.deadline = RequestHelper.parseDeadline(arbitraryData);

        // Calculates fee
        uint percentageFee = RequestHelper.parsePercentageFee(arbitraryData);
        require(percentageFee <= MAX_PROTOCOL_FEE, "CCExchangeRouter: percentage fee is not correct");
        request.fee = percentageFee*request.inputAmount/MAX_PROTOCOL_FEE;

        // FIXME: speed can be removed and and compare EthCc with Cc based on the appIds
        request.speed = RequestHelper.parseSpeed(arbitraryData);
        require(request.speed == 1, "CCExchangeRouter: speed is not correct");

        request.isUsed = true;

        // Saves request
        ccExchangeRequests[_txId] = request;
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
        // Finds fee amount
        uint feeAmount = IBitcoinRelay(relay).getBlockHeaderFee(_blockNumber, 0);
        require(msg.value >= feeAmount, "CCExchangeRouter: paid fee is not sufficient");

        // Calls relay contract
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

        // Sends extra ETH back to _msgSender()
        Address.sendValue(payable(_msgSender()), msg.value - feeAmount);

        return abi.decode(data, (bool));
    }

    /// @notice                       Mints teleBTC by calling lockers contract
    /// @param _lockerLockingScript   Locker's locking script
    /// @param _txId                  The transaction ID of the request
    /// @return _remainedAmount       Amount of teleBTC that user receives after reducing all fees (protocol, locker, teleporter)
    function _mintAndReduceFees(
        bytes memory _lockerLockingScript,
        bytes32 _txId
    ) private returns (uint _remainedAmount) {

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

    receive() external payable {}


    /// @notice                     Executes a cross-chain exchange request after checking its merkle inclusion proof
    /// @dev                        Mints teleBTC for user if exchanging is not successful
    /// @param _message             Version of the transaction containing the user request
    /// @return
    function withdrawFailedCcExchangeToBTC(
        bytes memory _message,
        bytes32 r,
        bytes32 s,
        uint8 v,
        bytes calldata _lockerLockingScript
    ) external nonReentrant override returns (bool) {

        uint8 theScriptType = _message.toUint8(0);
        uint8 theUserScriptLength = _message.toUint8(8);
        bytes32 theTxId = _message.toBytes32(16);
        bytes memory userScript = _message.slice(48, uint256(theUserScriptLength));

        require(
            theScriptType <= uint8(ScriptTypes.P2TR),
            "CCExchangeRouter: invalid script type"
        );

        require(
            _verifySig(
                _message,
                r,
                s,
                v
            ) == ccExchangeRequests[theTxId].recipientAddress,
            "CCExchangeRouter: invalid signature"
        );

        IBurnRouter(burnRouter).ccBurn(
            ccExchangeRequests[theTxId].remainedInputAmount,
            userScript,
            ScriptTypes(theScriptType),
            _lockerLockingScript
        );

        return true;
    }

    // TODO: move to a library
    function _verifySig(
        bytes memory message,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure returns (address) {
        // Compute the message hash
        bytes32 messageHash = keccak256(message);

        // Prefix the message hash as per the Ethereum signing standard
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n", uintToString(message.length), messageHash)
        );

        // Verify the message using ecrecover
        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        require(signer != address(0), "PolygonConnectorLogic: Invalid sig");

        return signer;
    }

    // TODO: move to a library
    // Helper function to convert uint to string
    function uintToString(uint v) private pure returns (string memory str) {
        if (v == 0) {
            return "0";
        }
        uint j = v;
        uint length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint k = length;
        while (v != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(v - v / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            v /= 10;
        }
        str = string(bstr);
    }


    /// @notice                     Executes a cross-chain exchange request after checking its merkle inclusion proof
    /// @dev                        Mints teleBTC for user if exchanging is not successful
    /// @param _message             Version of the transaction containing the user request
    /// @return
    function reDoFailedCcExchange(
        bytes memory _message,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external nonReentrant override returns (bool) {
        bytes32 theTxId = _message.toBytes32(0);
        uint256 theOutputAmount = _message.toUint256(32);
        uint256 theDeadline = _message.toUint256(64);

        ethCcExchangeRequest memory theCCExchangeReq = ccExchangeRequests[theTxId];

        require(
            _verifySig(
                _message,
                r,
                s,
                v
            ) == theCCExchangeReq.recipientAddress,
            "CCExchangeRouter: invalid signature"
        );

        bool result;
        uint[] memory amounts;

        address _exchangeConnector = exchangeConnector[theCCExchangeReq.appId];

        (result, amounts) = IExchangeConnector(_exchangeConnector).swap(
            theCCExchangeReq.remainedInputAmount,
            theOutputAmount,
            theCCExchangeReq.path,
            address(this),
            theDeadline,
            true
        );

        require(result, "CCExchangeRouter: swap failed");


        // FIXME: add all requirement
        ITeleBTC(theCCExchangeReq.path[1]).approve(
            across, 
            amounts[amounts.length-1]
        );

        ccExchangeRequests[theTxId].isTransferedToEth = true;

        bytes memory nullData;

        SpokePoolInterface(across).deposit(
            theCCExchangeReq.recipientAddress,
            theCCExchangeReq.path[1],
            amounts[amounts.length-1],
            // eth chain id
            1,
            // FIXME: decide relayer percentage fee to be updatable or not
            1000000,
            uint32(block.timestamp),
            nullData,
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );

        return true;
    }
}
