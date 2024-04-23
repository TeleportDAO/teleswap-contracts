// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./EthConnectorStorage.sol";
import "./interfaces/IEthConnectorLogic.sol";

contract EthConnectorLogic is IEthConnectorLogic, EthConnectorStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0))
            revert ZeroAddress();
        _;
    }

    function initialize(
        address _polygonTeleBTC,
        address _across,
        address _wrappedNativeToken,
        uint _targetChainId
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();
        
        _setPolygonTeleBTC(_polygonTeleBTC);
        _setAcross(_across);
        _setWrappedNativeToken(_wrappedNativeToken);
        targetChainId = _targetChainId;
        _setMinModifier(ONE_HUNDRED_PERCENT);
        uniqueCounter = 0;
    }

    /// @notice Setter for min exchange amount of a token
    /// @dev Exchanging below the min amount is not possible since withdrawing 
    ///      funds in the case of failure becomes impossible (due to Across bridge fee)
    function setMinAmount(address _token, uint _minAmount) external override onlyOwner nonZeroAddress(_token){
        _setMinAmount(_token, _minAmount);
    }

    /// @notice Setter for min amount modifier
    /// @dev In the case of network fee changes, instead of 
    ///      updating min amount for all tokens, we only update this modifier
    function setMinModifier(uint _minModifier) external override onlyOwner {
        _setMinModifier(_minModifier);
    }

    /// @notice Setter for Across
    function setAcross(address _across) external override onlyOwner {
        _setAcross(_across);
    }

    /// @notice Setter for PolygonConnectorProxy
    function setPolygonConnectorProxy(address _polygonConnectorProxy) external override onlyOwner {
        _setPolygonConnectorProxy(_polygonConnectorProxy);
    }

    /// @notice Setter for PolygonTeleBTC
    function setPolygonTeleBTC(address _polygonTeleBTC) external override onlyOwner {
        _setPolygonTeleBTC(_polygonTeleBTC);
    }

    /// @notice Setter for WrappedNativeToken
    function setWrappedNativeToken(address _wrappedNativeToken) external override onlyOwner {
        _setWrappedNativeToken(_wrappedNativeToken);
    }

    // 

    function _setMinAmount(address _token, uint _minAmount) nonZeroAddress(_token) private {
        emit MinAmountUpdated(
            _token,
            _minAmount
        );

        minAmounts[_token] = _minAmount;
    }

    function _setMinModifier(uint _minModifier) private {
        emit MinModifierUpdated(
            minModifier,
            _minModifier
        );

        minModifier = _minModifier;
    }

    function _setAcross(address _across) private nonZeroAddress(_across){
        emit AcrossUpdated(
            across,
            _across
        );

        across = _across;
    }

    function _setPolygonConnectorProxy(address _polygonConnectorProxy) private nonZeroAddress(_polygonConnectorProxy){
        emit PolygonConnectorUpdated(
            polygonConnectorProxy,
            _polygonConnectorProxy
        );

        polygonConnectorProxy = _polygonConnectorProxy;
    }

    function _setPolygonTeleBTC(address _polygonTeleBTC) private nonZeroAddress(_polygonTeleBTC){
        emit PolygonTeleBtcUpdated(
            polygonTeleBTC,
            _polygonTeleBTC
        );
        
        polygonTeleBTC = _polygonTeleBTC;
    }

    function _setWrappedNativeToken(address _wrappedNativeToken) private nonZeroAddress(_wrappedNativeToken){
        emit WrappedNativeTokenUpdated(
            wrappedNativeToken,
            _wrappedNativeToken
        );
        
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @notice Withdraws tokens in the emergency case
    /// @dev Only owner can call this
    function emergencyWithdraw(
        address _token,
        address _to,
        uint _amount
    ) external override onlyOwner {
        if (_token == ETH_ADDR) 
            _to.call{value: _amount}("");
        else
            IERC20(_token).transfer(_to, _amount);
    }

    /// @notice Requests exchanging token for BTC
    /// @param _token Address of input token (on the current chain)
    /// @param _exchangeConnector Address of exchange connector to be used
    /// @param _amounts [inputTokenAmount, teleBTCAmount]
    /// @param _path of exchanging inputToken to teleBTC (these are Polygon token addresses, so _path[0] != _token)
    /// @param _userScript User script hash
    /// @param _scriptType User script type
    /// @param _lockerLockingScript	of locker that should execute the burn request
    /// @param _relayerFeePercentage Fee percentage for relayer
    /// @param thirdParty Id of third party
    function exchangeForBtcAcross(
        address _token,
        address _exchangeConnector,
        uint[] calldata _amounts,
        address[] calldata _path,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        int64 _relayerFeePercentage,
        uint thirdParty
	) external payable override nonReentrant() {

        _checkRequest(_token, _amounts, _path);

        // Sends msg to Polygon
        
        bytes memory message = abi.encode(
            "exchangeForBtcAcross",
            uniqueCounter,
            msg.sender,
            _exchangeConnector, 
            _amounts[1], // Min output amount to receive
            _path, 
            _userScript,
            _scriptType,
            _lockerLockingScript,
            thirdParty
        );
        
        emit MsgSent(
            uniqueCounter,
            "putBidAcross",
            message,
            _token,
            _amounts[0]
        );

        uniqueCounter++;

        _sendMsgUsingAcross(
            _token,
            _amounts[0],
            message,
            _relayerFeePercentage
        );
    }

    /// @notice Sends tokens and message using Across bridge
    function _sendMsgUsingAcross(
        address _token,
        uint _amount,
        bytes memory _message,
        int64 _relayerFeePercentage
    ) internal {

        if (_token == ETH_ADDR) {
            require(msg.value == _amount, "EthManagerLogic: wrong value");
            _token = wrappedNativeToken;
        } else {
            require(msg.value == 0, "EthManagerLogic: wrong value");

            // Transfers tokens from user to contract
            IERC20(_token).transferFrom(
                msg.sender,
                address(this),
                _amount
            );

            IERC20(_token).approve(
                across, 
                _amount
            );
        }

        // Calling across for transferring token and msg
        Address.functionCallWithValue(
            across,
            abi.encodeWithSignature(
                "deposit(address,address,uint256,uint256,int64,uint32,bytes,uint256)",
                polygonConnectorProxy,
                _token,
                _amount,
                targetChainId,
                _relayerFeePercentage,
                uint32(block.timestamp),
                _message,
                115792089237316195423570985008687907853269984665640564039457584007913129639935
            ),
            msg.value
        );  
    }

    /// @notice Checks validity of request
    /// @dev Token should be acceptable, input amount should be >= min, 
    ///      last token of path should be teleBTC, and amounts array length should be 2 
    function _checkRequest(
        address _token,
        uint[] calldata _amounts,
        address[] calldata _path
    ) internal view {
        // Checks that amount is greater than min
        // Note: if the amount is lower than min, 
        //       it may become impossible to withdraw funds in future
        require(
            minAmounts[_token] > 0,
            "EthManagerLogic: token not supported"
        );
        require(
            _amounts[0] >= (minAmounts[_token] * minModifier / ONE_HUNDRED_PERCENT),
            "EthManagerLogic: low amount"
        );

        //TODO remove this check
        require(
            _path[_path.length - 1] == polygonTeleBTC, 
            "EthManagerLogic: invalid path"
        );

        require(_amounts.length == 2, "EthManagerLogic: wrong amounts");
    }

    receive() external payable {}
}