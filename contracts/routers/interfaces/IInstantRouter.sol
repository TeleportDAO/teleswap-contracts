pragma solidity >=0.7.6;

interface IInstantRouter {
    // structures
    struct InstantTransferRequest {
        address user;
        uint collateralAmount;
        uint wrappedBitcoinAmount;
        uint creationTime;
        uint deadline;
        uint paybackDeadline;
        bool isPaidback;
        bool isUsed;
    }
    struct debt {
        address user;
        uint wrappedBitcoinAmount;
        uint collateralAmount;
        uint deadline;
    }

    // events
    event PaybackInstantLoan(address user, uint bitcoinAmount);
    event PunishUser(address user, uint slashedAmount);

    // read-only functions
    function owner() external view returns(address);
    function bitcoinInstantPool() external view returns(address);
    function wrappedBitcoin() external view returns(address);
    function ccTransferRouter() external view returns(address);
    function requestCollateralAmount(bytes32 messageHash) external view returns(uint);
    function paybackDeadline() external returns(uint);
    function collateralRatio() external returns(uint);

    // state-changing functions
    function changeOwner(address _owner) external;
    function setExchangeRouter(address _ExchangeRouter) external;
    function setPaybackDeadline(uint _paybackDeadline) external;
    function setCollateralRatio(uint _paybackDeadline) external;
    function setCCTransferRouter (address _ccTransferRouter) external;
    function setPunisherReward (uint _punisherReward) external;
    function addLiquidity(address user, uint instantPoolTokenAmount) external returns(uint);
    function removeLiquidity(address user, uint instantPoolTokenAmount) external returns(uint);
    function instantCCTransfer (address receiver, uint amount, uint deadline) external returns (bool);
    function instantCCTransferWithPermit(
        address signer,
        bytes memory signature,
        address receiver,
        uint amount,
        uint nonce
    ) external returns(bool);
    function instantCCExchange (
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address receiver,
        uint deadline
    ) external returns(uint[] memory amounts, bool result);
    function instantCCExchangeWithPermit(
        address signer,
        bytes memory signature,
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address receiver,
        uint deadline
    ) external returns(uint[] memory amounts, bool result);
    function payBackInstantTransfer (uint bitcoinAmount, address user) external returns (bool);
    function punishUser (address user, uint[] memory debtIndex) external returns (bool);

}