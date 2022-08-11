// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

interface ILockers {

    // Structures

    /// @notice                             Structure for registering lockers
    /// @dev
    /// @param lockerRedeemScript           Locker redeem script
    /// @param TDTLockedAmount              Bond amount of locker in TDT
    /// @param nativeTokenLockedAmount      Bond amount of locker in native token of the target chain
    /// @param netMinted                    Total minted - total burnt
    /// @param isScriptHash                 Determines if the lockerScriptHash is pub key hash or redeem script hash
    /// @param isActive                     Shows if a locker is active (has not requested for removal and
    ///                                     has enough collateral to accept more minting requests)
    struct locker {
        bytes lockerRedeemScript;
        address lockerScriptHash;
        uint TDTLockedAmount;
        uint nativeTokenLockedAmount;
        uint netMinted;
        bool isLocker;
        // TODO: isScriptHash is used for p2pkh and p2sh, but what about segwit
        bool isScriptHash;
        bool isActive;
    }

    // Events

    event RequestAddLocker(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        bool indexed isScriptHash
    );

    event RequestRemoveLocker(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount,
        uint netMinted        //   = totalMinted  - totalBurnt which needs to be burnt
    );

    event LockerAdded(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTLockedAmount,
        uint nativeTokenLockedAmount,
        bool isScriptHash
    // uint addingTime
    );

    event LockerRemoved(
        address indexed lockerTargetAddress,
        bytes lockerRedeemScript,
        uint TDTUnlockedAmount,
        uint nativeTokenUnlockedAmount
    );

    event LockerSlashed(
        address indexed lockerTargetAddress,
        uint slashedCollateralAmount
    );

    // Read-only functions

    function lockerPercentageFee() external view returns (uint);

    function TeleportDAOToken() external view returns(address);

    function teleBTC() external view returns (address);

    function ccBurnRouter() external view returns (address);

    function exchangeConnector() external view returns (address);

    function minRequiredTDTLockedAmount() external view returns (uint);

    function minRequiredTNTLockedAmount() external view returns (uint);

    function collateralRatio() external view returns (uint);

    function liquidationRatio() external view returns (uint);

    function priceOracle() external view returns (address);

    function lockerTargetAddress(address  _lockerScriptHash) external view returns (address);

    function isLocker(address _lockerScriptHash) external view returns (bool);

    function getNumberOfLockers() external view returns (uint);

    function getLockerRedeemScript(address _lockerTargetAddress) external view returns (bytes memory);

    function isActive(address _lockerTargetAddress) external view returns (bool);

    function getLockerCapacity(address _lockerTargetAddress) external view returns (uint);

    function totalNumberOfLockers() external view returns (uint);

    function totalNumberOfCandidates() external view returns (uint);

    // State-changing functions

    function pauseLocker() external;

    function unPauseLocker() external;

    function addMinter(address _account) external;

    function removeMinter(address _account) external;

    function addBurner(address _account) external;

    function removeBurner(address _account) external;

    function mint(address _lockerScriptHash, address _receiver, uint _amount) external returns(uint);

    function burn(address _lockerScriptHash, uint256 _amount) external returns(uint);

    // function setRequiredLockedAmount(uint _requiredLockedAmount) external;

    function setMinRequiredTDTLockedAmount(uint _minRequiredTDTLockedAmount) external;

    function setMinRequiredTNTLockedAmount(uint _minRequiredTNTLockedAmount) external;

    function setPriceOracle(address _priceOracle) external;

    // TODO: add minter and add burner
    function setCCBurnRouter(address _ccBurnRouter) external;

    function setExchangeConnector(address _exchangeConnector) external;

    function setTeleBTC(address _teleBTC) external;

    function setCollateralRatio(uint _collateralRatio) external;

    function luquidateLocker(
        address _lockerTargetAddress,
        uint _btcAmount
    ) external returns (bool);

    function requestToBecomeLocker(
        bytes memory _candidateBitcoinAddress,
        address _candidateBitcoinDecodedAddress,
        uint _lockedTDTAmount,
        uint _lockedNativeTokenAmount
    ) external payable returns (bool);

    function revokeRequest() external returns (bool);

    function addLocker(address _lockerTargetAddress) external returns (bool);

    function requestToRemoveLocker() external returns (bool);

    function removeLocker(address _lockerTargetAddress) external returns(bool);

    function selfRemoveLocker() external returns (bool);

    function slashLocker(
        address _lockerTargetAddress, 
        uint _rewardAmount,
        address _rewardRecipient,
        uint _amount, 
        address _recipient
    ) external returns(bool);

}