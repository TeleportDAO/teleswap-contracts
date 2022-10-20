// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

interface IInstantRouter {
    // Structures

    /// @notice                                 Structure for recording instant requests
    /// @param user                             Address of user who recieves loan
    /// @param collateralPool                   Address of collateral pool
    /// @param paybackAmount                    Amount of (loan + instant fee)
    /// @param collateralToken                  Address of underlying collateral token
    /// @param lockedCollateralPoolTokenAmount  Amount of locked collateral pool token for getting loan
    /// @param deadline                         Deadline for paying back the loan
    struct instantRequest {
        address user;
        address collateralPool;
		address collateralToken;
        uint paybackAmount;
        uint lockedCollateralPoolTokenAmount;
        uint deadline;
    }

    // Events

    /// @notice                             Emits when a user gets loan for transfer
    /// @param user                         Address of the user who made the request
    /// @param receiver                     Address of the loan receiver
    /// @param loanAmount                   Amount of the loan
    /// @param instantFee                   Amount of the instant loan fee
    /// @param deadline                     Deadline of paying back the loan
    /// @param collateralToken              Address of the collateral token
    /// @param lockedCollateralPoolToken    Amount of collateral pool token that got locked
    event InstantTransfer(
        address indexed user, 
        address receiver, 
        uint loanAmount, 
        uint instantFee, 
        uint indexed deadline, 
        address indexed collateralToken,
        uint lockedCollateralPoolToken
    );

    /// @notice                             Emits when a user gets loan for exchange
    /// @param user                         Address of the user who made the request
    /// @param receiver                     Address of the loan receiver
    /// @param loanAmount                   Amount of the loan
    /// @param instantFee                   Amount of the instant loan fee
    /// @param amountOut                    Amount of the output token
    /// @param path                         Path of exchanging tokens
    /// @param isFixed                      Shows whether input or output is fixed in exchange
    /// @param deadline                     Deadline of getting the loan
    /// @param collateralToken              Address of the collateral token
    /// @param lockedCollateralPoolToken    Amount of collateral pool token that got locked
    event InstantExchange(
        address indexed user, 
        address receiver, 
        uint loanAmount, 
        uint instantFee,
        uint amountOut,
        address[] path,
        bool isFixed,
        uint indexed deadline, 
        address indexed collateralToken,
        uint lockedCollateralPoolToken
    );

    /// @notice                            Emits when a loan gets paid back
    /// @param user                        Address of user who recieves loan
    /// @param paybackAmount               Amount of (loan + fee) that should be paid back
    /// @param collateralToken             Address of underlying collateral token
    /// @param lockedCollateralPoolToken   Amount of locked collateral pool token for getting loan
    event PaybackLoan(
		address indexed user, 
		uint paybackAmount, 
		address indexed collateralToken, 
		uint lockedCollateralPoolToken
	);

    /// @notice                         Emits when a user gets slashed
    /// @param user                     Address of user who recieves loan
    /// @param collateralToken          Address of collateral underlying token
	/// @param slashedAmount            How much user got slashed
	/// @param paybackAmount            Address of collateral underlying token
	/// @param slasher                  Address of slasher
	/// @param slasherReward            Slasher reward (in collateral token)
    event SlashUser(
		address indexed user, 
		address indexed collateralToken, 
		uint slashedAmount, 
		uint paybackAmount,
        address slasher,
        uint slasherReward
	);

    // Read-only functions

    function pause() external;

    function unpause() external;

    function teleBTCInstantPool() external view returns (address);

    function teleBTC() external view returns (address);

    function relay() external view returns (address);

	function collateralPoolFactory() external view returns (address);

	function priceOracle() external view returns (address);

    function slasherPercentageReward() external view returns (uint);

    function paybackDeadline() external view returns (uint);

    function defaultExchangeConnector() external view returns (address);
    
    function getLockedCollateralPoolTokenAmount(address _user, uint _index) external view returns (uint);

    function getUserRequestsLength(address _user) external view returns (uint);

    function getUserRequestDeadline(address _user, uint _index) external view returns (uint);

    // State-changing functions

    function setPaybackDeadline(uint _paybackDeadline) external;

    function setSlasherPercentageReward(uint _slasherPercentageReward) external;

    function setPriceOracle(address _priceOracle) external;

    function setCollateralPoolFactory(address _collateralPoolFactory) external;

    function setRelay(address _relay) external;

    function setTeleBTC(address _teleBTC) external;

    function setTeleBTCInstantPool(address _teleBTCInstantPool) external;

    function setDefaultExchangeConnector(address _defaultExchangeConnector) external;

    function instantCCTransfer(
        address _receiver,
        uint _loanAmount,
        uint _deadline,
        address _collateralPool
    ) external returns (bool);

    function instantCCExchange(
		address _exchangeConnector,
        address _receiver,
        uint _loanAmount, 
        uint _amountOut, 
        address[] memory _path, 
        uint _deadline,
        address _collateralToken,
        bool _isFixedToken
    ) external returns (uint[] memory);

    function payBackLoan(address _user, uint _teleBTCAmount) external returns (bool);

    function slashUser(
		address _user, 
		uint _requestIndex
	) external returns (bool);

}