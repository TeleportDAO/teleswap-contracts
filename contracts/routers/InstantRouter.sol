// SPDX-License-Identifier: MIT
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
    
    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "InstantRouter: zero address");
        _;
    }

    // Constants 
    uint constant MAX_SLASHER_PERCENTAGE_REWARD = 10000;

    // Public variables
    mapping(address => instantRequest[]) public instantRequests;
    uint public override slasherPercentageReward;
    uint public override paybackDeadline;
    address public override teleBTC;
    address public override teleBTCInstantPool;
    address public override relay;
    address public override priceOracle;
    address public override collateralPoolFactory;
    address public override defaultExchangeConnector;

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
        uint _paybackDeadline,
        address _defaultExchangeConnector
    ) {
        teleBTC = _teleBTC;
        relay = _relay;
        priceOracle = _priceOracle;
        collateralPoolFactory = _collateralPoolFactory;
        slasherPercentageReward = _slasherPercentageReward;
        require(
            slasherPercentageReward <= MAX_SLASHER_PERCENTAGE_REWARD, 
            "InstantRouter: wrong slasher percentage reward"
        );
        paybackDeadline = _paybackDeadline;
        defaultExchangeConnector = _defaultExchangeConnector;
    }

    /// @notice                  Gives the collateral amount corresponding to the request
    /// @param _user             Address of the user
    /// @param _index            Number of the instant request
    /// @return                  Amount of locked collateral
    function getLockedCollateralPoolTokenAmount(address _user, uint _index) external view override returns (uint) {
        require(_index < instantRequests[_user].length, "InstantRouter: wrong index");
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
        require(_index < instantRequests[_user].length, "InstantRouter: wrong index");
        return instantRequests[_user][_index].deadline;
    }

    /// @notice                   Changes the payback _deadline
    /// @dev                      Only owner can call this
    /// @param _paybackDeadline   The new payback _deadline
    function setPaybackDeadline(uint _paybackDeadline) external override onlyOwner {
        uint _finalizationParameter = IBitcoinRelay(relay).finalizationParameter();
        // Gives users enough time to pay back loans
        require(_paybackDeadline >= _finalizationParameter, "InstantRouter: wrong payback deadline");
        paybackDeadline = _paybackDeadline;
    }

    /// @notice                             Changes the slasher reward
    /// @dev                                Only owner can call this
    /// @param _slasherPercentageReward     The new slasher reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) external override onlyOwner {
        require(
            _slasherPercentageReward <= MAX_SLASHER_PERCENTAGE_REWARD, 
            "InstantRouter: wrong slasher percentage reward"
        );
        slasherPercentageReward = _slasherPercentageReward;
    }

    /// @notice                                 Sets the teleBTC instant pool address
    /// @dev                                    Only owner can call this
    /// @param _teleBTCInstantPool              The new teleBTC instant pool address
    function setTeleBTCInstantPool(
        address _teleBTCInstantPool
    ) external nonZeroAddress(_teleBTCInstantPool) override onlyOwner {
        teleBTCInstantPool = _teleBTCInstantPool;
    }

    /// @notice                                 Sets the teleBTC instant pool address
    /// @dev                                    Only owner can call this
    /// @param _defaultExchangeConnector        The new teleBTC instant pool address
    function setDefaultExchangeConnector(
        address _defaultExchangeConnector
    ) external nonZeroAddress(_defaultExchangeConnector) override onlyOwner {
        defaultExchangeConnector = _defaultExchangeConnector;
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
    ) external nonReentrant nonZeroAddress(_receiver) nonZeroAddress(_collateralToken) override returns (bool) {
        // Checks that deadline for getting loan has not passed
        require(_deadline >= block.timestamp, "InstantRouter: deadline has passed");

        // Gets the instant fee
        uint instantFee = IInstantPool(teleBTCInstantPool).getFee(_loanAmount);

        // Locks the required amount of user's collateral
        _lockCollateral(msg.sender, _loanAmount + instantFee, _collateralToken);

        // Gets loan from instant pool for receiver
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
    /// @param _isFixedToken      Shows whether input or output is fixed in exchange
    /// @return _amounts
    function instantCCExchange(
        address _exchangeConnector,
        address _receiver,
        uint _loanAmount,
        uint _amountOut,
        address[] memory _path,
        uint _deadline,
        address _collateralToken,
        bool _isFixedToken
    ) external nonReentrant nonZeroAddress(_exchangeConnector) override returns(uint[] memory _amounts) {
        // Checks that deadline for exchanging has not passed
        require(_deadline >= block.timestamp, "InstantRouter: deadline has passed");

        // Checks that the first token of path is teleBTC and its length is greater than one
        require(_path[0] == teleBTC && _path.length > 1, "InstantRouter: path is invalid");

        // Calculates the instant fee
        uint instantFee = IInstantPool(teleBTCInstantPool).getFee(_loanAmount);

        // Locks the required amount of user's collateral
        _lockCollateral(msg.sender, _loanAmount + instantFee, _collateralToken);

        // Gets loan from instant pool
        IInstantPool(teleBTCInstantPool).getLoan(address(this), _loanAmount);

        // Gives allowance to exchange connector
        IERC20(teleBTC).approve(_exchangeConnector, _loanAmount);

        // Exchanges teleBTC for output token
        bool result;
        (result, _amounts) = IExchangeConnector(_exchangeConnector).swap(
            _loanAmount,
            _amountOut,
            _path,
            _receiver,
            _deadline,
            _isFixedToken
        );

        /* 
            Reverts if exchanging was not successful since
            user doesn't want to lock collateral without exchanging
        */
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
    }

    /// @notice                             Settles loans of the user
    /// @param _user                        Address of the user who wants to pay back loans
    /// @param _teleBTCAmount               Amount of available teleBTC to pay back loans
    /// @return                             True if paying back is successful
    function payBackLoan(
        address _user, 
        uint _teleBTCAmount
    ) external nonReentrant nonZeroAddress(_user) override returns (bool) {
        uint remainedAmount = _teleBTCAmount;
        uint lastSubmittedHeight = IBitcoinRelay(relay).lastSubmittedHeight();

        for (uint i = 1; i <= instantRequests[_user].length; i++) {
            // Checks that remained teleBTC is enough to pay back the loan and payback deadline has not passed
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

        // Transfers remained teleBTC to user
        if (remainedAmount > 0) {
            IERC20(teleBTC).transferFrom(msg.sender, _user, remainedAmount);
        }

        return true;
    }

    /// @notice                           Slashes collateral of user who did not pay back loan
    /// @dev                              Buys teleBTC using the collateral
    /// @param _user                      Address of the slashed user
    /// @param _requestIndex              Index of the request that have not been paid back before deadline
    /// @return                           True if slashing is successful
    function slashUser(
        address _user,
        uint _requestIndex
    ) override nonReentrant nonZeroAddress(_user) external returns (bool) {

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
        (bool result, uint requiredCollateralToken) = IExchangeConnector(defaultExchangeConnector).getInputAmount(
            paybackAmount, // Output amount
            collateralToken, // Input token
            teleBTC // Output token
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
            IERC20(collateralToken).approve(defaultExchangeConnector, requiredCollateralToken);

            // Exchanges collateral token for teleBTC
            IExchangeConnector(defaultExchangeConnector).swap(
                requiredCollateralToken,
                paybackAmount, // Output amount
                path,
                teleBTCInstantPool,
                block.timestamp + 1,
                false // Output amount is fixed
            );

            uint slasherReward = (totalCollateralToken - requiredCollateralToken)
            *slasherPercentageReward/MAX_SLASHER_PERCENTAGE_REWARD;

            // Sends reward to slasher
            IERC20(collateralToken).transfer(msg.sender, slasherReward);

            // Deposits rest of the tokens to collateral pool on behalf of the user
            ICollateralPool(collateralPool).addCollateral(
                _user,
                totalCollateralToken - requiredCollateralToken - slasherReward
            );

            emit SlashUser(
                _user, 
                collateralToken, 
                requiredCollateralToken, 
                paybackAmount,
                msg.sender,
                slasherReward
            );
        } else {
            // Handles situations where locked collateral is not enough to pay back the loan

            // Approves exchange connector to use collateral token
            IERC20(collateralToken).approve(defaultExchangeConnector, totalCollateralToken);

            // Buys teleBTC as much as possible and sends it to instant pool
            IExchangeConnector(defaultExchangeConnector).swap(
                totalCollateralToken,
                0,
                path,
                teleBTCInstantPool,
                block.timestamp + 1,
                true // Input amount is fixed 
            );

            emit SlashUser(
                _user, 
                collateralToken, 
                totalCollateralToken, 
                paybackAmount,
                msg.sender,
                0 // Slasher reward is zero
            );
        }

        // Deletes the request after slashing user
        _removeElement(_user, _requestIndex);

        return true;
    }

    /// @notice             Removes an element of array of user's instant requests
    /// @dev                Deletes and shifts the array
    /// @param _user        Address of the user whose instant requests array is considered
    /// @param _index       Index of the element that will be deleted
    function _removeElement(address _user, uint _index) private {
        require(_index < instantRequests[_user].length, "InstantRouter: index is out of bound");
        for (uint i = _index; i < instantRequests[_user].length - 1; i++) {
            instantRequests[_user][i] = instantRequests[_user][i+1];
        }
        instantRequests[_user].pop();
    }

    /// @notice                   Locks the required amount of user's collateral
    /// @dev                      Records the instant request to be used in future
    /// @param _user              Address of the loan receiver
    /// @param _paybackAmount     Amount of the (loan + fee) that should be paid back
    /// @param _collateralToken   Address of the collateral
    function _lockCollateral(
        address _user,
        uint _paybackAmount,
        address _collateralToken
    ) private nonZeroAddress(_collateralToken) {
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
            _paybackAmount, // input amount
            IERC20(teleBTC).decimals(),
            IERC20(_collateralToken).decimals(),
            teleBTC, // input token
            _collateralToken // output token
        );

        // Finds needed collateral token for getting loan
        uint requiredCollateralToken = equivalentCollateralToken*collateralizationRatio/100;

        // Finds needed collateral pool token for getting loan
        uint requiredCollateralPoolToken = ICollateralPool(collateralPool).equivalentCollateralPoolToken(
            requiredCollateralToken
        );

        // Transfers collateral pool token from user to itself
        ICollateralPool(collateralPool).transferFrom(_user, address(this), requiredCollateralPoolToken);

        // Records the instant request for user
        instantRequest memory request;
        request.user = _user;
        request.paybackAmount = _paybackAmount;
        request.lockedCollateralPoolTokenAmount = requiredCollateralPoolToken;
        request.collateralPool = collateralPool;
        request.collateralToken = _collateralToken;
        request.deadline = IBitcoinRelay(relay).lastSubmittedHeight() + paybackDeadline;
        instantRequests[_user].push(request);

    }
}