// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

interface IInstantRouter {
    // Structures

    /// @notice                                 Structure for recording instant requests
    /// @param user                             Address of user who recieves loan
    /// @param collateralPool                   Address of collateral pool
    /// @param collateralToken                  Address of underlying collateral token
    /// @param paybackAmount                    Amount of (loan + instant fee)
    /// @param lockedCollateralPoolTokenAmount  Amount of locked collateral pool token for getting loan
    /// @param deadline                         Deadline for paying back the loan
    /// @param requestCounterOfUser             The index of the request for a specific user
    struct instantRequest {
        address user;
        address collateralPool;
		address collateralToken;
        uint paybackAmount;
        uint lockedCollateralPoolTokenAmount;
        uint deadline;
        uint requestCounterOfUser;
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
        uint lockedCollateralPoolToken,
        uint requestCounterOfUser
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
        uint lockedCollateralPoolToken,
        uint requestCounterOfUser
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
		uint lockedCollateralPoolToken,
        uint requestCounterOfUser
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
        uint slasherReward,
        uint requestCounterOfUser
	);

    /// @notice                     	Emits when changes made to payback deadline
    event NewPaybackDeadline(
        uint oldPaybackDeadline, 
        uint newPaybackDeadline
    );

    /// @notice                     	Emits when changes made to slasher percentage reward
    event NewSlasherPercentageReward(
        uint oldSlasherPercentageReward, 
        uint newSlasherPercentageReward
    );

    /// @notice                     	Emits when changes made to TeleBTC address
    event NewTeleBTC(
        address oldTeleBTC, 
        address newTeleBTC
    );

    /// @notice                     	Emits when changes made to relay address
    event NewRelay(
        address oldRelay, 
        address newRelay
    );

    /// @notice                     	Emits when changes made to collateral pool factory address
    event NewCollateralPoolFactory(
        address oldCollateralPoolFactory, 
        address newCollateralPoolFactory
    );

    /// @notice                     	Emits when changes made to price oracle address
    event NewPriceOracle(
        address oldPriceOracle, 
        address newPriceOracle
    );

    /// @notice                     	Emits when changes made to TeleBTC instant pool address
    event NewTeleBTCInstantPool(
        address oldTeleBTCInstantPool, 
        address newTeleBTCInstantPool
    );

    /// @notice                     	Emits when changes made to default exchange connector address
    event NewDeafultExchangeConnector(
        address oldDeafultExchangeConnector, 
        address newDeafultExchangeConnector
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