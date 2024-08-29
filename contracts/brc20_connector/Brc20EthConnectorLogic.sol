// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./Brc20EthConnectorStorage.sol";
import "./interfaces/IBrc20EthConnector.sol";

contract Brc20EthConnectorLogic is
    IBrc20EthConnector,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    Brc20EthConnectorStorage
{
    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    function initialize(
        address _across,
        address _wrappedNativeToken,
        uint256 _targetChainId,
        uint256 _currChainId
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

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
        else IERC20(_token).transfer(_to, _amount);
    }

    /// @notice Request exchanging token for BTC
    /// @dev To find teleBTCAmount, _relayerFeePercentage should be reduced from the inputTokenAmount
    /// @param _token Address of input token (on the current chain)
    function swapAndUnwrap(
        address _token,
        uint256 _thirdPartyId,
        uint256 _tokenId,
        uint256 _appId,
        uint256 _amount,
        uint256 _inputAmount,
        address[] calldata _path,
        UserScriptAndType calldata _userScript,
        int64 _relayerFeePercentage
    ) external payable override nonReentrant {
        // TODO: change the function 
        // _checkRequest(_amounts, _path);

        // Send msg to Polygon
        bytes memory message = abi.encode(
            "unwrapBrc20",
            uniqueCounter,
            currChainId,
            _msgSender(),
            _thirdPartyId,
            _tokenId,
            _appId,
            _amount,
            _inputAmount,
            _path,
            _userScript
        ); 

        emit MsgSent(uniqueCounter, message, _token, _amount);

        uniqueCounter++;

        _sendMsgUsingAcross(
            _token,
            _amount,
            message,
            _relayerFeePercentage
        );
    }

    /// @notice Send tokens and message using Across bridge
    function _sendMsgUsingAcross(
        address _token,
        uint256 _amount,
        bytes memory _message,
        int64 _relayerFeePercentage
    ) internal {
        if (_token == ETH_ADDR) {
            require(msg.value == _amount, "Brc20EthConnectorLogic: wrong value");
            _token = wrappedNativeToken;
        } else {
            require(msg.value == 0, "Brc20EthConnectorLogic: wrong value");

            // Transfer tokens from user to contract
            IERC20(_token).transferFrom(_msgSender(), address(this), _amount);
            IERC20(_token).approve(across, _amount);
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

    /// @notice Check validity of request
    /// @dev Token should be acceptable, input amount should be >= min,
    ///      last token of path should be teleBTC, and amounts array length should be 2
    // function _checkRequest(
    //     uint256[] calldata _amounts,
    //     address[] calldata _path
    // ) internal view {
    //     require(
    //         _path[_path.length - 1] == targetChainTeleBTC,
    //         "Brc20EthConnectorLogic: invalid path"
    //     );

    //     require(_amounts.length == 2, "Brc20EthConnectorLogic: wrong amounts");
    // }

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

    function _setWrappedNativeToken(
        address _wrappedNativeToken
    ) private nonZeroAddress(_wrappedNativeToken) {
        emit WrappedNativeTokenUpdated(wrappedNativeToken, _wrappedNativeToken);

        wrappedNativeToken = _wrappedNativeToken;
    }
}
