pragma solidity ^0.8.0;

import './interfaces/IInstantRouter.sol';
import '../connectors/interfaces/IExchangeConnector.sol';
import '../pools/interfaces/IInstantPool.sol';
import '../pools/interfaces/ICollateralPool.sol';
import '../pools/interfaces/ICollateralPoolFactory.sol';
import '../erc20/interfaces/IERC20.sol';
import '../oracle/interfaces/IPriceOracle.sol';
import "../relay/interfaces/IBitcoinRelay.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "hardhat/console.sol"; // Just for test

contract InstantRouter is IInstantRouter, Ownable, ReentrancyGuard {
    
    mapping(address => instantRequest[]) public instantRequests;
    mapping(address => bool) public override exchangeConnectors;
    uint public override slasherPercentageReward;
    uint public override paybackDeadline;
    address public override teleBTC;
    address public override teleBTCInstantPool;
    address public override relay;
	address public override priceOracle;
	address public override collateralPoolFactory;

    /// @notice                             This contract handles instant transfer and instant exchange requests
    /// @dev                                It manages instant pool contract
    /// @param _teleBTC                     Address of teleBTC contract
    /// @param _relay                       Address of price oracle contract
	/// @param _priceOracle                 Address of collateral pool factory contract
	/// @param _collateralPoolFactory       Address of relay contract
    /// @param _slasherPercentageReward     Percentage of total collateral that goes to slasher
    /// @param _paybackDeadline             Dealine of paying back the borrowed tokens from instant pool
    constructor(
        address _teleBTC,
        address _relay,
		address _priceOracle,
		address _collateralPoolFactory,
        uint _slasherPercentageReward,
        uint _paybackDeadline
    ) public {
        teleBTC = _teleBTC;
        relay = _relay;
		priceOracle = _priceOracle;
		collateralPoolFactory = _collateralPoolFactory;
        slasherPercentageReward = _slasherPercentageReward;
        paybackDeadline = _paybackDeadline;
    }

    /// @notice                  Gives the collateral amount corresponding to the request
    /// @param _user             Address of the user
    /// @param _index            Number of the instant request
    /// @return                  Amount of locked collateral
    function getLockedCollateralPoolTokenAmount(address _user, uint _index) external view override returns (uint) {
        return instantRequests[_user][_index].lockedCollateralPoolTokenAmount;
    }

    /// @notice                   Gives the total number of user's requests                  
    /// @param _user              Address of the user
    /// @return                   The total number of user's requests
    function getUserRequestsLength(address _user) external view override returns (uint) {
        return instantRequests[_user].length;
    }

    /// @notice                   Gives the user request deadline                 
    /// @param _user              Address of the user
    /// @param _index             Index of the request in user request list
    /// @return                   The deadline of that request
    function getUserRequestDeadline(address _user, uint _index) external view override returns (uint) {
        return instantRequests[_user][_index].deadline;
    }

    /// @notice                   Changes the payback _deadline
    /// @dev                      Only owner can call this
    /// @param _paybackDeadline   The new payback _deadline
    function setPaybackDeadline(uint _paybackDeadline) external override onlyOwner {
        paybackDeadline = _paybackDeadline;
    }

    /// @notice                             Changes the slasher reward
    /// @dev                                Only owner can call this
    /// @param _slasherPercentageReward     The new slasher reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) external override onlyOwner {
        slasherPercentageReward = _slasherPercentageReward;
    }
    
    /// @notice                                 Sets the teleBTC instant pool address
    /// @dev                                    Only owner can call this
    /// @param _teleBTCInstantPool              The new teleBTC instant pool address
    function setTeleBTCInstantPool(address _teleBTCInstantPool) external override onlyOwner {
        teleBTCInstantPool = _teleBTCInstantPool;
    }

    function addExchangeConnector(address _exchangeConnector) external override onlyOwner {
        exchangeConnectors[_exchangeConnector] = true;
    }

    function removeExchangeConnector(address _exchangeConnector) external override onlyOwner {
        exchangeConnectors[_exchangeConnector] = false;
    }

    /// @notice                   Transfers the loan amount to the user
    /// @dev                      Transfes required collateral pool token of user to itself
    /// @param _receiver          Address of the loan receiver
    /// @param _loanAmount        Amount of the loan
    /// @param _deadline          Deadline of getting the loan
    /// @param _collateralToken   Address of the collateral token
    /// @return                   True if getting loan was successful
    function instantCCTransfer(
        address _receiver, 
        uint _loanAmount, 
        uint _deadline, 
        address _collateralToken
    ) external nonReentrant override returns (bool) {
		// Checks that deadline for getting loan has not passed
        require(_deadline >= block.timestamp, "InstantRouter: deadline has passed");

        // Calculates the instant fee
        uint instantFee = IInstantPool(teleBTCInstantPool).instantPercentageFee()*_loanAmount/10000;

        // Locks the required amount of user's collateral
        _lockCollateral(msg.sender, _loanAmount + instantFee, _collateralToken);

        // Gets loan from instant pool
        IInstantPool(teleBTCInstantPool).getLoan(_receiver, _loanAmount);

        emit InstantTransfer(
            msg.sender, 
            _receiver, 
            _loanAmount, 
            instantFee,
            instantRequests[msg.sender][instantRequests[msg.sender].length - 1].deadline, 
            _collateralToken
        );
        return true;
    }

    /// @notice                   Exchanges the loan amount instantly for the user
    /// @dev                      Locks the required collateral amount of the user
    /// @param _receiver          Address of the loan receiver
    /// @param _loanAmount        Amount of the loan
    /// @param _amountOut         Amount of the output token
    /// @param _path              Path of exchanging tokens
    /// @param _deadline          Deadline of getting the loan
    /// @param _collateralToken   Address of collateral token
    /// @param _isFixedToken           Shows whether input or output is fixed in exchange
    /// @return                   
    function instantCCExchange(
		address _exchangeConnector,
        address _receiver,
        uint _loanAmount, 
        uint _amountOut, 
        address[] memory _path, 
        uint _deadline,
        address _collateralToken,
        bool _isFixedToken
    ) external nonReentrant override returns(uint[] memory) {
		// Checks that deadline for exchanging has not passed 
        require(_deadline >= block.timestamp, "InstantRouter: deadline has passed");

		// Checks that the first token in teleBTC
        require(_path[0] == teleBTC, "InstantRouter: input token is not valid");

        // Calculates the instant fee
        uint instantFee = IInstantPool(teleBTCInstantPool).instantPercentageFee()*_loanAmount/10000;

        // Locks the required amount of user's collateral
        _lockCollateral(msg.sender, _loanAmount + instantFee, _collateralToken);

        // Gets loan from instant pool
        IInstantPool(teleBTCInstantPool).getLoan(address(this), _loanAmount);

        // Gives allowance to exchange connector
        IERC20(teleBTC).approve(_exchangeConnector, _loanAmount);

        // Exchanges teleBTC for output token
		(bool result, uint[] memory amounts) = IExchangeConnector(_exchangeConnector).swap(
			_loanAmount,
			_amountOut,
			_path,
			_receiver,
			_deadline,
			_isFixedToken
		);

		// Checks the exchanging result
		require(result == true, "InstantRouter: exchange was not successful");

        emit InstantExchange(
            msg.sender, 
            _receiver, 
            _loanAmount,
            instantFee,
            _amountOut,
            _path,
            _isFixedToken,
            instantRequests[msg.sender][instantRequests[msg.sender].length - 1].deadline, // payback deadline
            _collateralToken
        );
        return amounts;
    }

    /// @notice                             Settles loans of the user                
    /// @param _user                        Address of the user who wants to pay back loans
    /// @param _teleBTCAmount               Amount of available teleBTC to pay back loans
    /// @return                             True if paying back is successful
    function payBackLoan(address _user, uint _teleBTCAmount) external nonReentrant override returns (bool) {
        uint remainedAmount = _teleBTCAmount;
        uint lastSubmittedHeight = IBitcoinRelay(relay).lastSubmittedHeight();

        for (uint i = 1; i <= instantRequests[_user].length; i++) {
            if (
                remainedAmount >= instantRequests[_user][i-1].paybackAmount && 
                instantRequests[_user][i-1].deadline >= lastSubmittedHeight
            ) {
                remainedAmount = remainedAmount - instantRequests[_user][i-1].paybackAmount;

                // Pays back the loan to instant pool
                IERC20(teleBTC).transferFrom(
                    msg.sender, 
                    teleBTCInstantPool, 
                    instantRequests[_user][i-1].paybackAmount
                );

                // Unlocks the locked collateral pool token after paying the loan
                ICollateralPool(instantRequests[_user][i-1].collateralPool).transfer(
                    _user, 
                    instantRequests[_user][i-1].lockedCollateralPoolTokenAmount
                );

                emit PaybackLoan(
                    _user, 
                    instantRequests[_user][i-1].paybackAmount, 
                    instantRequests[_user][i-1].collateralToken,
                    instantRequests[_user][i-1].lockedCollateralPoolTokenAmount
                );

                // Deletes the request after paying it
                _removeElement(_user, i-1);
                i--;
            }

            if (remainedAmount == 0) {
                break;
            }
        }

        // Transfers rest of teleBTC to user
        if (remainedAmount > 0) {
            IERC20(teleBTC).transferFrom(msg.sender, _user, remainedAmount);
        }

        return true;
    }

    /// @notice                           Slashes collateral of user who did not pay back loan
    /// @dev                              Buys teleBTC using the collateral
	/// @param _exchangeConnector         Address of the slashed user
    /// @param _user                      Address of the slashed user
    /// @param _requestIndex              Index of the request that have not been paid back before deadline
    /// @return                           True if slashing is successful
    function slashUser(
		address _exchangeConnector, 
		address _user, 
		uint _requestIndex
	) override nonReentrant external returns (bool) {
        require(exchangeConnectors[_exchangeConnector], "InstantRouter: exchange connector is not acceptable");
        require(instantRequests[_user].length > _requestIndex, "InstantRouter: request index does not exist");

		// Gets last submitted height on relay
		uint lastSubmittedHeight = IBitcoinRelay(relay).lastSubmittedHeight();

		// Checks that deadline has passed
        require(
            instantRequests[_user][_requestIndex].deadline < lastSubmittedHeight, 
            "InstantRouter: deadline has not passed yet"
        );

		// Gets loan information
        uint lockedCollateralPoolTokenAmount = instantRequests[_user][_requestIndex].lockedCollateralPoolTokenAmount;
        address collateralToken = instantRequests[_user][_requestIndex].collateralToken;
		address collateralPool = instantRequests[_user][_requestIndex].collateralPool;
        uint paybackAmount = instantRequests[_user][_requestIndex].paybackAmount;

		// Finds needed collateral token to pay back loan
		(bool result, uint requiredCollateralToken) = IExchangeConnector(_exchangeConnector).getInputAmount(
			paybackAmount,
			collateralToken,
			teleBTC
		);
		uint totalCollateralToken = ICollateralPool(collateralPool).equivalentCollateralToken(
			lockedCollateralPoolTokenAmount
		);

		// Path of exchanging
        address[] memory path = new address[](2);
        path[0] = collateralToken;
        path[1] = teleBTC;

        // Gets collateral token from collateral pool
        ICollateralPool(collateralPool).removeCollateral(lockedCollateralPoolTokenAmount);

        // Checks that locked collateral is enough to pay back loan
        if (totalCollateralToken >= requiredCollateralToken && result == true) {
            // Approves exchange connector to use collateral token
            IERC20(collateralToken).approve(_exchangeConnector, requiredCollateralToken);

			// Exchanges collateral token for teleBTC
			IExchangeConnector(_exchangeConnector).swap(
				requiredCollateralToken, 
				paybackAmount, 
				path, 
				teleBTCInstantPool, 
				block.timestamp + 1, 
				false
			);

            uint remainedCollateralToken = totalCollateralToken - requiredCollateralToken;
            uint slasherReward = remainedCollateralToken*slasherPercentageReward/100;

            // Sends reward to slasher 
            IERC20(collateralToken).transfer(msg.sender, slasherReward);

            // Deposits rest of the tokens to collateral pool
            ICollateralPool(collateralPool).addCollateral(_user, remainedCollateralToken - slasherReward);

			emit SlashUser(_user, collateralToken, requiredCollateralToken, paybackAmount);
        } else {
            // Approves exchange connector to use collateral token
            IERC20(collateralToken).approve(_exchangeConnector, totalCollateralToken);
            
            // Buys teleBTC as much as possible and sends it to instant pool
			IExchangeConnector(_exchangeConnector).swap(
				totalCollateralToken, 
				0,
				path, 
				teleBTCInstantPool, 
				block.timestamp + 1, 
				true
			);

			emit SlashUser(_user, collateralToken, totalCollateralToken, paybackAmount);
        }

        // Deletes the request after slashing user
        _removeElement(_user, _requestIndex);

        return true;
    }

    /// @notice             Removes an element of array of user's instant requests
    /// @dev                Deletes and shifts the array  
    /// @param _user        Address of the user whose instant requests array is considered
    /// @param _index       Index of the element that will be deleted
    function _removeElement(address _user, uint _index) internal {
        require(_index < instantRequests[_user].length, "InstantRouter: index is out of bound");
        for (uint i = _index; i < instantRequests[_user].length - 1; i++) {
            instantRequests[_user][i] = instantRequests[_user][i+1];
        }
        instantRequests[_user].pop();
    }

    /// @notice                   Locks the required amount of user's collateral 
    /// @dev                      Records the instant request to be used in future
    /// @param _user              Address of the loan receiver
    /// @param _payBackAmount     Amount of the (loan + fee) that should be paid back
    /// @param _collateralToken   Address of the collateral
    /// @return                   True if collateral is locked successfully
    function _lockCollateral(
		address _user, 
		uint _payBackAmount, 
		address _collateralToken
	) internal returns (bool) {
		// Checks that collateral token is acceptable
        require(
			ICollateralPoolFactory(collateralPoolFactory).isCollateral(_collateralToken), 
			"InstantRouter: collateral token is not acceptable"
		);

        // Gets the collateral pool address
        address collateralPool = ICollateralPoolFactory(collateralPoolFactory).getCollateralPoolByToken(
			_collateralToken
		);
		
		// Gets collateralization ratio
        uint collateralizationRatio = ICollateralPool(collateralPool).collateralizationRatio();
        
		// Gets the equivalent amount of collateral token
        uint equivalentCollateralToken = IPriceOracle(priceOracle).equivalentOutputAmount(
            _payBackAmount, // input amount
			IERC20(teleBTC).decimals(),
			IERC20(_collateralToken).decimals(),
            teleBTC, 
            _collateralToken // output token
        );

		// Finds needed collateral token for getting loan
        uint requiredCollateralToken = equivalentCollateralToken*collateralizationRatio/100;
		uint requiredCollateralPoolToken = ICollateralPool(collateralPool).equivalentCollateralPoolToken(
			requiredCollateralToken
		);

		// Transfers collateral pool token from user to itself
        ICollateralPool(collateralPool).transferFrom(_user, address(this), requiredCollateralPoolToken);

        // Records the instant request
        instantRequest memory request;
        request.user = _user;
        request.paybackAmount = _payBackAmount;
        request.lockedCollateralPoolTokenAmount = requiredCollateralPoolToken;
        request.collateralPool = collateralPool;
        request.collateralToken = _collateralToken;
        request.deadline = IBitcoinRelay(relay).lastSubmittedHeight() + paybackDeadline;
        instantRequests[_user].push(request);
    }
}