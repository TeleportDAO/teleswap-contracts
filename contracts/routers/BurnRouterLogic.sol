// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "../erc20/interfaces/ITeleBTC.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../libraries/BurnRouterLib.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./BurnRouterStorageV2.sol";

contract BurnRouterLogic is BurnRouterStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable, BurnRouterStorageV2 {
    
    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0))
            revert ZeroAddress();
        _;
    }

    modifier onlyOracle(address _networkFeeOracle) {
        require(_networkFeeOracle == bitcoinFeeOracle, "BurnRouterLogic: not oracle");
        _;
    }

    /// @notice Handles cross-chain burn requests
    /// @param _startingBlockNumber Requests that are included in a block older 
    ///                             than _startingBlockNumber cannot be executed
    /// @param _relay Address of relay contract
    /// @param _lockers Address of lockers contract
    /// @param _treasury Address of the treasury of the protocol
    /// @param _teleBTC Address of teleBTC contract
    /// @param _transferDeadline of sending BTC to user (aster submitting a burn request)
    /// @param _protocolPercentageFee Percentage of tokens that user pays to protocol for burning
    /// @param _slasherPercentageReward Percentage of tokens that slasher receives after slashing a locker
    /// @param _networkFee Fee of submitting a transaction on Network
    function initialize(
        uint _startingBlockNumber,
        address _relay,
        address _lockers,
        address _treasury,
        address _teleBTC,
        uint _transferDeadline,
        uint _protocolPercentageFee,
        uint _slasherPercentageReward,
        uint _networkFee
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        setStartingBlockNumber(_startingBlockNumber);
        setRelay(_relay);
        setLockers(_lockers);
        setTreasury(_treasury);
        setTeleBTC(_teleBTC);
        setTransferDeadline(_transferDeadline);
        setProtocolPercentageFee(_protocolPercentageFee);
        setSlasherPercentageReward(_slasherPercentageReward);
        setNetworkFeeOracle(owner());
        setNetworkFee(_networkFee);
    }

    receive() external payable {}

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice Returns true is request has been processed
    /// @param _lockerTargetAddress Locker address on the target chain
    /// @param _index the request for the locker
    function isTransferred(
        address _lockerTargetAddress,
        uint _index
    ) external view override returns (bool) {
        return burnRequests[_lockerTargetAddress][_index].isTransferred;
    }

    /// @notice Setter for starting block number
    function setStartingBlockNumber(uint _startingBlockNumber) public override onlyOwner {
        require(
            _startingBlockNumber > startingBlockNumber,
            "BurnRouterLogic: low startingBlockNumber"
        );
        startingBlockNumber = _startingBlockNumber;
    }

    /// @notice Updates relay contract address
    /// @dev Only owner can call this
    /// @param _relay The new relay contract address
    function setRelay(address _relay) public override onlyOwner nonZeroAddress(_relay) {
        emit NewRelay(relay, _relay);
        relay = _relay;
    }

    /// @notice Updates lockers contract address
    /// @dev Only owner can call this
    /// @param _lockers The new lockers contract address
    function setLockers(address _lockers) public override onlyOwner nonZeroAddress(_lockers) {
        emit NewLockers(lockers, _lockers);
        lockers = _lockers;
    }

    /// @notice Updates teleBTC contract address
    /// @dev Only owner can call this
    /// @param _teleBTC The new teleBTC contract address
    function setTeleBTC(address _teleBTC) public override onlyOwner nonZeroAddress(_teleBTC) {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
    }

    /// @notice Updates protocol treasury address
    /// @dev Only owner can call this
    /// @param _treasury The new treasury address
    function setTreasury(address _treasury) public override onlyOwner nonZeroAddress(_treasury) {
        emit NewTreasury(treasury, _treasury);
        treasury = _treasury;
    }

    /// @notice Updates deadline of executing burn requests
    /// @dev Only owner can call this
    ///      Deadline should be greater than relay finalization parameter
    /// @param _transferDeadline The new transfer deadline
    function setTransferDeadline(uint _transferDeadline) public override {
        uint _finalizationParameter = BurnRouterLib.finalizationParameter(relay);
        require(
            _msgSender() == owner() || transferDeadline < _finalizationParameter, 
            "BurnRouterLogic: no permit"
        );
        // Gives lockers enough time to pay cc burn requests
        require(_transferDeadline > _finalizationParameter, "BurnRouterLogic: low deadline");
        emit NewTransferDeadline(transferDeadline, _transferDeadline);
        transferDeadline = _transferDeadline;
    }

    /// @notice Updates protocol percentage fee for burning tokens
    /// @dev Only owner can call this
    /// @param _protocolPercentageFee The new protocol percentage fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) public override onlyOwner {
        require(MAX_PROTOCOL_FEE >= _protocolPercentageFee, "BurnRouterLogic: invalid fee");
        emit NewProtocolPercentageFee(protocolPercentageFee, _protocolPercentageFee);
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice Updates slasher percentage reward for disputing lockers
    /// @dev Only owner can call this
    /// @param _slasherPercentageReward The new slasher percentage reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) public override onlyOwner {
        require(MAX_SLASHER_REWARD >= _slasherPercentageReward, "BurnRouterLogic: invalid reward");
        emit NewSlasherPercentageFee(slasherPercentageReward, _slasherPercentageReward);
        slasherPercentageReward = _slasherPercentageReward;
    }

    /// @notice Updates Bitcoin oracle
    /// @dev Only owner can call this
    /// @param _networkFeeOracle Address of oracle who can update burn fee
    function setNetworkFeeOracle(address _networkFeeOracle) public override onlyOwner {
        emit NewNetworkFeeOracle(bitcoinFeeOracle, _networkFeeOracle);
        bitcoinFeeOracle = _networkFeeOracle;
    }

    /// @notice Updates Bitcoin transaction fee
    /// @dev Only owner can call this
    /// @param _networkFee The new Bitcoin transaction fee
    function setNetworkFee(uint _networkFee) public override onlyOracle(msg.sender) {
        emit NewNetworkFee(bitcoinFee, _networkFee);
        bitcoinFee = _networkFee;
    }

    /// @notice                             Setter for third party address
    /// @dev                                Only owner can call this
    /// @param _thirdPartyAddress           third party address
    function setThirdPartyAddress(uint _thirdPartyId, address _thirdPartyAddress) public override onlyOwner {
        emit NewThirdPartyAddress(_thirdPartyId, thirdPartyAddress[_thirdPartyId], _thirdPartyAddress);
        thirdPartyAddress[_thirdPartyId] = _thirdPartyAddress;
    }

    /// @notice                             Setter for third party fee
    /// @dev                                Only owner can call this
    /// @param _thirdPartyFee               third party fee
    function setThirdPartyFee(uint _thirdPartyId, uint _thirdPartyFee) public override onlyOwner {
        emit NewThirdPartyFee(_thirdPartyId, thirdPartyFee[_thirdPartyId], _thirdPartyFee);
        thirdPartyFee[_thirdPartyId] = _thirdPartyFee;
    }

    /// @notice Records users burn request
    /// @dev After submitting the burn request, Locker has a limited time
    ///      to send BTC and provide burn proof
    /// @param _amount of teleBTC that user wants to burn
    /// @param _userScript User script hash
    /// @param _scriptType User script type
    /// @param _lockerLockingScript	of locker that should execute the burn request
    /// @param thirdParty Third party id 
    /// @return Amount of BTC that user receives
    function unwrap(
        uint _amount,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        uint thirdParty
    ) external nonReentrant override returns (uint) {
        // Transfers user's teleBTC to contract
        require(
            ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), _amount),
            "BurnRouterLogic: transferFrom failed"
        );

        (uint burntAmount) = _unwrap(
            teleBTC,
            _amount,
            _amount, 
            _userScript, 
            _scriptType, 
            _lockerLockingScript,
            thirdParty
        );

        return burntAmount;

    }

    /// @notice Exchanges input token for teleBTC then burns it
    /// @dev After exchanging, rest of the process is similar to ccBurn
    /// @param _exchangeConnector Address of exchange connectBurnRouterLogicor to be used
    /// @param _amounts [inputTokenAmount, teleBTCAmount]
    /// @param _isFixedToken True if input token amount is fixed
    /// @param _path of exchanging inputToken to teleBTC
    /// @param _deadline of exchanging
    /// @param thirdParty Third party id 
    /// @return Amount of BTC that user receives
    function swapAndUnwrap(
        address _exchangeConnector,
        uint[] calldata _amounts,
        bool _isFixedToken,
        address[] calldata _path,
        uint256 _deadline, 
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        uint thirdParty
    ) external nonReentrant override returns (uint) {
        uint _exchangedTeleBTC = _exchange(
            _exchangeConnector,
            _amounts,
            _isFixedToken,
            _path,
            _deadline
        );

        return _swapAndUnwrap(
            _amounts[0],
            _path[0],
            _exchangedTeleBTC,
            _userScript,
            _scriptType,
            _lockerLockingScript,
            thirdParty
        );
    }

    /// @notice Checks the correctness of burn proof (which is a Bitcoin tx)
    /// @dev Makes isTransferred flag true for the paid requests
    /// @param _version Version of the Bitcoin tx
    /// @param _vin Inputs of the Bitcoin tx
    /// @param _vout Outputs of the Bitcoin tx
    /// @param _locktime Lock time of the Bitcoin tx
    /// @param _blockNumber Height of the block containing the Bitcoin tx
    /// @param _intermediateNodes Merkle inclusion proof for the Bitcoin tx
    /// @param _index Index of the Bitcoin tx the block
    /// @param _lockerLockingScript Locker's locking script that this burn request belongs to
    /// @param _burnReqIndexes Indexes of requests that locker wants to provide proof for them
    /// @param _voutIndexes Indexes of outputs that were used to pay burn requests. 
    ///                     _voutIndexes[i] belongs to _burnReqIndexes[i]
    function burnProof(
        bytes4 _version,
        bytes memory _vin,
        bytes memory _vout,
        bytes4 _locktime,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index,
        bytes memory _lockerLockingScript,
        uint[] memory _burnReqIndexes,
        uint[] memory _voutIndexes
    ) external payable nonReentrant override returns (bool) {
        BurnRouterLib.burnProofHelper(
            _blockNumber,
            startingBlockNumber,
            _locktime,
            lockers,
            _lockerLockingScript,
            _burnReqIndexes.length,
            _voutIndexes.length
        );

        // Checks inclusion of transaction
        bytes32 txId = BitcoinHelper.calculateTxId(_version, _vin, _vout, _locktime);
        require(
            BurnRouterLib.isConfirmed(
                relay,
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "BurnRouterLogic: not finalized"
        );

        // Get the target address of the locker from its locking script
        address _lockerTargetAddress = ILockersManager(lockers).getLockerTargetAddress(_lockerLockingScript);

        // Checks the paid burn requests
        uint paidOutputCounter = _checkPaidBurnRequests(
            txId,
            _blockNumber,
            _lockerTargetAddress,
            _vout,
            _burnReqIndexes,
            _voutIndexes
        );

        /*
            Checks if there is an output that goes back to the locker
            Sets isUsedAsBurnProof of txId true if all the outputs (except one) were used to pay cc burn requests
        */
        BurnRouterLib.updateIsUsedAsBurnProof(
            isUsedAsBurnProof, 
            paidOutputCounter, 
            _vout, 
            _lockerLockingScript, 
            txId
        );

        return true;
    }

    /// @notice Slashes a locker if did not pay a cc burn request before its deadline
    /// @param _lockerLockingScript Locker's locking script that the unpaid request belongs to
    /// @param _indices Indices of requests that their deadline has passed
    function disputeBurn(
        bytes calldata _lockerLockingScript,
        uint[] memory _indices
    ) external nonReentrant onlyOwner override {
        // Checks if the locking script is valid
        require(
            ILockersManager(lockers).isLocker(_lockerLockingScript),
            "BurnRouterLogic: not locker"
        );

        // Get the target address of the locker from its locking script
        address _lockerTargetAddress = ILockersManager(lockers).getLockerTargetAddress(_lockerLockingScript);

        // Goes through provided indexes of burn requests to see if locker should be slashed
        for (uint i = 0; i < _indices.length; i++) {

            BurnRouterLib.disputeBurnHelper(
                burnRequests,
                _lockerTargetAddress,
                _indices[i],
                transferDeadline,
                BurnRouterLib.lastSubmittedHeight(relay),
                startingBlockNumber
            );

            // Slashes locker and sends the slashed amount to the user
            ILockersManager(lockers).slashIdleLocker(
                _lockerTargetAddress,
                burnRequests[_lockerTargetAddress][_indices[i]].amount*slasherPercentageReward/MAX_SLASHER_REWARD, // Slasher reward
                _msgSender(), // Slasher address
                burnRequests[_lockerTargetAddress][_indices[i]].amount,
                burnRequests[_lockerTargetAddress][_indices[i]].sender // User address
            );

            emit BurnDispute(
                burnRequests[_lockerTargetAddress][_indices[i]].sender,
                _lockerTargetAddress,
                _lockerLockingScript,
                burnRequests[_lockerTargetAddress][_indices[i]].requestIdOfLocker
            );
        }
    }

    /// @notice Slashes a locker if they issue a tx that doesn't match any burn request
    /// @dev Input tx is a malicious tx which shows that locker spent BTC
    ///      Output tx is the tx that was spent by locker in input tx
    ///      Output tx shows money goes to locker
    ///      Input tx shows locker steals the funds
    /// @param _lockerLockingScript Suspicious locker's locking script
    /// @param _versions Versions of input and output tx
    /// @param _inputVin Inputs of the malicious transaction
    /// @param _inputVout Outputs of the malicious transaction
    /// @param _outputVin Inputs of the spent transaction
    /// @param _outputVout Outputs of the spent transaction
    /// @param _locktimes Locktimes of input and output tx
    /// @param _inputIntermediateNodes Merkle inclusion proof for the malicious transaction
    /// @param _indexesAndBlockNumbers Indices of malicious input in input tx, 
    ///                                input tx in block and block number of input tx
    function disputeLocker(
        bytes memory _lockerLockingScript,
        bytes4[] memory _versions, // [inputTxVersion, outputTxVersion]
        bytes memory _inputVin,
        bytes memory _inputVout,
        bytes memory _outputVin,
        bytes memory _outputVout,
        bytes4[] memory _locktimes, // [inputTxLocktime, outputTxLocktime]
        bytes memory _inputIntermediateNodes,
        uint[] memory _indexesAndBlockNumbers // [inputIndex, inputTxIndex, inputTxBlockNumber]
    ) external payable nonReentrant onlyOwner override {

        // Finds input tx id and checks its inclusion
        bytes32 _inputTxId = BitcoinHelper.calculateTxId(_versions[0], _inputVin, _inputVout, _locktimes[0]);

        BurnRouterLib.disputeAndSlashLockerHelper(
            lockers,
            _lockerLockingScript,
            _versions,
            [_inputVin, _outputVin, _outputVout],
            isUsedAsBurnProof,
            transferDeadline,
            relay,
            startingBlockNumber,
            _inputTxId,
            _locktimes,
            _inputIntermediateNodes,
            _indexesAndBlockNumbers
        );     

        // Slashes locker
        _slashLockerForDispute(
            _inputVout,
            _lockerLockingScript,
            _inputTxId,
            _indexesAndBlockNumbers[2] // Block number
        );
    }

    /// @notice Burns the exchanged teleBTC
    function _swapAndUnwrap(
        uint _inputAmount,
        address _inputToken,
        uint _exchangedTeleBTC, 
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        uint thirdParty
    ) private returns (uint) {
        (uint burntAmount) = _unwrap(
            _inputToken,
            _inputAmount,
            _exchangedTeleBTC, 
            _userScript, 
            _scriptType, 
            _lockerLockingScript,
            thirdParty
        );

        return burntAmount;
    }

    /// @notice Burns teleBTC and records the burn request
    /// @return _burntAmount Amount of BTC that user receives
    function _unwrap(
        address _inputToken,
        uint _inputAmount,
        uint _amount,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        uint thirdParty
    ) private returns (uint _burntAmount) {
        // Checks validity of user script
        BurnRouterLib.checkScriptTypeAndLocker(_userScript, _scriptType, lockers, _lockerLockingScript);

        // Gets the target address of locker
        (uint remainingAmount, uint protocolFee, uint thirdPartyFee) = _getFees(_amount, thirdParty);

        // Burns remained teleBTC
        ITeleBTC(teleBTC).approve(lockers, remainingAmount);

        // Reduces the Bitcoin fee to find the amount that user receives (called burntAmount)
        _burntAmount = (ILockersManager(lockers).burn(_lockerLockingScript, remainingAmount)); 
        
        address _lockerTargetAddress = ILockersManager(lockers).getLockerTargetAddress(_lockerLockingScript);

        _saveBurnRequest(
            _amount,
            _burntAmount,
            _userScript,
            _scriptType,
            BurnRouterLib.lastSubmittedHeight(relay),
            _lockerTargetAddress
        );
        
        address inputToken = _inputToken;
        uint[3] memory amounts = [_inputAmount, _amount, _burntAmount];
        uint[4] memory fees = [bitcoinFee, remainingAmount - _burntAmount, protocolFee, thirdPartyFee];

        emit NewUnwrap(
            _userScript, 
            _scriptType,
            _lockerTargetAddress, 
            _msgSender(),
            burnRequests[_lockerTargetAddress][burnRequests[_lockerTargetAddress].length - 1].requestIdOfLocker, // index of request
            burnRequests[_lockerTargetAddress][burnRequests[_lockerTargetAddress].length - 1].deadline,
            thirdParty,
            inputToken,
            amounts,
            fees
        );
    }

    /// @notice Exchanges input token for teleBTC
    /// @dev Reverts if exchange fails
    /// @return Amount of exchanged teleBTC 
    function _exchange(
        address _exchangeConnector,
        uint[] calldata _amounts,
        bool _isFixedToken,
        address[] calldata _path,
        uint256 _deadline
    ) private returns (uint) {
        require(_path[_path.length - 1] == teleBTC, "BurnRouterLogic: invalid path");
        require(_amounts.length == 2, "BurnRouterLogic: wrong amounts");
        // Transfers user's input token

        IERC20(_path[0]).transferFrom(_msgSender(), address(this), _amounts[0]);

        IERC20(_path[0]).approve(_exchangeConnector, _amounts[0]); // Gives approval to exchange connector
        (bool result, uint[] memory amounts) = IExchangeConnector(_exchangeConnector).swap(
            _amounts[0], 
            _amounts[1], 
            _path, 
            address(this), 
            _deadline, 
            _isFixedToken
        );
        require(result, "BurnRouterLogic: exchange failed");
        return amounts[amounts.length - 1]; // Amount of exchanged teleBTC
    }

    /// @notice Slashes the malicious locker
    /// @param _inputVout Inputs of the malicious transaction
    /// @param _lockerLockingScript Malicious locker's locking script
    /// @param _inputTxId Tx id of the malicious transaction
    /// @param _inputBlockNumber Block number of the malicious transaction
    function _slashLockerForDispute(
        bytes memory _inputVout,
        bytes memory _lockerLockingScript,
        bytes32 _inputTxId,
        uint _inputBlockNumber
    ) private {

        // Finds total value of malicious transaction
        uint totalValue = BitcoinHelper.parseOutputsTotalValue(_inputVout);

        // Gets the target address of the locker from its Bitcoin address
        address _lockerTargetAddress = ILockersManager(lockers).getLockerTargetAddress(_lockerLockingScript);

        ILockersManager(lockers).slashThiefLocker(
            _lockerTargetAddress,
            totalValue*slasherPercentageReward/MAX_SLASHER_REWARD, // Slasher reward
            _msgSender(), // Slasher address
            totalValue
        );

        // Emits the event
        emit LockerDispute(
            _lockerTargetAddress,
            _lockerLockingScript,
            _inputBlockNumber,
            _inputTxId,
            totalValue + totalValue*slasherPercentageReward/MAX_SLASHER_REWARD
        );
    }

    /// @notice Checks the burn requests that get paid by this transaction
    /// @param _paidBlockNumber Block number in which locker paid the burn request
    /// @param _lockerTargetAddress Address of the locker on the target chain
    /// @param _vout Outputs of a transaction
    /// @param _burnReqIndexes Indexes of requests that locker provides proof for them
    /// @param _voutIndexes Indexes of outputs that were used to pay burn requests
    /// @return paidOutputCounter Number of executed burn requests
    function _checkPaidBurnRequests(
        bytes32 txId,
        uint _paidBlockNumber,
        address _lockerTargetAddress,
        bytes memory _vout,
        uint[] memory _burnReqIndexes,
        uint[] memory _voutIndexes
    ) private returns (uint paidOutputCounter) {
        uint parsedAmount;
        /*
            Below variable is for checking that every output in vout (except one)
            is related to a cc burn request so that we can
            set "isUsedAsBurnProof = true" for the whole txId
        */
        paidOutputCounter = 0;

        uint tempVoutIndex;

        for (uint i = 0; i < _burnReqIndexes.length; i++) {

            // prevent from sending repeated vout indexes
            if (i == 0) {
                tempVoutIndex = _voutIndexes[i];
            } else {
                require(
                    _voutIndexes[i] > tempVoutIndex,
                    "BurnRouterLogic: un-sorted vout indexes"
                );

                tempVoutIndex = _voutIndexes[i];
            }

            uint _burnReqIndex = _burnReqIndexes[i];
            // Checks that the request has not been paid and its deadline has not passed
            if (
                !burnRequests[_lockerTargetAddress][_burnReqIndex].isTransferred &&
                burnRequests[_lockerTargetAddress][_burnReqIndex].deadline >= _paidBlockNumber
            ) {

                parsedAmount = BitcoinHelper.parseValueFromSpecificOutputHavingScript(
                    _vout,
                    _voutIndexes[i],
                    burnRequests[_lockerTargetAddress][_burnReqIndex].userScript,
                    burnRequests[_lockerTargetAddress][_burnReqIndex].scriptType
                );

                // Checks that locker has sent required teleBTC amount
                if (burnRequests[_lockerTargetAddress][_burnReqIndex].burntAmount == parsedAmount) {
                    burnRequests[_lockerTargetAddress][_burnReqIndex].isTransferred = true;
                    paidOutputCounter = paidOutputCounter + 1;
                    emit PaidUnwrap(
                        _lockerTargetAddress,
                        burnRequests[_lockerTargetAddress][_burnReqIndex].requestIdOfLocker,
                        txId,
                        _voutIndexes[i]
                    );
                }
            }
        }
    }

    /// @notice Records burn request of user
    /// @param _amount Amount of wrapped token that user wants to burn
    /// @param _burntAmount Amount of wrapped token that actually gets burnt after deducting fees from the original value (_amount)
    /// @param _userScript User's Bitcoin script type
    /// @param _lastSubmittedHeight Last block header height submitted on the relay contract
    /// @param _lockerTargetAddress Locker's target chain address that the request belongs to
    function _saveBurnRequest(
        uint _amount,
        uint _burntAmount,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        uint _lastSubmittedHeight,
        address _lockerTargetAddress
    ) private {
        burnRequest memory request;
        request.amount = _amount;
        request.burntAmount = _burntAmount;
        request.sender = _msgSender();
        request.userScript = _userScript;
        request.scriptType = _scriptType;
        request.deadline = _lastSubmittedHeight + transferDeadline;
        request.isTransferred = false;
        request.requestIdOfLocker = burnRequestCounter[_lockerTargetAddress];
        burnRequestCounter[_lockerTargetAddress] = burnRequestCounter[_lockerTargetAddress] + 1;
        burnRequests[_lockerTargetAddress].push(request);
    }

    /// @notice Checks inclusion of the transaction in the specified block
    /// @dev Calls the relay contract to check Merkle inclusion proof
    /// @param _amount The amount to be burnt
    /// @return remainingAmount amount after reducing fees
    /// @return _protocolFee fee of protocol
    /// @return _thirdPartyFee fee of third party
    function _getFees(
        uint _amount,
        uint _thirdParty
    ) private returns (uint remainingAmount, uint _protocolFee, uint _thirdPartyFee) {
        // Calculates protocol fee
        _protocolFee = _amount * protocolPercentageFee / MAX_PROTOCOL_FEE;
        _thirdPartyFee = _amount * thirdPartyFee[_thirdParty] / MAX_PROTOCOL_FEE;
        // note: to avoid dust, we require _amount to be greater than (2  * networkFee)
        require(_amount > _protocolFee + 2 * bitcoinFee, "BurnRouterLogic: low amount");
       
        remainingAmount = _amount - _protocolFee - _thirdPartyFee - bitcoinFee;

        // Transfers protocol fee
        if (_protocolFee > 0) {
            require(
                ITeleBTC(teleBTC).transfer(treasury, _protocolFee),
                "BurnRouterLogic: fee transfer failed"
            );
        }

        // Transfers third party fee
        if (_thirdPartyFee > 0) {
            require(
                ITeleBTC(teleBTC).transfer(thirdPartyAddress[_thirdParty], _thirdPartyFee),
                "BurnRouterLogic: third party fee transfer failed"
            );
        }

        if (bitcoinFee > 0) {
            require(
                ITeleBTC(teleBTC).transfer(lockers, bitcoinFee),
                "BurnRouterLogic: network fee transfer failed"
            );
        }
    }

}