// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ICCBurnRouter.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../lockers/interfaces/ILockers.sol";
import "../libraries/BitcoinHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract CCBurnRouter is ICCBurnRouter, Ownable, ReentrancyGuard {

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "CCBurnRouter: address is zero");
        _;
    }

    modifier nonZeroValue(uint _value) {
        require(_value > 0, "CCBurnRouter: value is zero");
        _;
    }

    // Constants
    uint constant MAX_PROTOCOL_FEE = 10000;
    uint constant MAX_SLASHER_REWARD = 100;

    // Public variables
    address public override relay;
    address public override lockers;
    address public override teleBTC;
    address public override treasury;
    uint public override transferDeadline;
    uint public override protocolPercentageFee; // Min amount is %0.01
    uint public override slasherPercentageReward; // Min amount is %1
    uint public override bitcoinFee; // Fee of submitting a tx on Bitcoin
    mapping(address => burnRequest[]) public burnRequests; // Mapping from locker target address to assigned burn requests
    mapping(address => uint) public burnRequestCounter;
    mapping(bytes32 => bool) public override isUsedAsBurnProof; // Mapping that shows a txId has been submitted to pay a burn request

    /// @notice                             Handles cross-chain burn requests
    /// @param _relay                       Address of relay contract
    /// @param _lockers                     Address of lockers contract
    /// @param _treasury                    Address of the treasury of the protocol
    /// @param _transferDeadline            Dealine of sending BTC to user (aster submitting a burn request)
    /// @param _protocolPercentageFee       Percentage of tokens that user pays to protocol for burning
    /// @param _slasherPercentageReward     Percentage of tokens that slasher receives after slashing a locker
    /// @param _bitcoinFee                  Fee of submitting a transaction on Bitcoin
    constructor(
        address _relay,
        address _lockers,
        address _treasury,
        uint _transferDeadline,
        uint _protocolPercentageFee,
        uint _slasherPercentageReward,
        uint _bitcoinFee
    ) {
        relay = _relay;
        lockers = _lockers;
        treasury = _treasury;
        transferDeadline = _transferDeadline;
        protocolPercentageFee = _protocolPercentageFee;
        slasherPercentageReward = _slasherPercentageReward;
        bitcoinFee = _bitcoinFee;
    }

    receive() external payable {}

    /// @notice                         Shows if a burn request has been done or not
    /// @param _lockerTargetAddress		Locker's address on the target chain
    /// @param _index                   The index of the request for the locker
    function isTransferred(
        address _lockerTargetAddress,
        uint _index
    ) external view override returns (bool) {
        return burnRequests[_lockerTargetAddress][_index].isTransferred;
    }

    /// @notice               Changes relay contract address
    /// @dev                  Only owner can call this
    /// @param _relay         The new relay contract address
    function setRelay(address _relay) external nonZeroAddress(_relay) override onlyOwner {
        relay = _relay;
    }

    /// @notice               Changes lockers contract address
    /// @dev                  Only owner can call this
    /// @param _lockers       The new lockers contract address
    function setLockers(address _lockers) external nonZeroAddress(_lockers) override onlyOwner {
        lockers = _lockers;
    }

    /// @notice                 Changes teleBTC contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new teleBTC contract address
    function setTeleBTC(address _teleBTC) external nonZeroAddress(_teleBTC) override onlyOwner {
        teleBTC = _teleBTC;
    }

    /// @notice                     Changes protocol treasury address
    /// @dev                        Only owner can call this
    /// @param _treasury            The new treasury address
    function setTreasury(address _treasury) external nonZeroAddress(_treasury) override onlyOwner {
        treasury = _treasury;
    }

    /// @notice                             Changes deadline of executing burn requests
    /// @dev                                Only owner can call this
    ///                                     Deadline shoudl be greater than relay finalization parameter
    /// @param _transferDeadline            The new transfer deadline
    function setTransferDeadline(uint _transferDeadline) external override onlyOwner {
        uint _finalizationParameter = IBitcoinRelay(relay).finalizationParameter();
        // Gives lockers enough time to pay cc burn requests
        require(_transferDeadline > _finalizationParameter, "CCBurnRouter: transfer deadline is too low");
        transferDeadline = _transferDeadline;
    }

    /// @notice                             Changes protocol percentage fee for burning tokens
    /// @dev                                Only owner can call this
    /// @param _protocolPercentageFee       The new protocol percentage fee
    function setProtocolPercentageFee(uint _protocolPercentageFee) external override onlyOwner {
        require(MAX_PROTOCOL_FEE >= _protocolPercentageFee, "CCBurnRouter: protocol fee is out of range");
        protocolPercentageFee = _protocolPercentageFee;
    }

    /// @notice                            Changes slasher percentage reward for disputing lockers
    /// @dev                               Only owner can call this
    /// @param _slasherPercentageReward    The new slasher percentage reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) external override onlyOwner {
        require(MAX_SLASHER_REWARD >= _slasherPercentageReward, "CCBurnRouter: slasher percentage reward is out of range");
        slasherPercentageReward = _slasherPercentageReward;
    }

    /// @notice                       Changes Bitcoin transaction fee
    /// @dev                          Only owner can call this
    /// @param _bitcoinFee            The new Bitcoin transaction fee
    function setBitcoinFee(uint _bitcoinFee) external override onlyOwner {
        bitcoinFee = _bitcoinFee;
    }

    /// @notice                             Burns teleBTC and records the burn request
    /// @dev                                After submitting the burn request, lockers have a limited time
    ///                                     to send BTC and provide burn proof
    /// @param _amount                      Amount of teleBTC that user wants to burn
    /// @param _userScript                  User's script
    /// @param _lockerLockingScript	        Locking script of locker that should execute the burn request
    /// @return _burntAmount                Amount of teleBTC that user will receive (after reducing fees)
    function ccBurn(
        uint _amount,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript
    ) external nonReentrant nonZeroValue(_amount) override returns (uint _burntAmount) {
        // Checks validity of user's script
        _checkScriptType(_userScript, _scriptType);

        // Checks if the given locking script is locker
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        /*
            Gets the target address of locker
            note: we don't check whether _lockerTargetAddress is equal to zero
            or not since _lockerLockingScript is locker
        */
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        // Transfers users's teleBTC
        ITeleBTC(teleBTC).transferFrom(_msgSender(), address(this), _amount);

        uint remainedAmount = _getFees(
            _amount,
            _lockerTargetAddress
        );

        // Burns remained teleBTC
        ITeleBTC(teleBTC).approve(lockers, remainedAmount);
        _burntAmount = ILockers(lockers).burn(_lockerLockingScript, remainedAmount);

        _saveBurnRequest(
            _amount,
            _burntAmount,
            _userScript,
            _scriptType,
            IBitcoinRelay(relay).lastSubmittedHeight(),
            _lockerTargetAddress
        );

        emit CCBurn(
            _msgSender(),
            _userScript,
            _scriptType,
            _amount,
            _burntAmount,
            _lockerTargetAddress,
            _lockerLockingScript,
            burnRequests[_lockerTargetAddress][burnRequests[_lockerTargetAddress].length - 1].requestIdOfLocker,
            burnRequests[_lockerTargetAddress][burnRequests[_lockerTargetAddress].length - 1].deadline
        );

    }

    /// @notice                             Checks the correctness of burn proof
    /// @dev                                Makes isTransferred flag true for the paid requests
    /// @param _version                     Version of the transaction containing the burn transaction
    /// @param _vin                         Inputs of the transaction containing the burn transaction
    /// @param _vout                        Outputs of the transaction containing the burn transaction
    /// @param _locktime                    Lock time of the transaction containing the burn transaction
    /// @param _blockNumber                 Height of the block containing the burn transaction
    /// @param _intermediateNodes           Merkle inclusion proof for transaction containing the burn transaction
    /// @param _index                       Index of transaction containing the burn transaction in the block
    /// @param _lockerLockingScript         Locker's locking script (on Bitcoin) that this burn request belongs to
    /// @param _burnReqIndexes              Indexes of requests that locker wants to provide proof for them
    /// @param _voutIndexes                 Indexes of outputs that were used to pay burn requests (_voutIndexes[i] belongs to _burnReqIndexes[i])
    /// @return
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
        // Checks that locker's tx doesn't have any locktime
        require(_locktime == bytes4(0), "CCBurnRouter: non-zero lock time");

        // Checks if the locking script is valid
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        // Get the target address of the locker from its locking script
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        require(
            _burnReqIndexes.length == _voutIndexes.length,
            "CCBurnRouter: wrong indexes"
        );

        // Checks inclusion of transaction
        bytes32 txId = BitcoinHelper.calculateTxId(_version, _vin, _vout, _locktime);
        require(
            _isConfirmed(
                txId,
                _blockNumber,
                _intermediateNodes,
                _index
            ),
            "CCBurnRouter: transaction has not finalized yet"
        );

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
        _updateIsUsedAsBurnProof(paidOutputCounter, _vout, _lockerLockingScript, txId);

        return true;
    }

    /// @notice                             Slashes a locker if she did not paid a cc burn request before its deadline
    /// @param _lockerLockingScript         locker's locking script that the unpaid request belongs to
    /// @param _indices                     Array of indices of the requests that their deadline has passed
    /// @return                             True if dispute is successfull
    function disputeBurn(
        bytes calldata _lockerLockingScript,
        uint[] memory _indices
    ) external nonReentrant override returns (bool) {
        // Checks if the locking script is valid
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        // Get the target address of the locker from its locking script
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        uint _lastSubmittedHeight = IBitcoinRelay(relay).lastSubmittedHeight();

        // Goes through provided indexes of burn requests to see if locker should be slashed
        for (uint i = 0; i < _indices.length; i++) {
            // Checks that locker has not provided burn proof
            require(
                !burnRequests[_lockerTargetAddress][_indices[i]].isTransferred,
                "CCBurnRouter: request has been paid before"
            );

            // Checks that payback deadline has passed
            require(
                burnRequests[_lockerTargetAddress][_indices[i]].deadline < _lastSubmittedHeight,
                "CCBurnRouter: payback deadline has not passed yet"
            );

            // Sets "isTransferred = true" to prevent slashing the locker again
            burnRequests[_lockerTargetAddress][_indices[i]].isTransferred = true;

            // Slashes locker and sends the slashed amount to the user
            ILockers(lockers).slashIdleLocker(
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

        return true;
    }

    /// @notice                                 Slashes a locker if they issue a tx that doesn't match any burn request
    /// @dev                                    Input tx is a malicious tx which shows that locker spent BTC
    ///                                         Output tx is the tx that was spent by locker in input tx
    ///                                         Output tx --> money goes to locker --> Input tx --> locker steals the funds
    /// @param _lockerLockingScript             Suspicious locker's locking script
    /// @param _versions                        Versions of input and output tx
    /// @param _inputVin                        Inputs of the malicious transaction
    /// @param _inputVout                       Outputs of the malicious transaction
    /// @param _outputVin                       Inputs of the spent transaction
    /// @param _outputVout                      Outputs of the spent transaction
    /// @param _locktimes                       Locktimes of input and output tx
    /// @param _inputIntermediateNodes          Merkle inclusion proof for the malicious transaction
    /// @param _indexesAndBlockNumbers          Indices of malicious input in input tx, input tx in block and block number of input tx
    /// @return                                 True if dispute is successfull
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
    ) external payable nonReentrant override returns (bool) {
        // Checks input array sizes
        require(
            _versions.length == 2 &&
            _locktimes.length == 2 &&
            _indexesAndBlockNumbers.length == 3,
            "CCBurnRouter: wrong inputs"
        );

        // Checks if the locking script is valid
        require(
            ILockers(lockers).isLocker(_lockerLockingScript),
            "CCBurnRouter: given locking script is not locker"
        );

        // Finds input tx id and checks its inclusion
        bytes32 _inputTxId = BitcoinHelper.calculateTxId(_versions[0], _inputVin, _inputVout, _locktimes[0]);
        require(
            _isConfirmed(
                _inputTxId,
                _indexesAndBlockNumbers[2], // Block number
                _inputIntermediateNodes,
                _indexesAndBlockNumbers[1] // Index of input tx in the block
            ),
            "CCBurnRouter: input transaction is not finalized"
        );

        /*
            Checks that input tx has not been provided as a burn proof
            note: if a locker executes a cc burn request but doesn't provide burn proof before deadline,
            we consider the transaction as a malicious tx
        */
        require(
            !isUsedAsBurnProof[_inputTxId],
            "CCBurnRouter: transaction has been used as burn proof"
        );

        // Extracts outpoint id and index from input tx
        (bytes32 _outpointId, uint _outpointIndex) = BitcoinHelper.extractOutpoint(
            _inputVin,
            _indexesAndBlockNumbers[0] // Index of malicious input in input tx
        );

        // Checks that "outpoint tx id == output tx id"
        require(
            _outpointId == BitcoinHelper.calculateTxId(_versions[1], _outputVin, _outputVout, _locktimes[1]),
            "CCBurnRouter: outpoint tx doesn't match with output tx"
        );

        // Checks that _outpointIndex of _outpointId belongs to locker locking script
        require(
            keccak256(BitcoinHelper.getLockingScript(_outputVout, _outpointIndex)) ==
            keccak256(_lockerLockingScript),
            "CCBurnRouter: output tx doesn't belong to locker"
        );

        // Checks that deadline for using the tx as burn proof has passed
        require(
            IBitcoinRelay(relay).lastSubmittedHeight() > transferDeadline + _indexesAndBlockNumbers[2],
            "CCBurnRouter: payback deadline has not passed yet"
        );

        // Slashes locker
        _slashLockerForDispute(
            _inputVout,
            _lockerLockingScript,
            _inputTxId,
            _indexesAndBlockNumbers[2] // Block number
        );

        return true;
    }

    /// @notice                                 Slashes the malicious locker
    /// @param _inputVout                       Inputs of the malicious transaction
    /// @param _lockerLockingScript             Malicious locker's locking script
    /// @param _inputTxId                       Tx id of the malicious transaction
    /// @param _inputBlockNumber                Block number of the malicious transaction
    function _slashLockerForDispute(
        bytes memory _inputVout,
        bytes memory _lockerLockingScript,
        bytes32 _inputTxId,
        uint _inputBlockNumber
    ) private {

        // Finds total value of malicious transaction
        uint totalValue = BitcoinHelper.parseOutputsTotalValue(_inputVout);

        // Gets the target address of the locker from its Bitcoin address
        address _lockerTargetAddress = ILockers(lockers)
        .getLockerTargetAddress(_lockerLockingScript);

        ILockers(lockers).slashTheifLocker(
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

    /// @notice                             Checks the burn requests that get paid by this transaction
    /// @param _paidBlockNumber             Block number in which locker paid the burn request
    /// @param _lockerTargetAddress         Address of the locker on the target chain
    /// @param _vout                        Outputs of a transaction
    /// @param _burnReqIndexes              Indexes of requests that locker wants to provide proof for them
    /// @param _voutIndexes                 Indexes of outputs that were used to pay burn requests (_voutIndexes[i] belongs to _burnReqIndexes[i])
    /// @return paidOutputCounter           Number of executed burn requests
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

        for (uint i = 0; i < _burnReqIndexes.length; i++) {
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
                    ScriptTypes(uint(burnRequests[_lockerTargetAddress][_burnReqIndex].scriptType))
                );

                // Checks that locker has sent required teleBTC amount
                if (burnRequests[_lockerTargetAddress][_burnReqIndex].burntAmount == parsedAmount) {
                    burnRequests[_lockerTargetAddress][_burnReqIndex].isTransferred = true;
                    paidOutputCounter = paidOutputCounter + 1;
                    emit PaidCCBurn(
                    // burnRequests[_lockerTargetAddress][_burnReqIndex].sender,
                    // burnRequests[_lockerTargetAddress][_burnReqIndex].userScript,
                    // burnRequests[_lockerTargetAddress][_burnReqIndex].scriptType,
                    // parsedAmount,
                        _lockerTargetAddress,
                        burnRequests[_lockerTargetAddress][_burnReqIndex].requestIdOfLocker,
                        txId,
                        _voutIndexes[i]
                    );
                }
            }
        }
    }

    /// @notice                                 Checks if all outputs of the transaction used to pay a cc burn request
    /// @dev                                    One output might return the remaining value to the locker
    /// @param _paidOutputCounter               Number of the tx outputs that pay a cc burn request
    /// @param _vout                            Outputs of a transaction
    /// @param _lockerLockingScript             Locking script of locker
    /// @param _txId                            Transaction id
    function _updateIsUsedAsBurnProof(
        uint _paidOutputCounter,
        bytes memory _vout,
        bytes memory _lockerLockingScript,
        bytes32 _txId
    ) private {
        uint parsedAmount = BitcoinHelper.parseValueHavingLockingScript(_vout, _lockerLockingScript);
        uint numberOfOutputs = BitcoinHelper.numberOfOutputs(_vout);

        if (parsedAmount != 0 && _paidOutputCounter + 1 == numberOfOutputs) {
            // One output sends the remained value to locker
            isUsedAsBurnProof[_txId] = true;
        } else if (_paidOutputCounter == numberOfOutputs) {
            // All output pays cc burn requests
            isUsedAsBurnProof[_txId] = true;
        }
    }

    function _checkScriptType(bytes memory _userScript, ScriptTypes _scriptType) private pure {
        if (_scriptType == ScriptTypes.P2PK || _scriptType == ScriptTypes.P2WSH) {
            require(_userScript.length == 32, "CCBurnRouter: invalid user script");
        } else {
            require(_userScript.length == 20, "CCBurnRouter: invalid user script");
        }
    }

    /// @notice                           Records burn request of user
    /// @param _amount                    Amount of wrapped token that user wants to burn
    /// @param _burntAmount               Amount of wrapped token that actually gets burnt after deducting fees from the original value (_amount)
    /// @param _userScript                User's Bitcoin address
    /// @param _lastSubmittedHeight       Last block header height submitted on the relay contract
    /// @param _lockerTargetAddress       Locker's target chain address that the request belongs to
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

    /// @notice                         Checks inclusion of the transaction in the specified block
    /// @dev                            Calls the relay contract to check Merkle inclusion proof
    /// @param _txId                    Id of the transaction
    /// @param _blockNumber             Height of the block containing the transaction
    /// @param _intermediateNodes       Merkle inclusion proof for the transaction
    /// @param _index                   Index of transaction in the block
    /// @return                         True if the transaction was included in the block
    function _isConfirmed(
        bytes32 _txId,
        uint256 _blockNumber,
        bytes memory _intermediateNodes,
        uint _index
    ) private returns (bool) {
        // Finds fee amount
        uint feeAmount = IBitcoinRelay(relay).getBlockHeaderFee(_blockNumber, 0);
        require(msg.value >= feeAmount, "CCBurnRouter: relay fee is not sufficient");

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

    /// @notice                      Checks inclusion of the transaction in the specified block
    /// @dev                         Calls the relay contract to check Merkle inclusion proof
    /// @param _amount               Id of the transaction
    /// @param _lockerTargetAddress  Id of the transaction
    /// @return                      Remained amount after reducing fees
    function _getFees(
        uint _amount,
        address _lockerTargetAddress
    ) private returns (uint) {
        // Calculates protocol fee
        uint protocolFee = _amount*protocolPercentageFee/MAX_PROTOCOL_FEE;

        require(_amount > protocolFee + bitcoinFee, "CCBurnRouter: amount is too low");

        uint remainedAmount = _amount - protocolFee - bitcoinFee;

        // Transfers protocol fee
        ITeleBTC(teleBTC).transfer(treasury, protocolFee);

        // Transfers bitcoin fee to locker
        ITeleBTC(teleBTC).transfer(_lockerTargetAddress, bitcoinFee);

        return remainedAmount;
    }

}