// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./RuneRouterStorage.sol";
import "./RuneRouterLib.sol";
import "../erc20/interfaces/IRune.sol";
import "../swap_connectors/interfaces/IExchangeConnector.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract RuneRouterLogic is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    RuneRouterStorage
{
    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "RuneRouterLogic: zero address");
        _;
    }

    /// @notice Initialize the contract
    /// @param _startingBlockNumber Requests included in a block older than _startingBlockNumber cannot be processed
    /// @param _protocolPercentageFee Percentage amount of protocol fee (min: %0.01)
    /// @param _chainId Id of the underlying chain
    /// @param _relay Bitcoin bridge address which validates Bitcoin tx
    /// @param _treasury Address of treasury that collects protocol fees
    function initialize(
        uint _startingBlockNumber,
        uint _protocolPercentageFee,
        uint _chainId,
        address _relay,
        address _locker,
        bytes memory _lockerLockingScript,
        ScriptTypes _lockerScriptType,
        address _teleporter,
        address _treasury
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        chainId = _chainId;
        setStartingBlockNumber(_startingBlockNumber);
        setProtocolPercentageFee(_protocolPercentageFee);
        setRelay(_relay);
        setLocker(_locker);
        setLockerLockingScript(_lockerLockingScript, _lockerScriptType);
        setTeleporter(_teleporter);
        setTreasury(_treasury);
    }

    receive() external payable {}

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice Check if the wrap request has been processed before
    /// @param _txId of the request on Bitcoin
    function isWrapRequestProcessed(
        bytes32 _txId
    ) external view override returns (bool) {
        return runeWrapRequests[_txId].isUsed ? true : false;
    }

    /// @notice Check if the unwrap request has been processed before
    function isUnwrapRequestProcessed(
        uint _reqIdx
    ) external view override returns (bool) {
        return runeUnwrapRequests[_reqIdx].isProcessed ? true : false;
    }

    /// @notice Setter for locker locking script
    function setLockerLockingScript(
        bytes memory _lockerLockingScript,
        ScriptTypes _lockerScriptType
    ) public override onlyOwner {
        lockerLockingScript = _lockerLockingScript;
        lockerScriptType = _lockerScriptType;
    }

    /// @notice Setter for starting block number
    function setStartingBlockNumber(
        uint _startingBlockNumber
    ) public override onlyOwner {
        require(
            _startingBlockNumber > startingBlockNumber,
            "RuneRouterLogic: low number"
        );
        startingBlockNumber = _startingBlockNumber;
    }

    /// @notice Setter for protocol percentage fee
    function setProtocolPercentageFee(
        uint _protocolPercentageFee
    ) public override onlyOwner {
        require(
            MAX_PROTOCOL_FEE >= _protocolPercentageFee,
            "RuneRouterLogic: out of range"
        );
        emit NewProtocolPercentageFee(
            protocolPercentageFee,
            _protocolPercentageFee
        );
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice Setter for Bitcoin relay
    function setRelay(
        address _relay
    ) public override nonZeroAddress(_relay) onlyOwner {
        emit NewRelay(relay, _relay);
        relay = _relay;
    }

    /// @notice Setter for locker
    function setLocker(
        address _locker
    ) public override nonZeroAddress(_locker) onlyOwner {
        emit NewLocker(locker, _locker);
        locker = _locker;
    }

    /// @notice Setter for teleporter
    function setTeleporter(
        address _teleporter
    ) public override nonZeroAddress(_teleporter) onlyOwner {
        emit NewTeleporter(teleporter, _teleporter);
        teleporter = _teleporter;
    }

    /// @notice Setter for treasury
    function setTreasury(
        address _treasury
    ) public override nonZeroAddress(_treasury) onlyOwner {
        emit NewTreasury(treasury, _treasury);
        treasury = _treasury;
    }

    /// @notice Set exchange connector for appId
    /// @dev If address(0) is set for an appId, that appId is inactive
    function setExchangeConnector(
        uint _appId,
        address _exchangeConnector
    ) external override onlyOwner {
        emit SetExchangeConnector(_appId, _exchangeConnector);
        exchangeConnector[_appId] = _exchangeConnector;
    }

    /// @notice Setter for third party address and fee
    function setThirdParty(
        uint _thirdPartyId,
        address _thirdPartyAddress,
        uint _thirdPartyFee
    ) external override onlyOwner {
        emit ThirdPartyInfoUpdated(
            _thirdPartyId,
            thirdParties[_thirdPartyId].thirdPartyAddress,
            thirdParties[_thirdPartyId].thirdPartyFee,
            _thirdPartyAddress,
            _thirdPartyFee
        );

        thirdParty memory _thirdParty;
        _thirdParty.thirdPartyAddress = _thirdPartyAddress;
        _thirdParty.thirdPartyFee = _thirdPartyFee;
        thirdParties[_thirdPartyId] = _thirdParty;
    }

    /// @notice Setter for chainId
    function setChainId(uint _chainId) public override onlyOwner {
        chainId = _chainId;
    }

    /// @notice Deploy wrapped Rune token contract
    /// @dev We assign tokenId to a supported Rune
    /// @param _runeId Real rune id
    /// @param _internalId Internal id
    function addRune(
        string memory _name,
        string memory _symbol,
        string memory _runeId,
        uint8 _decimal,
        uint _internalId
    ) external override onlyOwner {
        // Cannot assign to a used tokenId
        require(
            supportedRunes[_internalId] == address(0),
            "RuneRouterLogic: used id"
        );

        // Deploy logic contract
        address wRuneLogic = RuneRouterLib.addRuneHelper();

        bytes memory nullData;
        WRuneProxy _wRuneProxy = new WRuneProxy(wRuneLogic, owner(), nullData);
        // ^^ We set current owner as the proxy admin

        address wRuneProxy = address(_wRuneProxy);

        // Initialize proxy (logic owner is this contract)
        WRuneLogic(wRuneProxy).initialize(_name, _symbol, _decimal);

        // Add this contract as minter and burner
        WRuneLogic(wRuneProxy).addMinter(address(this));
        WRuneLogic(wRuneProxy).addBurner(address(this));

        supportedRunes[_internalId] = wRuneProxy;
        internalIds[wRuneProxy] = _internalId;
        runeIds[wRuneProxy] = _runeId;

        emit NewRune(
            _name,
            _symbol,
            _runeId,
            _decimal,
            _internalId,
            wRuneProxy,
            wRuneLogic
        );
    }

    /// @notice Remove support of a wrapped RUNE token
    function removeRune(uint _internalId) external override onlyOwner {
        address wrappedRune = supportedRunes[_internalId];
        require(wrappedRune != address(0), "RuneRouterLogic: no token");
        emit RuneRemoved(_internalId, wrappedRune);
        delete runeIds[wrappedRune];
        delete internalIds[wrappedRune];
        delete supportedRunes[_internalId];
    }

    /// @notice Setter for unwrap fee
    /// @dev This fee is taken for unwrap requests to cover the Bitcoin network fee
    function setUnwrapFee(uint _newFee) external override onlyOwner {
        emit UnwrapFeeUpdated(unwrapFee, _newFee);
        unwrapFee = _newFee;
    }

    /// @notice Process wrap Rune request
    /// @dev Locker submits wrap requests to this function for:
    ///      1) Checking tx inclusion
    ///      2) Extracting wrap request info from the OP_RETURN output
    ///      3) Exchanging wrapped Rune (if request is wrap & exchange) using the path
    ///         provided by the locker
    /// @param _version of Bitcoin tx
    /// @param _vin Tx inputs
    /// @param _vout Tx outputs
    /// @param _locktime Tx locktime
    /// @param _blockNumber that includes the tx
    /// @param _intermediateNodes Merkle proof for tx
    /// @param _index of tx in the block
    function wrapRune(
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes calldata _intermediateNodes,
        uint _index,
        address[] memory _path
    ) external payable override nonReentrant {
        require(_msgSender() == teleporter, "RuneRouterLogic: not teleporter");

        // Find txId and check its inclusion
        bytes32 txId = RuneRouterLib.checkTx(
            startingBlockNumber,
            relay,
            _version,
            _vin,
            _vout,
            _locktime,
            _blockNumber,
            _intermediateNodes,
            _index
        );

        // Extract information from the request & find fees and remaining amount
        (
            uint remainingAmount,
            fees memory fee,
            address _thirdPartyAddress,
            address wrappedRune
        ) = RuneRouterLib.wrapHelper(
                chainId,
                _vout,
                txId,
                runeWrapRequests,
                supportedRunes,
                thirdParties,
                protocolPercentageFee,
                lockerPercentageFee
            );

        // Mint wrapped tokens
        IRune(wrappedRune).mint(
            address(this),
            fee.protocolFee +
                fee.lockerFee +
                fee.thirdPartyFee +
                remainingAmount
        );

        // Send protocol, locker and third party fee
        IRune(wrappedRune).transfer(treasury, fee.protocolFee);

        IRune(wrappedRune).transfer(locker, fee.lockerFee);

        if (_thirdPartyAddress != address(0)) {
            IRune(wrappedRune).transfer(_thirdPartyAddress, fee.thirdPartyFee);
        }

        runeWrapRequest memory request = runeWrapRequests[txId];

        if (request.appId == 0) {
            // This is a wrap request
            // Transfer wrapped tokens to user
            IRune(wrappedRune).transfer(
                request.recipientAddress,
                remainingAmount
            );

            emit NewRuneWrap(
                request.recipientAddress,
                remainingAmount,
                wrappedRune,
                fee,
                _thirdPartyAddress,
                txId
            );
        } else {
            // This is wrap & exchange request
            // Check exchange path provided by locker
            require(
                _path[0] == request.inputToken &&
                    _path[_path.length - 1] == request.outputToken,
                "RuneRouterLogic: wrong path"
            );

            (bool result, uint[] memory amounts) = _swap(
                request.appId,
                request.recipientAddress,
                remainingAmount,
                request.outputAmount,
                _path
            );

            if (result) {
                emit NewRuneWrapAndSwap(
                    request.recipientAddress,
                    remainingAmount,
                    wrappedRune,
                    amounts[amounts.length - 1],
                    request.outputToken,
                    fee,
                    _thirdPartyAddress,
                    txId
                );
            } else {
                emit FailedRuneWrapAndSwap(
                    request.recipientAddress,
                    remainingAmount,
                    wrappedRune,
                    request.outputAmount,
                    request.outputToken,
                    fee,
                    _thirdPartyAddress,
                    txId
                );

                // Transfer wrapped tokens to user
                IRune(wrappedRune).transfer(
                    request.recipientAddress,
                    remainingAmount
                );
            }
        }
    }

    /// @notice Process user rune unwrap request
    /// @dev For unwrap requests (not swap & unwrap), pass _appId,
    ///      _inputAmount and _path ZERO
    /// @param _amount of WRune that user wants to burn
    /// @param _userScript User script hash
    /// @param _scriptType User script type
    function unwrapRune(
        uint _thirdPartyId,
        uint _internalId,
        uint _amount,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        uint _appId,
        uint _inputAmount,
        address[] memory _path
    ) external payable override nonReentrant {
        address token = supportedRunes[_internalId];
        require(token != address(0), "RuneRouterLogic: not supported");
        require(msg.value == unwrapFee, "RuneRouterLogic: wrong fee");

        if (_path.length != 0) {
            // This is a swap and unwrap request
            // Transfer user's tokens to contract
            IRune(_path[0]).transferFrom(
                msg.sender,
                address(this),
                _inputAmount
            );

            (bool result, uint[] memory amounts) = _swap(
                _appId,
                address(this),
                _inputAmount,
                _amount,
                _path
            );
            require(result, "RuneRouterLogic: swap failed");
            _amount = amounts[amounts.length - 1]; // Rune amount that would be burnt
        } else {
            // This is a unwrap request
            // Transfer user's tokens to contract
            require(
                IRune(token).transferFrom(_msgSender(), address(this), _amount),
                "RuneRouterLogic: transfer failed"
            );
        }

        (
            fees memory fee,
            address thirdPartyAddress,
            uint remainingAmount
        ) = _unwrapRune(
                _thirdPartyId,
                token,
                _amount,
                _userScript,
                _scriptType
            );

        if (_path.length == 0) {
            emit NewRuneUnwrap(
                _msgSender(),
                _userScript,
                _scriptType,
                token,
                _amount,
                remainingAmount,
                fee,
                unwrapFee,
                thirdPartyAddress,
                runeUnwrapRequests.length - 1
            );
        } else {
            emit NewRuneSwapAndUnwrap(
                _msgSender(),
                _userScript,
                _scriptType,
                _inputAmount,
                _path[0],
                _amount,
                remainingAmount,
                token,
                fee,
                unwrapFee,
                thirdPartyAddress,
                runeUnwrapRequests.length - 1
            );
        }
    }

    /// @notice Check proof of unwraping Runes
    function unwrapProofRune(
        bytes4 _version,
        bytes memory _vin,
        bytes memory _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index,
        uint[] memory _reqIndexes
    ) external payable override nonReentrant {
        require(_msgSender() == locker, "RuneRouterLogic: not locker");

        RuneRouterLib.checkTx(
            startingBlockNumber,
            relay,
            _version,
            _vin,
            _vout,
            _locktime,
            _blockNumber,
            _intermediateNodes,
            _index
        );

        for (uint i = 0; i < _reqIndexes.length; i++) {
            require(
                !runeUnwrapRequests[_reqIndexes[i]].isProcessed,
                "RuneRouterLogic: already processed"
            );
            runeUnwrapRequests[_reqIndexes[i]].isProcessed = true;
            emit UnwrapRuneProcessed(
                runeUnwrapRequests[_reqIndexes[i]].sender,
                runeUnwrapRequests[_reqIndexes[i]].burntAmount,
                runeUnwrapRequests[_reqIndexes[i]].userScript,
                runeUnwrapRequests[_reqIndexes[i]].scriptType,
                _reqIndexes[i]
            );
        }
    }

    /// @notice Burns wrapped Rune and record the request
    function _unwrapRune(
        uint _thirdPartyId,
        address _token,
        uint _amount,
        bytes memory _userScript,
        ScriptTypes _scriptType
    )
        private
        returns (
            fees memory _fee,
            address _thirdPartyAddress,
            uint _remainingAmount
        )
    {
        // Save unwrap request and get fee and burnt amounts
        (_fee, _thirdPartyAddress, _remainingAmount) = RuneRouterLib
            .unwrapHelper(
                _msgSender(),
                protocolPercentageFee,
                lockerPercentageFee,
                runeUnwrapRequests,
                thirdParties,
                _thirdPartyId,
                _amount,
                _userScript,
                _scriptType
            );

        runeUnwrapCounter++;

        // Send protocol, locker and third party fee
        IRune(_token).transfer(treasury, _fee.protocolFee);
        IRune(_token).transfer(locker, _fee.lockerFee);
        if (_thirdPartyAddress != address(0)) {
            IRune(_token).transfer(_thirdPartyAddress, _fee.thirdPartyFee);
        }

        // Send unwrap fee (in native token) to locker
        Address.sendValue(payable(locker), unwrapFee);

        // Burn remained amount
        IRune(_token).burn(_remainingAmount);
    }

    // Swap tokens using an exchange connector
    function _swap(
        uint _appId,
        address _recipientAddress,
        uint _inputAmount,
        uint _outputAmount,
        address[] memory _path
    ) private returns (bool _result, uint[] memory _amounts) {
        address _exchangeConnector = exchangeConnector[_appId];
        require(
            _exchangeConnector != address(0),
            "RuneRouterLogic: invalid appId"
        );

        IRune(_path[0]).approve(_exchangeConnector, _inputAmount);

        if (IExchangeConnector(_exchangeConnector).isPathValid(_path)) {
            (_result, _amounts) = IExchangeConnector(_exchangeConnector).swap(
                _inputAmount,
                _outputAmount,
                _path,
                _recipientAddress,
                block.timestamp,
                true // Input amount is fixed
            );
        } else {
            _result = false;
        }
    }
}
