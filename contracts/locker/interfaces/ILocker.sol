pragma solidity 0.8.0;

interface ILocker {
    // structures
    // struct teleporter {
    //     bytes teleporterBitcoinPubKey;
    //     address teleporterAddress;
    // }

    // Structures

    /// @notice                             Structure for registering lockers
    /// @dev
    /// @param lockerBitcoinAddress         Bitcoin address of locker
    /// @param TDTLockedAmount              Bond amount of locker in TDT
    /// @param nativeTokenLockedAmount      Bond amount of locker in native token of the target chain
    /// @param netMinted                    Total minted - total burnt
    /// @param isScriptHash                 Determines if the locker Bitcoin address is PubKey script or Hash script
    /// @param isActive                     Shows if a locker is active (has not requested for removal and
    ///                                     has enough collateral to accept more minting requests)
    struct locker {
        bytes lockerBitcoinAddress;
        uint TDTLockedAmount;
        uint nativeTokenLockedAmount;
        uint netMinted;
        bool isExisted;
        bool isScriptHash;
        bool isActive;
    }

    // events
    // event AddTeleporter(bytes teleporterBitcoinPubKey, address teleporterAddress, uint lockedAmount, uint addedtime);
    // event RemoveTeleporter(bytes teleporterBitcoinPubKey, address teleporterAddress, uint unlockedAmount);

    // Events

    event RequestAddLocker(
        address indexed lockerTargetAddress,
        bytes lockerBitcoinAddress,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        bool indexed isScriptHash
    );

    event RequestRemoveLocker(
        address indexed lockerTargetAddress,
        bytes lockerBitcoinAddress,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount,
        uint netMinted        //   = totalMinted  - totalBurnt which needs to be burnt
    );

    event LockerAdded(
        address indexed lockerTargetAddress,
        bytes lockerBitcoinAddress,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        bool isScriptHash
    // uint addingTime
    );

    event LockerRemoved(
        address indexed lockerTargetAddress,
        bytes lockerBitcoinAddress,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount
    // uint removingTime
    );

    // read-only functions
    // function owner() external view returns (address);
    // function TeleportDAOToken() external view returns(address);
    // function wrappedBitcoin() external view returns(address);
    // function ccBurnRouter() external view returns(address);
    // function exchangeRouter() external view returns(address);
    // function requiredLockedAmount() external view returns(uint);
    // function numberOfTeleporters() external view returns(uint);
    // function redeemScript() external view returns(bytes memory);
    // function redeemScriptHash() external view returns(address);
    // function multisigAddress() external view returns(address);
    // function multisigAddressBeforeEncoding() external view returns(bytes memory);
    // function isTeleporter (address teleporter, uint index) external view returns(bool);

    // Read-only functions

    function TeleportDAOToken() external view returns(address);

    function teleBTC() external view returns (address);

    function ccBurnRouter() external view returns (address);

    function exchangeRouter() external view returns (address);

    function requiredTDTLockedAmount() external view returns (uint);

    function requiredTNTLockedAmount() external view returns (uint);

    function collateralRatio() external view returns (uint);

    function priceOracle() external view returns (address);

    function BitcoinAddressToTargetAddress(bytes memory _lockerBitcoinAddress) external view returns (address);

    // function lockerTargetAddressList(uint _index) external view returns (address);

    // function candidateTargetAddressList(uint _index) external view returns (address);

    function isLocker(address _lockerTargetAddress) external view returns (bool);

    function getNumberOfLockers() external view returns (uint);

    function getLockerBitcoinAddress(address _lockerTargetAddress) external view returns (bytes memory);

    function isActive(address _lockerTargetAddress) external view returns (bool);

    function getLockerCapacity(address _lockerTargetAddress) external view returns (uint);

    // FIXME: What is this?
    // function assignLocker(bool _isMint, uint _amount) external view returns (address);


    // state-changing functions
    // function changeOwner(address _owner) external;
    // function setUnlockFee(uint _unlockFee) external;
    // function setUnlockPeriod(uint _unlockPeriod) external;
    // function setRequiredLockedAmount(uint _submissionGasUsed) external;
    // function setExchangeRouter(address _ccTransferRouter) external;
    // function setCCBurnRouter(address _ccBurnRouter) external;
    // function setWrappedBitcoin(address _wrappedBitcoin) external;
    // function addTeleporter(bytes memory teleporterAddress) external returns(bool);
    // function removeTeleporter(uint teleporterIndex) external returns(bool);
    // function slashTeleporters (uint amount, address recipient) external;

    // State-changing functions

    // function setRequiredLockedAmount(uint _requiredLockedAmount) external;

    function setRequiredTDTLockedAmount(uint _requiredTDTLockedAmount) external;

    function setRequiredTNTLockedAmount(uint _requiredTNTLockedAmount) external;

    function setPriceOracle(address _priceOracle) external;

    function setCCBurnRouter(address _ccBurnRouter) external;

    function setExchangeRouter(address _exchangeRouter) external;

    function setTeleBTC(address _teleBTC) external;

    function setCollateralRatio(uint _collateralRatio) external;

    // FIXME: change the function signature
    function updateIsActive(address _lockerBitcoinAddress, uint _amount, bool _isMint) external returns (bool);

    function requestToBecomeLocker(
        bytes memory _candidateBitcoinAddress,
        uint lockedTDTAmount,
        uint lockedNativeTokenAmount
    ) external returns (bool);

    function revokeRequest() external returns (bool);

    function addLocker(address _lockerTargetAddress) external returns (bool);

    function requestToRemoveLocker() external returns (bool);

    function removeLocker(address _lockerTargetAddress) external returns(bool);

    function selfRemoveLocker() external returns (bool);

    function slashLocker(address _lockerTargetAddress, uint _amount, address _recipient) external returns(bool);

}