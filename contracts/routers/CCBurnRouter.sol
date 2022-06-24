pragma solidity ^0.7.6;

import "../libraries/SafeMath.sol";
import "../libraries/BitcoinTxParser.sol";
import "./interfaces/ICCBurnRouter.sol";
import "./interfaces/ICCExchangeRouter.sol";
import "../erc20/interfaces/IWrappedToken.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "../teleporter/interfaces/IBitcoinTeleporter.sol";
import "hardhat/console.sol";

contract CCBurnRouter is ICCBurnRouter {
    using SafeMath for uint256;
    address public bitcoinRelay;
    address public bitcoinTeleporter;
    unWrapRequest[] public unWrapRequests;
    mapping(uint => psbt[]) public psbts;
    address public ccExchangeRouter;
    address public TeleportDAOToken;
    address public override wrappedBitcoin;
    uint public transferDeadline;
    uint public burningFee;
    uint public confirmationParameter;
    address public override owner;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor(
        address _bitcoinRelay,
        address _bitcoinTeleporter,
        address _TeleportDAOToken,
        uint _confirmationParameter,
        uint _transferDeadline,
        uint _burningFee
    ) public {
        bitcoinRelay = _bitcoinRelay;
        bitcoinTeleporter = _bitcoinTeleporter;
        TeleportDAOToken = _TeleportDAOToken;
        confirmationParameter = _confirmationParameter;
        transferDeadline = _transferDeadline;
        burningFee = _burningFee;
        owner = msg.sender;
    }

    function changeOwner(address _owner) external override onlyOwner {
        owner = _owner;
    }

    function setConfirmationParameter(uint _confirmationParameter) external override onlyOwner {
        confirmationParameter = _confirmationParameter;
    }

    function setBitcoinRelay(address _bitcoinRelay) external override onlyOwner {
        bitcoinRelay = _bitcoinRelay;
    }

    function setWrappedBitcoin (address _wrappedBitcoin) external override onlyOwner {
        wrappedBitcoin = _wrappedBitcoin;
    }


    function setTransferDeadline (uint _transferDeadline) external override onlyOwner {
        transferDeadline = _transferDeadline;
    }

    function ccBurn (uint amount, bytes memory decodedAddress) external override returns(bool) {
        console.log("ccBurn...");
        address pubKeyHash = bytesToAddress(decodedAddress, 1, 21);
        // TODO: check the correctness of bitcoinAddress
        IERC20(wrappedBitcoin).transferFrom(msg.sender, address(this), amount);
        IWrappedToken(wrappedBitcoin).burn(amount*(100-burningFee)/100);

        console.log("just before saveUnwrapRequest");
        saveUnwrapRequest(amount, pubKeyHash);
        emit CCBurn(pubKeyHash, amount, unWrapRequests.length - 1);
        return true;
    }

    function bytesToAddress (bytes memory data, uint start, uint end) internal returns (address resultAddress) {
        byte temp;
        bytes memory resultBytes;
        for (uint i = start; i < end + 1; i++) {
            temp = data[i];
            resultBytes = abi.encodePacked(resultBytes, temp);
        }
        assembly {
            resultAddress := mload(add(resultBytes, 20))
        }
    }

    // function pubKeyHash (bytes memory pubKey) external returns (address) {
    //     address result = address(uint160(bytes20(doubleHash(pubKey))));
    //     console.log("result", result);
    //     return result;
    // }

    // PSBT = partialy signed bitcoin transaction
    function submitPSBT(
        uint teleporterIndex,
        bytes memory psbtBase,
        bytes memory psbtSigned,
        uint requestIndex
    ) external override returns(bool) {
        require(
            IBitcoinTeleporter(bitcoinTeleporter).isTeleporter(msg.sender, teleporterIndex), "msg sender is not teleporter"
        );
        require(
            !unWrapRequests[requestIndex].isTransferred,
            "Request has been paid before"
        );
        require(
            unWrapRequests[requestIndex].transferDeadline >= block.number,
            "Pay back deadline has passed"
        );
        // save psbt
        psbt memory _psbt;
        _psbt.psbtSigned = psbtSigned;
        _psbt.psbtBase = psbtBase;
        psbts[requestIndex].push(_psbt);
        emit SubmitPSBT(psbtBase, psbtSigned, teleporterIndex, requestIndex);
        return true;
    }

    function burnProof(
        bytes4 version,
        bytes memory vin,
        bytes calldata vout,
        bytes4 locktime,
        uint256 blockNumber,
        bytes calldata intermediateNodes,
        uint index,
        bool payWithTDT,
        uint requestIndex
    ) external override returns(bool) {
        console.log("burnProof...");
        require(
            !unWrapRequests[requestIndex].isTransferred,
            "Request has been paid before"
        );
        require(
        // FIXME: I think the following line is the correct one
            unWrapRequests[requestIndex].transferDeadline >= IBitcoinRelay(bitcoinRelay).lastSubmittedHeight(),
        // unWrapRequests[requestIndex].transferDeadline >= block.number,
            "Pay back deadline has passed"
        );

        console.log("after requires in burnProof");

        bytes32 txId = calculateTxId(version, vin, vout, locktime);

        txId = revertBytes32(txId);
        require(
            isConfirmed(
                txId,
                blockNumber,
                intermediateNodes,
                index,
                payWithTDT,
                confirmationParameter
            ),
            "Transaction has not finalized"
        );
        uint parsedBitcoinAmount;
        (parsedBitcoinAmount,) = BitcoinTxParser.parseAmountForP2PK(
            vout,
            unWrapRequests[requestIndex].pubKeyHash
        );

        console.log("parsedBitcoinAmount");
        console.log(parsedBitcoinAmount);

        console.log("after event emitting in burnProof");
        require(
            parsedBitcoinAmount >= unWrapRequests[requestIndex].amount,
            "Pay back amount is not sufficient"
        );

        // FIXME: somewhere the "isTransferred" must be changed to true
        unWrapRequests[requestIndex].isTransferred = true;

        emit PaidCCBurn(unWrapRequests[requestIndex].pubKeyHash, parsedBitcoinAmount, requestIndex);
        return true;
    }

    function disputeBurn(uint requestIndex, address recipient) external override {
        require(
            !unWrapRequests[requestIndex].isTransferred,
            "Request has been paid before"
        );
        // get the latest submitted block on relay
        uint lastSubmittedHeight = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight();

        console.log("lastSubmittedHeight");
        console.log(lastSubmittedHeight);

        require(
            unWrapRequests[requestIndex].transferDeadline < lastSubmittedHeight,
            "Pay back deadline has not passed yet"
        );

        // FIXME: should remove the following line
        require(msg.sender == unWrapRequests[requestIndex].requestSender, "Sender is not allowed");
        // slash teleporters
        IBitcoinTeleporter(bitcoinTeleporter).slashTeleporters(unWrapRequests[requestIndex].amount, recipient);
    }

    function saveUnwrapRequest(
        uint amount,
        address pubKeyHash
    ) internal {
        console.log("saveUnwrapRequest...");
        uint lastSubmittedHeight = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight();
        unWrapRequest memory request;
        request.amount = amount;
        request.requestSender = msg.sender;
        request.pubKeyHash = pubKeyHash;
        request.burningFee = burningFee;
        request.transferDeadline = lastSubmittedHeight + transferDeadline;
        request.isTransferred = false;
        unWrapRequests.push(request);
        console.log("end of saveUnwrapRequest");
    }

    function isConfirmed(
        bytes32 txId,
        uint256 blockNumber,
        bytes memory intermediateNodes,
        uint index,
        bool payWithTDT,
        uint neededConfirmations
    ) internal returns (bool) {

        console.log("isConfirmed...");
        console.log("the tx id");
        console.logBytes32(txId);

        // TODO: uncomment it
        // uint feeAmount;
        // IERC20(feeTokenAddress).transferFrom(msg.sender, address(this), feeAmount);
        return IBitcoinRelay(bitcoinRelay).checkTxProof(
            txId,
            blockNumber,
            intermediateNodes,
            index
        // payWithTDT,
        // neededConfirmations
        );
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

    function calculateTxId (
        bytes4 _version,
        bytes memory _vin,
        bytes calldata _vout,
        bytes4 _locktime
    ) internal returns(bytes32) {

        console.log("calculateTxId");
        bytes32 inputHash1 = sha256(abi.encodePacked(_version, _vin, _vout, _locktime));
        bytes32 inputHash2 = sha256(abi.encodePacked(inputHash1));
        return inputHash2;
    }

    // bitcoin double hash function
    function doubleHash (bytes memory input) internal returns(bytes20) {
        bytes32 inputHash1 = sha256(input);
        bytes20 inputHash2 = ripemd160(abi.encodePacked(inputHash1));
        return inputHash2;
    }
}
