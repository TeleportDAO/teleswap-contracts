pragma solidity 0.7.6;

interface IBitcoinTeleporter {
    // structures
    struct teleporter {
        bytes teleporterBitcoinPubKey;
        address teleporterAddress;
    }

    // events
    event AddTeleporter(bytes teleporterBitcoinPubKey, address teleporterAddress, uint lockedAmount, uint addedtime);
    event RemoveTeleporter(bytes teleporterBitcoinPubKey, address teleporterAddress, uint unlockedAmount);

    // read-only functions
    function owner() external view returns (address);
    function TeleportDAOToken() external view returns(address);
    function wrappedBitcoin() external view returns(address);
    function ccBurnRouter() external view returns(address);
    function exchangeRouter() external view returns(address);
    function requiredLockedAmount() external view returns(uint);
    function numberOfTeleporters() external view returns(uint);
    function redeemScript() external view returns(bytes memory);
    function redeemScriptHash() external view returns(address);
    function multisigAddress() external view returns(address);
    function multisigAddressBeforeEncoding() external view returns(bytes memory);
    function isTeleporter (address teleporter, uint index) external view returns(bool);

    // state-changing functions
    function changeOwner(address _owner) external;
    function setUnlockFee(uint _unlockFee) external;
    function setUnlockPeriod(uint _unlockPeriod) external;
    function setRequiredLockedAmount(uint _submissionGasUsed) external;
    function setExchangeRouter(address _ccTransferRouter) external;
    function setCCBurnRouter(address _ccBurnRouter) external;
    function setWrappedBitcoin(address _wrappedBitcoin) external;
    function addTeleporter(bytes memory teleporterAddress) external returns(bool);
    function removeTeleporter(uint teleporterIndex) external returns(bool);
    function slashTeleporters (uint amount, address recipient) external;
}