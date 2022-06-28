pragma solidity 0.8.0;

import "../libraries/SafeMath.sol";
import "./interfaces/IBitcoinTeleporter.sol";
import "../routers/interfaces/IExchangeRouter.sol";
import "../erc20/interfaces/IERC20.sol";
import "hardhat/console.sol";

contract BitcoinTeleporter is IBitcoinTeleporter {
    using SafeMath for uint256;
    address public override owner;
    address public override TeleportDAOToken;
    address public override wrappedBitcoin;
    address public override ccBurnRouter;
    address public override exchangeRouter;
    uint public override requiredLockedAmount;
    uint public unlockFee; // it is a percentage
    uint public unlockPeriod;
    uint public lastUnlock;
    teleporter[] public teleportersList;
    uint public override numberOfTeleporters;
    bytes public override redeemScript;
    address public override redeemScriptHash;
    address public override multisigAddress;
    bytes public override multisigAddressBeforeEncoding;
    bytes constant ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor(
        address _TeleportDAOToken, 
        address _exchangeRouter, 
        uint _unlockFee, 
        uint _unlockPeriod, 
        uint _requiredLockedAmount
    ) public {
        TeleportDAOToken = _TeleportDAOToken;
        // Fixed bug
        exchangeRouter = _exchangeRouter;
        unlockFee = _unlockFee;
        unlockPeriod = _unlockPeriod;
        requiredLockedAmount = _requiredLockedAmount;
        owner = msg.sender;
    }

    function changeOwner(address _owner) external override onlyOwner {
        owner = _owner;
    }

    function setUnlockFee(uint _unlockFee) external override onlyOwner {
        unlockFee = _unlockFee;
    }

    function setUnlockPeriod(uint _unlockPeriod) external override onlyOwner {
        unlockPeriod = _unlockPeriod;
    }

    function setRequiredLockedAmount(uint _requiredLockedAmount) external override onlyOwner {
        requiredLockedAmount = _requiredLockedAmount;
    }

    function setCCBurnRouter(address _ccBurnRouter) external override onlyOwner {
        ccBurnRouter = _ccBurnRouter;
    }

    function setExchangeRouter(address _exchangeRouter) external override onlyOwner {
        exchangeRouter = _exchangeRouter;
    }

    function setWrappedBitcoin(address _wrappedBitcoin) external override onlyOwner {
        wrappedBitcoin = _wrappedBitcoin;
    }

    function addTeleporter (bytes memory _teleporterBitcoinPubKey) external override returns(bool) {
        // user need to lock enough amount of TDT to become teleporter
        IERC20(TeleportDAOToken).transferFrom(msg.sender, address(this), requiredLockedAmount);
        teleporter memory _teleporter;
        _teleporter.teleporterBitcoinPubKey = _teleporterBitcoinPubKey;
        _teleporter.teleporterAddress = msg.sender;
        // we cannot resize the solidity array, so we store the number of teleporters in numberOfTeleporters
        if (teleportersList.length == numberOfTeleporters) {
            teleportersList.push(_teleporter);
        } else {
            teleportersList[numberOfTeleporters] = _teleporter;
        }
        numberOfTeleporters = numberOfTeleporters + 1;
        require(updateRedeemScriptHash(), "teleporter address is not correct");
        require(updateMultisigAddress(), "teleporter address is not correct");
        emit AddTeleporter(_teleporterBitcoinPubKey, msg.sender, requiredLockedAmount, block.timestamp);
        return true;
    }

    function removeTeleporter (uint teleporterIndex) external override returns(bool) {
        require(teleportersList[teleporterIndex].teleporterAddress == msg.sender, "you are not allowed to remove teleporter");
        // Fixed bug
        require(block.number >= lastUnlock + unlockPeriod, "too soon for new unlock");
        require(numberOfTeleporters > teleporterIndex, "the given index does not exist");
        // TODO: check that the caller has authority to delete the teleporter address
        bytes memory _teleporterBitcoinPubKey = teleportersList[teleporterIndex].teleporterBitcoinPubKey;
        delete teleportersList[teleporterIndex];
        teleportersList[teleporterIndex] = teleportersList[numberOfTeleporters - 1]; // fill the gap in the teleporter list
        delete teleportersList[teleportersList.length - 1];
        numberOfTeleporters = numberOfTeleporters - 1;
        require(updateRedeemScriptHash(), "teleporter address is not correct");
        require(updateMultisigAddress(), "teleporter address is not correct");
        IERC20(TeleportDAOToken).transfer(msg.sender, requiredLockedAmount*(100-unlockFee)/100);
        lastUnlock = block.number;
        emit RemoveTeleporter(_teleporterBitcoinPubKey, msg.sender, requiredLockedAmount*(100-unlockFee)/100);
        return true;
    }

    function isTeleporter (address teleporter, uint index) external override view returns(bool) {
        if (teleportersList[index].teleporterAddress == teleporter) {
            return true;
        } else {
            return false;
        }
    }
    
    function updateRedeemScriptHash() internal returns(bool) { // tested
        bytes1 constantOPCODE = 0x21;
        bytes1 multisigOPCODE = 0xae;
        uint numberOfRequiredSignatures;
        if (numberOfTeleporters == 1) {
            numberOfRequiredSignatures = 1;
        } else {
            numberOfRequiredSignatures = 2*numberOfTeleporters/3;
        }
        bytes1 _numberOfTeleporters = findOPCODE(numberOfTeleporters);
        bytes1 _numberOfRequiredSignatures = findOPCODE(numberOfRequiredSignatures);
        redeemScript = abi.encodePacked(_numberOfRequiredSignatures);
        for (uint i = 0; i < numberOfTeleporters; i++) {
            redeemScript = abi.encodePacked(redeemScript, constantOPCODE, teleportersList[i].teleporterBitcoinPubKey);
        }
        redeemScript = abi.encodePacked(redeemScript, _numberOfTeleporters, multisigOPCODE);
        redeemScriptHash =  address(uint160(bytes20(doubleHash(redeemScript))));
        return true;
    }

    function updateMultisigAddress() internal returns(bool) {
        bytes memory desiredResult1;
        bytes memory desiredResult2;
        bytes memory desiredResult3;
        bytes memory desiredResult4;
        bytes memory result;
        address _result;
        // step 1
        bytes1 temp1 = 0xc4; // for btc testnet
        desiredResult1 = abi.encodePacked(temp1, redeemScriptHash);
        // step 2
        bytes32 temp32 = sha256(abi.encodePacked(sha256(desiredResult1)));
        desiredResult2 = abi.encodePacked(temp32[0], temp32[1], temp32[2], temp32[3]);
        // step 3
        desiredResult3 = abi.encodePacked(desiredResult1, desiredResult2);
        multisigAddressBeforeEncoding = desiredResult3;
        // step 4
        desiredResult4 = decTo58(hexToDec(desiredResult3)); // the result is not UTF-8 encoded
        result = revertBytes(desiredResult4);
        assembly {
            _result := mload(add(result, 20))
        }
        multisigAddress = _result;
        // step 5
        // step 6
        return true;
    }

    function slashTeleporters (uint bitcoinAmount, address recipient) external override {
        require(msg.sender == ccBurnRouter, "message sender is not correct");
        address[] memory path = new address[](2);
        path[0] = TeleportDAOToken;
        path[1] = wrappedBitcoin;
        uint[] memory neededTDT = IExchangeRouter(exchangeRouter).getAmountsIn(
            bitcoinAmount,
            path
        ); 
        IERC20(TeleportDAOToken).approve(exchangeRouter, neededTDT[0]);
        uint deadline = block.number + 1;
        IExchangeRouter(exchangeRouter).swapTokensForExactTokens(
            bitcoinAmount, // amount out
            neededTDT[0], // amount in
            path,
            recipient,
            deadline
        ); 
    }

    function hexToDec(bytes memory input) internal returns(uint) {
        uint len = input.length;
        uint result;
        for (uint i = 0; i < len; i++) {
            result = result*(256) + uint8(input[i]);
        }
        return result;
    }

    function decTo58 (uint input) internal returns(bytes memory) {
        bytes memory result; 
        uint temp;
        while (input > 0) {
            temp = input%58;
            result = abi.encodePacked(result, ALPHABET[temp]);
            input = input/58;
        }
        return result;
    }

    function findOPCODE(uint input) internal returns(bytes1 data) {
        if (input == 1) return 0x51;
        if (input == 2) return 0x52;
        if (input == 3) return 0x53;
        if (input == 4) return 0x54;
        if (input == 5) return 0x55;
        if (input == 6) return 0x56;
        if (input == 7) return 0x57;
        if (input == 8) return 0x58;
        if (input == 9) return 0x59;
        if (input == 10) return 0x5a;
        if (input == 11) return 0x5b;
        if (input == 12) return 0x5c;
        if (input == 13) return 0x5d;
        if (input == 14) return 0x5e;
        if (input == 15) return 0x5f;
        if (input == 16) return 0x60;
    }
    // bitcoin double hash function
    function doubleHash (bytes memory input) internal returns(bytes20) {
        bytes32 inputHash1 = sha256(input);
        bytes20 inputHash2 = ripemd160(abi.encodePacked(inputHash1));
        return inputHash2;
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

    function revertBytes (bytes memory input) internal returns(bytes memory) {
        bytes memory result;
        uint len = input.length;
        for (uint i = 0; i < len; i++) {
            result = abi.encodePacked(result, input[len-i-1]);
        }
        return result;
    }

    function concat(bytes memory a, bytes1 b) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b);
    }

}
