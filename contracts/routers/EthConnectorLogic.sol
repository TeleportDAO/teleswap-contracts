// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    function initialize(
        address _targetChainTeleBTC,
        address _across,
        address _wrappedNativeToken,
        uint256 _targetChainId
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        _setTargetChainTeleBTC(_targetChainTeleBTC);
        _setAcross(_across);
        _setWrappedNativeToken(_wrappedNativeToken);
        targetChainId = _targetChainId;
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

    /// @notice Withdraws tokens in the emergency case
    /// @dev Only owner can call this
    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external override onlyOwner {
        if (_token == ETH_ADDR) _to.call{value: _amount}("");
        else IERC20(_token).transfer(_to, _amount);
    }

    /// @notice Requests exchanging token for BTC
    /// @dev To find teleBTCAmount, _relayerFeePercentage should be reduced from the inputTokenAmount
    /// @param _token Address of input token (on the current chain)
    /// @param _exchangeConnector Address of exchange connector to be used
    /// @param _amounts [inputTokenAmount, teleBTCAmount]
    /// @param _path of exchanging inputToken to teleBTC (these are Polygon token addresses, so _path[0] != _token)
    /// @param _userScript User script hash
    /// @param _scriptType User script type
    /// @param _lockerLockingScript	of locker that should execute the burn request
    /// @param _relayerFeePercentage Fee percentage for relayer
    /// @param _thirdParty Id of third party
    function swapAndUnwrap(
        address _token,
        address _exchangeConnector,
        uint256[] calldata _amounts,
        address[] calldata _path,
        bytes memory _userScript,
        ScriptTypes _scriptType,
        bytes calldata _lockerLockingScript,
        int64 _relayerFeePercentage,
        uint256 _thirdParty
    ) external payable override nonReentrant {
        _checkRequest(_amounts, _path);

        // Sends msg to Polygon

        bytes memory message = abi.encode(
            "swapAndUnwrap",
            uniqueCounter,
            _msgSender(),
            _exchangeConnector,
            _amounts[1], // Min output amount to receive
            _path,
            _userScript,
            _scriptType,
            _lockerLockingScript,
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

    /// @notice Sends tokens and message using Across bridge
    function _sendMsgUsingAcross(
        address _token,
        uint256 _amount,
        bytes memory _message,
        int64 _relayerFeePercentage
    ) internal {
        if (_token == ETH_ADDR) {
            require(msg.value == _amount, "EthManagerLogic: wrong value");
            _token = wrappedNativeToken;
        } else {
            require(msg.value == 0, "EthManagerLogic: wrong value");

            // Transfers tokens from user to contract
            IERC20(_token).transferFrom(_msgSender(), address(this), _amount);

            IERC20(_token).approve(across, _amount);
        }

        // // Calling across for transferring token and msg
        // Address.functionCallWithValue(
        //     across,
        //     abi.encodeWithSignature(
        //         "deposit(address,address,uint256,uint256,int64,uint32,bytes,uint256)",
        //         targetChainConnectorProxy,
        //         _token,
        //         _amount,
        //         targetChainId,
        //         _relayerFeePercentage,
        //         uint32(block.timestamp),
        //         _message,
        //         115792089237316195423570985008687907853269984665640564039457584007913129639935
        //     ),
        //     msg.value
        // );
    }

    /// @notice Checks validity of request
    /// @dev Token should be acceptable, input amount should be >= min,
    ///      last token of path should be teleBTC, and amounts array length should be 2
    function _checkRequest(
        uint256[] calldata _amounts,
        address[] calldata _path
    ) internal view {
        require(
            _path[_path.length - 1] == targetChainTeleBTC,
            "EthManagerLogic: invalid path"
        );

        require(_amounts.length == 2, "EthManagerLogic: wrong amounts");
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
