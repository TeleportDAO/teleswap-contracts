// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./EthConnectorStorage.sol";
import "./interfaces/IEthConnector.sol";

contract EthConnectorLogic is
    IEthConnector,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    EthConnectorStorage
{
    error ZeroAddress();
    using SafeERC20 for IERC20;

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    function initialize(
        address _targetChainTeleBTC,
        address _across,
        address _wrappedNativeToken,
        uint256 _targetChainId,
        uint256 _currChainId
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        _setTargetChainTeleBTC(_targetChainTeleBTC);
        _setAcross(_across);
        _setWrappedNativeToken(_wrappedNativeToken);
        targetChainId = _targetChainId;
        currChainId = _currChainId;
        uniqueCounter = 0;
    }

    receive() external payable {}

    /// @notice Setter for Across
    function setAcross(address _across) external override onlyOwner {
        _setAcross(_across);
    }

    /// @notice Setter for TargetChainConnectorProxy
    function setTargetChainConnectorProxy(
        address _targetChainConnectorProxy
    ) external override onlyOwner {
        _setTargetChainConnectorProxy(_targetChainConnectorProxy);
    }

    /// @notice Setter for TargetChainTeleBTC
    function setTargetChainTeleBTC(
        address _targetChainTeleBTC
    ) external override onlyOwner {
        _setTargetChainTeleBTC(_targetChainTeleBTC);
    }

    /// @notice Setter for WrappedNativeToken
    function setWrappedNativeToken(
        address _wrappedNativeToken
    ) external override onlyOwner {
        _setWrappedNativeToken(_wrappedNativeToken);
    }

    /// @notice Withdraw tokens in the emergency case
    /// @dev Only owner can call this
    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external override onlyOwner {
        if (_token == ETH_ADDR) _to.call{value: _amount}("");
        else IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Request exchanging token for BTC
    /// @dev To find teleBTCAmount, _relayerFeePercentage should be reduced from the inputTokenAmount
    /// @param _token Address of input token (on the current chain)
    /// @param _exchangeConnector Address of exchange connector to be used
    /// @param _amounts [inputTokenAmount, teleBTCAmount]
    /// @param _path of exchanging inputToken to teleBTC (these are Polygon token addresses, so _path[0] != _token)
    /// @param _relayerFeePercentage Fee percentage for relayer
    /// @param _thirdParty Id of third party
    function swapAndUnwrap(
        address _token,
        address _exchangeConnector,
        uint256[] calldata _amounts,
        bool _isInputFixed,
        address[] calldata _path,
        UserAndLockerScript calldata _userAndLockerScript,
        int64 _relayerFeePercentage,
        uint256 _thirdParty
    ) external payable override nonReentrant {
        if (_token == ETH_ADDR) {
            require(msg.value == _amounts[0], "EthConnectorLogic: wrong value");
        } else {
            require(msg.value == 0, "EthConnectorLogic: wrong fee");
        }

        // Send msg to Polygon
        bytes memory message = abi.encode(
            "swapAndUnwrap",
            uniqueCounter,
            currChainId,
            _msgSender(),
            _exchangeConnector,
            _amounts[1],
            _isInputFixed,
            _path,
            _userAndLockerScript,
            _thirdParty
        );

        emit MsgSent(uniqueCounter, message, _token, _amounts[0]);

        uniqueCounter++;

        _sendMsgUsingAcross(
            _token,
            _amounts[0],
            message,
            _relayerFeePercentage
        );
    }

    /// @notice Request exchanging token for RUNE
    /// @dev To find runeAmount, _relayerFeePercentage should be reduced from the inputTokenAmount
    /// @param _token Address of input token (on the current chain)
    function swapAndUnwrapRune(
        address _token,
        uint256 _appId,
        uint256[] calldata _amounts, // [inputTokenAmount, runeAmount]
        uint256 _internalId,
        address[] calldata _path,
        UserScript calldata _userScript,
        int64 _relayerFeePercentage,
        uint256 _thirdParty
    ) external payable override nonReentrant {
        if (_token == ETH_ADDR) {
            require(
                msg.value == _amounts[0] + unwrapFee,
                "EthConnectorLogic: wrong value"
            );
        } else {
            require(msg.value == unwrapFee, "EthConnectorLogic: wrong fee");
        }

        // Send msg to Polygon
        bytes memory message = abi.encode(
            "swapAndUnwrapRune",
            uniqueCounter,
            currChainId,
            _msgSender(),
            _appId,
            _amounts[1],
            _internalId,
            _path,
            _userScript,
            _thirdParty
        );

        emit MsgSentRune(uniqueCounter, message, _token, _amounts[0]);

        uniqueCounter++;

        _sendMsgUsingAcross(
            _token,
            _amounts[0],
            message,
            _relayerFeePercentage
        );
    }

    // /// @notice Request exchanging token for RUNE
    // /// @dev To find runeAmount, _relayerFeePercentage should be reduced from the inputTokenAmount
    // /// @param _token Address of input token (on the current chain)
    // function generalSwapAndUnwrap(
    //     string calldata _swapType,
    //     address _token,
    //     uint _amount,
    //     bytes calldata _message,
    //     int64 _relayerFeePercentage
    // ) external payable nonReentrant {

    //     // Send msg to Polygon
    //     bytes memory finalMessage = abi.encode(
    //         _swapType,
    //         uniqueCounter,
    //         currChainId,
    //         _msgSender(),
    //         _message
    //     );

    //     // emit GeneralMsgSent(_token, _amount, finalMessage);

    //     uniqueCounter++;

    //     _sendMsgUsingAcross(
    //         _token,
    //         _amount,
    //         finalMessage,
    //         _relayerFeePercentage
    //     );
    // }

    /// @notice Send tokens and message using Across bridge
    function _sendMsgUsingAcross(
        address _token,
        uint256 _amount,
        bytes memory _message,
        int64 _relayerFeePercentage
    ) internal {
        if (_token == ETH_ADDR) {
            _token = wrappedNativeToken;
        } else {
            // Transfer tokens from user to contract
            IERC20(_token).safeTransferFrom(
                _msgSender(),
                address(this),
                _amount
            );
            IERC20(_token).safeApprove(across, _amount);
        }

        // Call across for transferring token and msg
        Address.functionCallWithValue(
            across,
            abi.encodeWithSignature(
                "deposit(address,address,uint256,uint256,int64,uint32,bytes,uint256)",
                targetChainConnectorProxy,
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

    function _setAcross(address _across) private nonZeroAddress(_across) {
        emit AcrossUpdated(across, _across);
        across = _across;
    }

    function _setTargetChainConnectorProxy(
        address _targetChainConnectorProxy
    ) private nonZeroAddress(_targetChainConnectorProxy) {
        emit TargetChainConnectorUpdated(
            targetChainConnectorProxy,
            _targetChainConnectorProxy
        );

        targetChainConnectorProxy = _targetChainConnectorProxy;
    }

    function _setTargetChainTeleBTC(
        address _targetChainTeleBTC
    ) private nonZeroAddress(_targetChainTeleBTC) {
        emit TargetChainTeleBTCUpdated(targetChainTeleBTC, _targetChainTeleBTC);
        targetChainTeleBTC = _targetChainTeleBTC;
    }

    function _setWrappedNativeToken(
        address _wrappedNativeToken
    ) private nonZeroAddress(_wrappedNativeToken) {
        emit WrappedNativeTokenUpdated(wrappedNativeToken, _wrappedNativeToken);

        wrappedNativeToken = _wrappedNativeToken;
    }
}
