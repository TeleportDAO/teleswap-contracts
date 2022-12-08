// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/IInstantRouter.sol";
import "../connectors/interfaces/IExchangeConnector.sol";
import "../pools/interfaces/IInstantPool.sol";
import "../pools/interfaces/ICollateralPool.sol";
import "../pools/interfaces/ICollateralPoolFactory.sol";
import "../erc20/interfaces/ITeleBTC.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../relay/interfaces/IBitcoinRelay.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract InstantRouter is IInstantRouter, Ownable, ReentrancyGuard, Pausable {
     using SafeERC20 for IERC20;
     
    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "InstantRouter: zero address");
        _;
    }

    // Constants
    uint constant MAX_SLASHER_PERCENTAGE_REWARD = 10000;
    uint constant MAX_INSTANT_LOAN_NUMBER = 15;

    // Public variables
    mapping(address => instantRequest[]) public instantRequests; // Mapping from user address to user's unpaid instant requests
    mapping(address => uint256) public instantRequestCounter;
    uint public override slasherPercentageReward;
    uint public override paybackDeadline;
    address public override teleBTC;
    address public override teleBTCInstantPool;
    address public override relay;
    address public override priceOracle;
    address public override collateralPoolFactory;
    address public override defaultExchangeConnector;

    /// @notice                             This contract handles instant transfer and instant exchange requests
    /// @dev                                It manages instant pool contract to give loan to users
    /// @param _teleBTC                     Address of teleBTC contract
    /// @param _relay                       Address of relay contract
    /// @param _priceOracle                 Address of price oracle contract
    /// @param _collateralPoolFactory       Address of collateral pool factory contract
    /// @param _slasherPercentageReward     Percentage of total collateral that goes to slasher
    /// @param _paybackDeadline             Deadline of paying back the borrowed tokens
    /// @param _defaultExchangeConnector    Exchange connector that is used for exchanging user's collateral to teleBTC (in the case of slashing)
    constructor(
        address _teleBTC,
        address _relay,
        address _priceOracle,
        address _collateralPoolFactory,
        uint _slasherPercentageReward,
        uint _paybackDeadline,
        address _defaultExchangeConnector
    ) {
        _setTeleBTC(_teleBTC);
        _setRelay(_relay);
        _setPriceOracle(_priceOracle);
        _setCollateralPoolFactory(_collateralPoolFactory);
        _setSlasherPercentageReward(_slasherPercentageReward);
        _setPaybackDeadline(_paybackDeadline);
        _setDefaultExchangeConnector(_defaultExchangeConnector);
    }

    receive() external payable {}

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice       Pause the contract
    function pause() external override onlyOwner {
        _pause();
    }

    /// @notice       Unpause the contract
    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @notice                  Gives the locked collateral pool token corresponding to a request
    /// @param _user             Address of the user
    /// @param _index            Index of the request in user's request list
    /// @return                  Amount of locked collateral pool token (not collateral token)
    function getLockedCollateralPoolTokenAmount(
        address _user,
        uint _index
    ) external view override returns (uint) {
        require(_index < instantRequests[_user].length, "InstantRouter: wrong index");
        return instantRequests[_user][_index].lockedCollateralPoolTokenAmount;
    }

    /// @notice                   Gives the total number of user's unpaid loans
    /// @param _user              Address of the user
    /// @return                   The total number of user's requests
    function getUserRequestsLength(address _user) external view override returns (uint) {
        return instantRequests[_user].length;
    }

    /// @notice                   Gives deadline of a specefic request
    /// @param _user              Address of the user
    /// @param _index             Index of the request in user's request list
    /// @return                   Deadline of that request
    function getUserRequestDeadline(address _user, uint _index) external view override returns (uint) {
        require(_index < instantRequests[_user].length, "InstantRouter: wrong index");
        return instantRequests[_user][_index].deadline;
    }

    /// @notice                   Setter for payback deadline
    /// @dev                      Only owner can call this. It should be greater than relay finalization parameter so user has enough time to payback loan
    /// @param _paybackDeadline   The new payback deadline
    function setPaybackDeadline(uint _paybackDeadline) external override onlyOwner {
        _setPaybackDeadline(_paybackDeadline);
    }

    /// @notice                   Fixing payback deadline after changing finalization parameter
    function fixPaybackDeadline() external {
        uint _finalizationParameter = IBitcoinRelay(relay).finalizationParameter();
        uint _paybackDeadline = 2 * _finalizationParameter + 1;
        _setPaybackDeadline(_paybackDeadline);
    }

    /// @notice                             Setter for slasher percentage reward
    /// @dev                                Only owner can call this
    /// @param _slasherPercentageReward     The new slasher reward
    function setSlasherPercentageReward(uint _slasherPercentageReward) external override onlyOwner {
        _setSlasherPercentageReward(_slasherPercentageReward);
    }

    /// @notice                                 Setter for teleBTC
    /// @dev                                    Only owner can call this
    /// @param _teleBTC                         The new teleBTC address
    function setTeleBTC(
        address _teleBTC
    ) external override onlyOwner {
        _setTeleBTC(_teleBTC);
    }

    /// @notice                                 Setter for relay
    /// @dev                                    Only owner can call this
    /// @param _relay                           The new relay address
    function setRelay(
        address _relay
    ) external override onlyOwner {
        _setRelay(_relay);
    }

    /// @notice                                 Setter for collateral pool factory
    /// @dev                                    Only owner can call this
    /// @param _collateralPoolFactory           The new collateral pool factory address
    function setCollateralPoolFactory(
        address _collateralPoolFactory
    ) external override onlyOwner {
        _setCollateralPoolFactory(_collateralPoolFactory);
    }

    /// @notice                                 Setter for price oracle
    /// @dev                                    Only owner can call this
    /// @param _priceOracle                     The new price oracle address
    function setPriceOracle(
        address _priceOracle
    ) external override onlyOwner {
        _setPriceOracle(_priceOracle);
    }

    /// @notice                                 Setter for teleBTC instant pool
    /// @dev                                    Only owner can call this
    /// @param _teleBTCInstantPool              The new teleBTC instant pool address
    function setTeleBTCInstantPool(
        address _teleBTCInstantPool
    ) external override onlyOwner {
        _setTeleBTCInstantPool(_teleBTCInstantPool);
    }

    /// @notice                                 Setter for default exchange connector
    /// @dev                                    Only owner can call this
    /// @param _defaultExchangeConnector        The new defaultExchangeConnector address
    function setDefaultExchangeConnector(
        address _defaultExchangeConnector
    ) external override onlyOwner {
        _setDefaultExchangeConnector(_defaultExchangeConnector);
    }

    /// @notice                   Internal setter for payback deadline
    /// @dev                      Only owner can call this. It should be greater than relay finalization parameter so user has enough time to payback loan
    /// @param _paybackDeadline   The new payback deadline
    function _setPaybackDeadline(uint _paybackDeadline) private {
        uint _finalizationParameter = IBitcoinRelay(relay).finalizationParameter();
        // Gives users enough time to pay back loans
        require(_paybackDeadline >= 2 * _finalizationParameter + 1, "InstantRouter: wrong payback deadline");
        emit NewPaybackDeadline(paybackDeadline, _paybackDeadline);
        paybackDeadline = _paybackDeadline;
    }

    /// @notice                             Internal setter for slasher percentage reward
    /// @dev                                Only owner can call this
    /// @param _slasherPercentageReward     The new slasher reward
    function _setSlasherPercentageReward(uint _slasherPercentageReward) private {
        require(
            _slasherPercentageReward <= MAX_SLASHER_PERCENTAGE_REWARD,
            "InstantRouter: wrong slasher percentage reward"
        );
        emit NewSlasherPercentageReward(slasherPercentageReward, _slasherPercentageReward);
        slasherPercentageReward = _slasherPercentageReward;
    }

    /// @notice                                 Internal setter for teleBTC instant
    /// @param _teleBTC                         The new teleBTC instant address
    function _setTeleBTC(
        address _teleBTC
    ) private nonZeroAddress(_teleBTC) {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
    }

    /// @notice                                 Internal setter for relay
    /// @param _relay                           The new relay address
    function _setRelay(
        address _relay
    ) private nonZeroAddress(_relay) {
        emit NewRelay(relay, _relay);
        relay = _relay;
    }

    /// @notice                                 Internal setter for collateral pool factory
    /// @param _collateralPoolFactory           The new collateral pool factory address
    function _setCollateralPoolFactory(
        address _collateralPoolFactory
    ) private nonZeroAddress(_collateralPoolFactory) {
        emit NewCollateralPoolFactory(collateralPoolFactory, _collateralPoolFactory);
        collateralPoolFactory = _collateralPoolFactory;
    }

    /// @notice                                 Internal setter for price oracle
    /// @param _priceOracle                     The new price oracle address
    function _setPriceOracle(
        address _priceOracle
    ) private nonZeroAddress(_priceOracle) {
        emit NewPriceOracle(priceOracle, _priceOracle);
        priceOracle = _priceOracle;
    }

    /// @notice                                 Internal setter for teleBTC instant pool
    /// @param _teleBTCInstantPool              The new teleBTC instant pool address
    function _setTeleBTCInstantPool(
        address _teleBTCInstantPool
    ) private nonZeroAddress(_teleBTCInstantPool) {
        emit NewTeleBTCInstantPool(teleBTCInstantPool, _teleBTCInstantPool);
        teleBTCInstantPool = _teleBTCInstantPool;
    }

    /// @notice                                 Internal setter for default exchange connector
    /// @param _defaultExchangeConnector        The new defaultExchangeConnector address
    function _setDefaultExchangeConnector(
        address _defaultExchangeConnector
    ) private nonZeroAddress(_defaultExchangeConnector) {
        emit NewDeafultExchangeConnector(defaultExchangeConnector, _defaultExchangeConnector);
        defaultExchangeConnector = _defaultExchangeConnector;
    }

    /// @notice                   Transfers the loan amount (in teleBTC) to the user
    /// @dev                      Transfes required collateral pool token of user to itself. Only works when contract is not paused.
    /// @param _receiver          Address of the loan receiver
    /// @param _loanAmount        Amount of the loan
    /// @param _deadline          Deadline for getting the loan
    /// @param _collateralToken   Address of the collateral token
    /// @return                   True if getting loan was successful
    function instantCCTransfer(
        address _receiver,
        uint _loanAmount,
        uint _deadline,
        address _collateralToken
    ) external nonReentrant nonZeroAddress(_receiver) nonZeroAddress(_collateralToken)
    whenNotPaused override returns (bool) {
        // Checks that deadline for getting loan has not passed
        require(_deadline >= block.timestamp, "InstantRouter: deadline has passed");

        // Gets the instant fee
        uint instantFee = IInstantPool(teleBTCInstantPool).getFee(_loanAmount);

        // Locks the required amount of user's collateral
        _lockCollateral(_msgSender(), _loanAmount + instantFee, _collateralToken);

        // Gets loan from instant pool for receiver
        IInstantPool(teleBTCInstantPool).getLoan(_receiver, _loanAmount);

        emit InstantTransfer(
            _msgSender(),
            _receiver,
            _loanAmount,
            instantFee,
            instantRequests[_msgSender()][instantRequests[_msgSender()].length - 1].deadline,
            _collateralToken,
            instantRequests[_msgSender()][instantRequests[_msgSender()].length - 1].lockedCollateralPoolTokenAmount,
            instantRequests[_msgSender()][instantRequests[_msgSender()].length - 1].requestCounterOfUser
        );

        return true;
    }

    /// @notice                   Exchanges the loan amount (in teleBTC) for the user
    /// @dev                      Locks the required collateral amount of the user. Only works when contract is not paused.
    /// @param _exchangeConnector Address of exchange connector that user wants to exchange the borrowed teleBTC in it
    /// @param _receiver          Address of the loan receiver
    /// @param _loanAmount        Amount of the loan
    /// @param _amountOut         Amount of the output token
    /// @param _path              Path of exchanging tokens
    /// @param _deadline          Deadline for getting the loan
    /// @param _collateralToken   Address of collateral token
    /// @param _isFixedToken      Shows whether input or output is fixed in exchange
    /// @return _amounts          Amounts of tokens involved in the exchange
    function instantCCExchange(
        address _exchangeConnector,
        address _receiver,
        uint _loanAmount,
        uint _amountOut,
        address[] memory _path,
        uint _deadline,
        address _collateralToken,
        bool _isFixedToken
    ) external nonReentrant nonZeroAddress(_exchangeConnector)
    whenNotPaused override returns(uint[] memory _amounts) {
        // Checks that deadline for exchanging has not passed
        require(_deadline >= block.timestamp, "InstantRouter: deadline has passed");

        // Checks that the first token of path is teleBTC and its length is greater than one
        require(_path[0] == teleBTC && _path.length > 1, "InstantRouter: path is invalid");

        // Calculates the instant fee
        uint instantFee = IInstantPool(teleBTCInstantPool).getFee(_loanAmount);

        // Locks the required amount of user's collateral
        _lockCollateral(_msgSender(), _loanAmount + instantFee, _collateralToken);

        // Gets loan from instant pool
        IInstantPool(teleBTCInstantPool).getLoan(address(this), _loanAmount);

        // Gives allowance to exchange connector
        ITeleBTC(teleBTC).approve(_exchangeConnector, _loanAmount);

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
            _msgSender(),
            _receiver,
            _loanAmount,
            instantFee,
            _amountOut,
            _path,
            _isFixedToken,
            instantRequests[_msgSender()][instantRequests[_msgSender()].length - 1].deadline, // payback deadline
            _collateralToken,
            instantRequests[_msgSender()][instantRequests[_msgSender()].length - 1].lockedCollateralPoolTokenAmount,
            instantRequests[_msgSender()][instantRequests[_msgSender()].length - 1].requestCounterOfUser
        );
    }

    /// @notice                             Settles loans of the user
    /// @dev                                Caller should give allowance for teleBTC to instant router
    /// @param _user                        Address of user who wants to pay back loans
    /// @param _teleBTCAmount               Amount of available teleBTC to pay back loans
    /// @return                             True if paying back is successful
    function payBackLoan(
        address _user,
        uint _teleBTCAmount
    ) external nonReentrant nonZeroAddress(_user) override returns (bool) {
        uint remainedAmount = _teleBTCAmount;
        uint lastSubmittedHeight = IBitcoinRelay(relay).lastSubmittedHeight();

        uint amountToTransfer = 0;

        for (uint i = 1; i <= instantRequests[_user].length; i++) {

            // Checks that remained teleBTC is enough to pay back the loan and payback deadline has not passed
            if (
                remainedAmount >= instantRequests[_user][i-1].paybackAmount &&
                instantRequests[_user][i-1].deadline >= lastSubmittedHeight
            ) {
                remainedAmount = remainedAmount - instantRequests[_user][i-1].paybackAmount;

                // Pays back the loan to instant pool
                amountToTransfer += instantRequests[_user][i-1].paybackAmount;

                // Unlocks the locked collateral pool token after paying the loan
                IERC20(instantRequests[_user][i-1].collateralPool).safeTransfer(
                    _user,
                    instantRequests[_user][i-1].lockedCollateralPoolTokenAmount
                );

                emit PaybackLoan(
                    _user,
                    instantRequests[_user][i-1].paybackAmount,
                    instantRequests[_user][i-1].collateralToken,
                    instantRequests[_user][i-1].lockedCollateralPoolTokenAmount,
                    instantRequests[_user][i-1].requestCounterOfUser
                );

                // Deletes the request after paying it
                _removeElement(_user, i-1);
                i--;
            }

            if (remainedAmount == 0) {
                break;
            }
        }

        ITeleBTC(teleBTC).transferFrom(
            _msgSender(),
            teleBTCInstantPool,
            amountToTransfer
        );

        // Transfers remained teleBTC to user
        if (remainedAmount > 0) {
            ITeleBTC(teleBTC).transferFrom(_msgSender(), _user, remainedAmount);
        }

        return true;
    }

    /// @notice                           Slashes collateral of user who did not pay back loan before its deadline
    /// @dev                              Buys teleBTC using the collateral and sends it to instant pool
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
        instantRequest memory theRequest = instantRequests[_user][_requestIndex];

        // Finds needed collateral token to pay back loan
        (bool result, uint requiredCollateralToken) = IExchangeConnector(defaultExchangeConnector).getInputAmount(
            theRequest.paybackAmount, // Output amount
            theRequest.collateralToken, // Input token
            teleBTC // Output token
        );

        require(result == true, "InstantRouter: liquidity pool doesn't exist");

        uint totalCollateralToken = ICollateralPool(theRequest.collateralPool).equivalentCollateralToken(
            theRequest.lockedCollateralPoolTokenAmount
        );

        // Path of exchanging
        address[] memory path = new address[](2);
        path[0] = theRequest.collateralToken;
        path[1] = teleBTC;

        // Gets collateral token from collateral pool
        ICollateralPool(theRequest.collateralPool).removeCollateral(theRequest.lockedCollateralPoolTokenAmount);

        // Checks that locked collateral is enough to pay back loan
        if (totalCollateralToken >= requiredCollateralToken) {
            // Approves exchange connector to use collateral token
            IERC20(theRequest.collateralToken).approve(defaultExchangeConnector, requiredCollateralToken);

            // Exchanges collateral token for teleBTC
            IExchangeConnector(defaultExchangeConnector).swap(
                requiredCollateralToken,
                theRequest.paybackAmount, // Output amount
                path,
                teleBTCInstantPool,
                block.timestamp + 1,
                false // Output amount is fixed
            );

            // Sends reward to slasher
            uint slasherReward = (totalCollateralToken - requiredCollateralToken)
            *slasherPercentageReward/MAX_SLASHER_PERCENTAGE_REWARD;
            IERC20(theRequest.collateralToken).safeTransfer(_msgSender(), slasherReward);

            IERC20(teleBTC).approve(theRequest.collateralPool, totalCollateralToken - requiredCollateralToken - slasherReward);

            // Deposits rest of the tokens to collateral pool on behalf of the user
            ICollateralPool(theRequest.collateralPool).addCollateral(
                _user,
                totalCollateralToken - requiredCollateralToken - slasherReward
            );

            emit SlashUser(
                _user,
                theRequest.collateralToken,
                requiredCollateralToken,
                theRequest.paybackAmount,
                _msgSender(),
                slasherReward,
                theRequest.requestCounterOfUser
            );
        } else { // Handles situations where locked collateral is not enough to pay back the loan

            // Approves exchange connector to use collateral token
            IERC20(theRequest.collateralToken).approve(defaultExchangeConnector, totalCollateralToken);

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
                theRequest.collateralToken,
                totalCollateralToken,
                theRequest.paybackAmount,
                _msgSender(),
                0, // Slasher reward is zero,
                theRequest.requestCounterOfUser
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
    /// @param _paybackAmount     Amount of the (loan + fee) that should be paid back by user
    /// @param _collateralToken   Address of the collateral token
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

        require(
            instantRequests[_user].length < MAX_INSTANT_LOAN_NUMBER,
            "InstantRouter: reached max loan number"
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
            ITeleBTC(teleBTC).decimals(),
            ITeleBTC(_collateralToken).decimals(),
            teleBTC, // input token
            _collateralToken // output token
        );

        // Finds needed collateral token for getting loan
        uint requiredCollateralToken = equivalentCollateralToken*collateralizationRatio/MAX_SLASHER_PERCENTAGE_REWARD;

        // Finds needed collateral pool token for getting loan
        uint requiredCollateralPoolToken = ICollateralPool(collateralPool).equivalentCollateralPoolToken(
            requiredCollateralToken
        );

        // Transfers collateral pool token from user to itself
        IERC20(collateralPool).safeTransferFrom(_user, address(this), requiredCollateralPoolToken);

        // Records the instant request for user
        instantRequest memory request;
        request.user = _user;
        request.paybackAmount = _paybackAmount;
        request.lockedCollateralPoolTokenAmount = requiredCollateralPoolToken;
        request.collateralPool = collateralPool;
        request.collateralToken = _collateralToken;
        request.deadline = IBitcoinRelay(relay).lastSubmittedHeight() + paybackDeadline;
        request.requestCounterOfUser = instantRequestCounter[_user];
        instantRequestCounter[_user] = instantRequestCounter[_user] + 1;
        instantRequests[_user].push(request);

    }
}