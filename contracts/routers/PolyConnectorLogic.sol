// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";
import "./interfaces/IBurnRouter.sol";
import "./BurnRouterStorage.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "./PolyConnectorStorage.sol";
import "./interfaces/IPolyConnectorLogic.sol";
import "./interfaces/AcrossMessageHandler.sol";

contract PolyConnectorLogic is IPolyConnectorLogic, PolyConnectorStorage, 
    OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, AcrossMessageHandler {

    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0))
            revert ZeroAddress();
        _;
    }

    function initialize(
        address _lockersProxy,
        address _burnRouterProxy,
        address _across,
        address _acrossV3,
        uint256 _sourceChainId
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        lockersProxy = _lockersProxy;
        burnRouterProxy = _burnRouterProxy;
        across = _across;
        acrossV3 = _acrossV3;
        sourceChainId = _sourceChainId;
    }

    /// @notice Setter for EthConnectorProxy
    function setEthConnectorProxy(address _ethConnectorProxy) external override onlyOwner nonZeroAddress(_ethConnectorProxy) {
        ethConnectorProxy = _ethConnectorProxy;
    }

    /// @notice Setter for LockersProxy
    function setLockersProxy(address _lockersProxy) external override onlyOwner nonZeroAddress(_lockersProxy){
        lockersProxy = _lockersProxy;
    }

    /// @notice Setter for BurnRouterProxy
    function setBurnRouterProxy(address _burnRouterProxy) external override onlyOwner nonZeroAddress(_burnRouterProxy){
        burnRouterProxy = _burnRouterProxy;
    }

    /// @notice Setter for Across
    function setAcross(address _across) external override onlyOwner nonZeroAddress(_across){
        across = _across;
    }

    // TODO check across v3 functions
    /// @notice Setter for AcrossV3
    function setAcrossV3(address _acrossV3) external override onlyOwner nonZeroAddress(_acrossV3){
        acrossV3 = _acrossV3;
    }

    /// @notice Processes requests coming from Ethereum (using Across)
    /// @dev Only Across can call this. Will be reverted if tokens have not been received fully yet.
    /// @param _tokenSent Address of exchanging token
    /// @param _amount Amount received by the contract (after reducing fees)
    /// @param _fillCompleted True if all tokens have been received
    /// @param _relayer Addres of relayer who submitted the request
    /// @param _message that user sent (from Ethereum)
    function handleAcrossMessage(
        address _tokenSent,
        uint256 _amount,
        bool _fillCompleted,
        address _relayer,
        bytes memory _message
    ) external nonReentrant override {
        // Checks the msg origin and fill completion (full amount has been received)
        require(msg.sender == across, "PolygonConnectorLogic: not across");

        // // FIXME: handle cases the fillCompleted is not true
        require(_fillCompleted, "PolygonConnectorLogic: partial fill");

        // Determines the function call
        (string memory purpose, uint uniqueCounter) = abi.decode(_message, (string, uint));
        emit MsgReceived(uniqueCounter, purpose, _message);

        if (_isEqualString(purpose, "exchangeForBtcAcross")) {
            _exchangeForBtcAcross(_amount, _message, _tokenSent);
        }
    }

    /// @notice Process requests coming from Ethereum (using Across V3)
    function handleV3AcrossMessage(
        address _tokenSent,
        uint256 _amount,
        address _relayer, 
        bytes memory _message
    ) external nonReentrant override {
        // Checks the msg origin and fill completion (full amount has been received)
        require(msg.sender == acrossV3, "PolygonConnectorLogic: not acrossV3");

        // Determines the function call
        (string memory purpose, uint uniqueCounter) = abi.decode(_message, (string, uint));
        emit MsgReceived(uniqueCounter, purpose, _message);

        if (_isEqualString(purpose, "exchangeForBtcAcross")) {
            _exchangeForBtcAcross(_amount, _message, _tokenSent);
        }
    }

    /// @notice Withdraws user's bid
    /// @dev User signs a message requesting for withdrawing a bid
    /// @param _message The signed message
    /// @param _v Signature v
    /// @param _r Signature r
    /// @param _s Signature s

    function withdrawFundsToEth(
        bytes memory _message,
        uint8 _v, 
        bytes32 _r, 
        bytes32 _s
    ) external nonReentrant override {

        (
            address _token, 
            uint256 _amount, 
            int64 _relayerFeePercentage
        ) = abi.decode(
            _message,
            (
                address,
                uint256, 
                int64
            )
        );

        // Verifies the signature and finds the buyer
        address user = _verifySig(
            _message,
            _r,
            _s,
            _v
        );

        // Checks that bid exists
        require(
            _amount > 0 && failedReqs[user][_token] >= _amount,
            "PolygonConnectorLogic: low balance"
        );

        // TODO test onchain 
        // Sends token back to the buyer
        _sendTokenUsingAcross(
            user,
            _token,
            _amount,
            _relayerFeePercentage
        );
        
        // Delets the bid
        failedReqs[user][_token] -= _amount;
    }

    /// @notice Retry failed exchange and burn requests
    /// @dev User signs a message for retrying its request
    /// @param _message The signed message
    /// @param _v Signature v
    /// @param _r Signature r
    /// @param _s Signature s

    function retrySwapAndUnwrap(
        bytes memory _message,
        uint8 _v, 
        bytes32 _r, 
        bytes32 _s
    ) external nonReentrant override {
        (
            address _token, 
            uint256 _amount, 
            address exchangeConnector,
            uint256 minOutputAmount,
            bytes memory userScript,
            ScriptTypes scriptType,
            bytes memory lockerLockingScript,
            address[] memory path
        ) = abi.decode(
            _message,
            (
                address,
                uint256, 
                address,
                uint256,
                bytes,
                ScriptTypes,
                bytes,
                address[]
            )
        );

        // Verifies the signature and finds the buyer
        address user = _verifySig(
            _message,
            _r,
            _s,
            _v
        );

        // Checks that bid exists
        require(
            _amount > 0 && failedReqs[user][_token] >= _amount,
            "PolygonConnectorLogic: low balance"
        );

        failedReqs[user][_token] -= _amount;

        uint[] memory amounts = new uint[](2);
        amounts[0] = _amount;
        amounts[1] = minOutputAmount;

        IERC20(path[0]).approve(burnRouterProxy, _amount);
        IBurnRouter(burnRouterProxy).swapAndUnwrap(
            exchangeConnector, 
            amounts, 
            true, // Input token amount is fixed
            path, 
            block.timestamp, 
            userScript, 
            scriptType, 
            lockerLockingScript,
            0
        );

        address lockerTargetAddress = ILockersManager(lockersProxy).getLockerTargetAddress(lockerLockingScript);
        
        emit NewBurn(
            exchangeConnector,
            _token,
            _amount,
            user,
            userScript,
            scriptType,
            lockerTargetAddress,
            BurnRouterStorage(burnRouterProxy).burnRequestCounter(
                lockerTargetAddress
            ) - 1,
            path
        );
    }

    
    /// @notice Helper for exchanging token for BTC
    function _exchangeForBtcAcross(
        uint256 _amount,
        bytes memory _message,
        address _tokenSent
    ) internal {
        IPolyConnectorLogic.exchangeForBtcArguments memory arguments;
        (
            ,,
            arguments.user,
            arguments.exchangeConnector,
            arguments.minOutputAmount,
            arguments.path,
            arguments.userScript,
            arguments.scriptType,
            arguments.lockerLockingScript,
            arguments.thirdParty
        ) = abi.decode(
            _message, 
            (
                string,
                uint,
                address,
                address,
                uint,
                address[],
                bytes,
                ScriptTypes,
                bytes,
                uint
            )
        );

        uint[] memory amounts = new uint[](2);
        amounts[0] = _amount;
        amounts[1] = arguments.minOutputAmount;

        IERC20(arguments.path[0]).approve(burnRouterProxy, _amount);
        
        try IBurnRouter(burnRouterProxy).swapAndUnwrap(
            arguments.exchangeConnector, 
            amounts, 
            true, // Input token amount is fixed
            arguments.path, 
            block.timestamp, 
            arguments.userScript, 
            arguments.scriptType, 
            arguments.lockerLockingScript,
            arguments.thirdParty
        ) {
            emit NewBurn(
                arguments.exchangeConnector,
                _tokenSent,
                _amount,
                arguments.user,
                arguments.userScript,
                arguments.scriptType,
                ILockersManager(lockersProxy).getLockerTargetAddress(arguments.lockerLockingScript),
                BurnRouterStorage(burnRouterProxy).burnRequestCounter(
                    ILockersManager(lockersProxy).getLockerTargetAddress(arguments.lockerLockingScript)
                ) - 1,
                arguments.path
            );
        } catch {
            // Removes spending allowance
            IERC20(arguments.path[0]).approve(burnRouterProxy, 0);

            // Saves token amount so user can withdraw it in future
            failedReqs[arguments.user][_tokenSent] += _amount;
            emit FailedBurn(
                arguments.exchangeConnector,
                _tokenSent,
                _amount,
                arguments.user,
                arguments.userScript,
                arguments.scriptType,
                arguments.path
            );
        }
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

    /// @notice Sends tokens to Ethereum using Across
    /// @dev This will be used for withdrawing funds
    function _sendTokenUsingAcross(
        address _user,
        address _token,
        uint _amount,
        int64 _relayerFeePercentage
    ) internal {
        bytes memory nullData;
        IERC20(_token).approve(
            across, 
            _amount
        );

        SpokePoolInterface(across).depositFor(
            _user,
            _user,
            _token,
            _amount,
            sourceChainId,
            _relayerFeePercentage,
            uint32(block.timestamp),
            nullData,
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
    }

    // TODO: move to a library
    function _verifySig(
        bytes memory message,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure returns (address) {
        // Compute the message hash
        bytes32 messageHash = keccak256(message);

        // Prefix the message hash as per the Ethereum signing standard
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Verify the message using ecrecover
        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        require(signer != address(0), "PolygonConnectorLogic: Invalid sig");

        return signer;
    }

    /// @notice Checks if two strings are equal
    function _isEqualString(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    receive() external payable {}

}