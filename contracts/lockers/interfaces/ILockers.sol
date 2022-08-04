pragma solidity 0.8.0;

interface ILockers {

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
        // TODO: remove lockerBitcoinAddress
        bytes lockerBitcoinAddress;
        address lockerBitcoinDecodedAddress;
        uint TDTLockedAmount;
        uint nativeTokenLockedAmount;
        uint netMinted;
        bool isExisted;
        // TODO: isScriptHash is used for p2pkh and p2sh, but what about segwit
        bool isScriptHash;
        bool isActive;
    }

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

    // Read-only functions

    // TODO: remove redeemScriptHash
    // function redeemScriptHash() external view returns(address);

    function TeleportDAOToken() external view returns(address);

    function teleBTC() external view returns (address);

    // TODO: add miter and burner roles and remove cc burn router, cc exchange, and cc transfer
    function ccBurnRouter() external view returns (address);

    function exchangeConnector() external view returns (address);

    function requiredTDTLockedAmount() external view returns (uint);

    function requiredTNTLockedAmount() external view returns (uint);

    function collateralRatio() external view returns (uint);

    function priceOracle() external view returns (address);

    function lockerBitcoinDecodedAddressToTargetAddress(address  _lockerBitcoinAddress) external view returns (address);

    // function lockerTargetAddressList(uint _index) external view returns (address);

    // function candidateTargetAddressList(uint _index) external view returns (address);

    function isLocker(address _lockerBitcoinDecodedAddress) external view returns (bool);

    function getNumberOfLockers() external view returns (uint);

    function getLockerBitcoinAddress(address _lockerTargetAddress) external view returns (bytes memory);

    function isActive(address _lockerTargetAddress) external view returns (bool);

    function getLockerCapacity(address _lockerTargetAddress) external view returns (uint);

    function totalNumberOfLockers() external view returns (uint);

    function totalNumberOfCandidates() external view returns (uint);

    // FIXME: What is this?
    // function assignLocker(bool _isMint, uint _amount) external view returns (address);

    // State-changing functions

    function addMinter(address account) external;

    function removeMinter(address account) external;

    function addBurner(address account) external;

    function removeBurner(address account) external;

    function mint(address lockerBitcoinDecodedAddress, address receiver, uint amount) external returns(bool);

    function burn(address lockerBitcoinDecodedAddress, uint256 amount) external returns(bool);

    // function setRequiredLockedAmount(uint _requiredLockedAmount) external;

    function setRequiredTDTLockedAmount(uint _requiredTDTLockedAmount) external;

    function setRequiredTNTLockedAmount(uint _requiredTNTLockedAmount) external;

    function setPriceOracle(address _priceOracle) external;

    // TODO: add minter and add burner
    function setCCBurnRouter(address _ccBurnRouter) external;

    function setExchangeConnector(address _exchangeConnector) external;

    function setTeleBTC(address _teleBTC) external;

    function setCollateralRatio(uint _collateralRatio) external;

    // FIXME: change the function signature
    // TODO: make it internal and must be called after mint and burn functions, also add mint and burn functions
    function updateIsActive(address _lockerBitcoinAddress, uint _amount, bool _isMint) external returns (bool);

    function requestToBecomeLocker(
        bytes memory _candidateBitcoinAddress,
        address _candidateBitcoinDecodedAddress,
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