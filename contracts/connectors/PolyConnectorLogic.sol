// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";
import "../routers/interfaces/IBurnRouter.sol";
import "../routers/interfaces/AcrossMessageHandler.sol";
import "../routers/BurnRouterStorage.sol";
import "../lockersManager/interfaces/ILockersManager.sol";
import "./PolyConnectorStorage.sol";
import "./interfaces/IPolyConnector.sol";

contract PolyConnectorLogic is
    IPolyConnector,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AcrossMessageHandler,
    PolyConnectorStorage
{
    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    function initialize(
        address _lockersProxy,
        address _burnRouterProxy,
        address _across
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        lockersProxy = _lockersProxy;
        burnRouterProxy = _burnRouterProxy;
        across = _across;
    }

    /// @notice Setter for LockersProxy
    function setLockersProxy(
        address _lockersProxy
    ) external override onlyOwner nonZeroAddress(_lockersProxy) {
        lockersProxy = _lockersProxy;
    }

    /// @notice Setter for BurnRouterProxy
    function setBurnRouterProxy(
        address _burnRouterProxy
    ) external override onlyOwner nonZeroAddress(_burnRouterProxy) {
        burnRouterProxy = _burnRouterProxy;
    }

    /// @notice Setter for AcrossV3
    function setAcross(
        address _across
    ) external override onlyOwner nonZeroAddress(_across) {
        across = _across;
    }

    /// @notice Process requests coming from Ethereum (using Across V3)
    function handleV3AcrossMessage(
        address _tokenSent,
        uint256 _amount,
        address,
        bytes memory _message
    ) external override nonReentrant {
        // Checks the msg origin and fill completion (full amount has been received)
        require(msg.sender == across, "PolygonConnectorLogic: not across");

        // Determines the function call
        (string memory purpose, uint256 uniqueCounter, uint256 chainId) = abi
            .decode(_message, (string, uint256, uint256));
        emit MsgReceived(purpose, uniqueCounter, chainId, _message);

        if (_isEqualString(purpose, "swapAndUnwrap")) {
            _swapAndUnwrap(_amount, _message, _tokenSent);
        }
    }

    /// @notice Send back tokens to the source chain
    /// @param _message The signed message
    /// @param _v Signature v
    /// @param _r Signature r
    /// @param _s Signature s
    function withdrawFundsToSourceChain(
        bytes memory _message,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override nonReentrant {
        // Find user address after verifying the signature
        address user = _verifySig(_message, _r, _s, _v);

        (
            uint256 _chainId,
            address _token,
            uint256 _amount,
            int64 _relayerFeePercentage
        ) = abi.decode(_message, (uint256, address, uint256, int64));

        // Checks that bid exists
        require(
            _amount > 0 && failedReqs[user][_chainId][_token] >= _amount,
            "PolygonConnectorLogic: low balance"
        );

        // Sends token back to the buyer
        _sendTokenUsingAcross(
            user,
            _chainId,
            _token,
            _amount,
            _relayerFeePercentage
        );

        // Delets the bid
        failedReqs[user][_chainId][_token] -= _amount;
    }

    /// @notice Retry to swap and unwrap tokens
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
    ) external override nonReentrant {
        // Find user address after verifying the signature
        address user = _verifySig(_message, _r, _s, _v);

        (
            uint256 _chainId,
            address _token,
            uint256 _amount,
            address exchangeConnector,
            uint256 outputAmount,
            bytes memory userScript,
            ScriptTypes scriptType,
            bytes memory lockerLockingScript,
            address[] memory path
        ) = abi.decode(
                _message,
                (
                    uint256,
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

        require(
            _amount > 0 && failedReqs[user][_chainId][_token] >= _amount,
            "PolygonConnectorLogic: low balance"
        );

        failedReqs[user][_chainId][_token] -= _amount;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount;
        amounts[1] = outputAmount;

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

        address lockerTargetAddress = ILockersManager(lockersProxy)
            .getLockerTargetAddress(lockerLockingScript);

        emit NewSwapAndUnwrap(
            _chainId,
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

    receive() external payable {}

    /// @notice Helper for exchanging token for BTC
    function _swapAndUnwrap(
        uint256 _amount,
        bytes memory _message,
        address _tokenSent
    ) internal {
        exchangeForBtcArguments memory arguments = _decodeReq(
            _message
        );

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount;
        amounts[1] = arguments.outputAmount;

        IERC20(arguments.path[0]).approve(burnRouterProxy, _amount);

        try
            IBurnRouter(burnRouterProxy).swapAndUnwrap(
                arguments.exchangeConnector,
                amounts,
                arguments.isInputFixed,
                arguments.path,
                block.timestamp,
                arguments.scripts.userScript,
                arguments.scripts.scriptType,
                arguments.scripts.lockerLockingScript,
                arguments.thirdParty
            )
        {
            emit NewSwapAndUnwrap(
                arguments.chainId,
                arguments.exchangeConnector,
                _tokenSent,
                _amount,
                arguments.user,
                arguments.scripts.userScript,
                arguments.scripts.scriptType,
                ILockersManager(lockersProxy).getLockerTargetAddress(
                    arguments.scripts.lockerLockingScript
                ),
                BurnRouterStorage(burnRouterProxy).burnRequestCounter(
                    ILockersManager(lockersProxy).getLockerTargetAddress(
                        arguments.scripts.lockerLockingScript
                    )
                ) - 1,
                arguments.path
            );
        } catch {
            // Remove spending allowance
            IERC20(arguments.path[0]).approve(burnRouterProxy, 0);

            // Save token amount so user can withdraw it in future
            failedReqs[arguments.user][arguments.chainId][
                _tokenSent
            ] += _amount;
            emit FailedSwapAndUnwrap(
                arguments.chainId,
                arguments.exchangeConnector,
                _tokenSent,
                _amount,
                arguments.user,
                arguments.scripts.userScript,
                arguments.scripts.scriptType,
                arguments.path
            );
        }
    }

    function _decodeReq(
        bytes memory _message
    )
        private
        pure
        returns (exchangeForBtcArguments memory arguments)
    {
        (
            ,
            ,
            // purpose,
            // uniqueCounter
            arguments.chainId,
            arguments.user,
            arguments.exchangeConnector,
            arguments.outputAmount,
            arguments.isInputFixed,
            arguments.path,
            arguments.scripts

        ) = abi.decode(
            _message,
            (
                string,
                uint256,
                uint256,
                address,
                address,
                uint256,
                bool,
                address[],
                UserAndLockerScript
            )
        );

        (, , , , , , , , , arguments.thirdParty) = abi.decode(
            _message,
            (
                string,
                uint256,
                uint256,
                address,
                address,
                uint256,
                bool,
                address[],
                UserAndLockerScript,
                uint256
            )
        );
    }

    /// @notice Sends tokens to Ethereum using Across
    /// @dev This will be used for withdrawing funds
    function _sendTokenUsingAcross(
        address _user,
        uint256 _chainId,
        address _token,
        uint256 _amount,
        int64 _relayerFeePercentage
    ) internal {
        bytes memory nullData;
        IERC20(_token).approve(across, _amount);

        SpokePoolInterface(across).depositFor(
            _user,
            _user,
            _token,
            _amount,
            _chainId,
            _relayerFeePercentage,
            uint32(block.timestamp),
            nullData,
            115792089237316195423570985008687907853269984665640564039457584007913129639935
        );
    }

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
    function _isEqualString(
        string memory _a,
        string memory _b
    ) internal pure returns (bool) {
        return
            keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }
}
