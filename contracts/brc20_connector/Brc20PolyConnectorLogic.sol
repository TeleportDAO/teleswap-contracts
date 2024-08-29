// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "@across-protocol/contracts-v2/contracts/interfaces/SpokePoolInterface.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@teleportdao/btc-evm-bridge/contracts/types/ScriptTypesEnum.sol";
import "../brc20_router/interfaces/IBrc20Router.sol";
import "../routers/interfaces/AcrossMessageHandler.sol";
import "./Brc20PolyConnectorStorage.sol";
import "./interfaces/IBrc20PolyConnector.sol";

contract Brc20PolyConnectorLogic is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IBrc20PolyConnector,
    AcrossMessageHandler,
    Brc20PolyConnectorStorage
{
    error ZeroAddress();

    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    function initialize(
        address _brc20RouterProxy,
        address _across
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        brc20RouterProxy = _brc20RouterProxy;
        across = _across;
    }

    /// @notice Setter for brc20RouterProxy
    function setBrc20RouterProxy(
        address _brc20RouterProxy
    ) external override onlyOwner nonZeroAddress(_brc20RouterProxy) {
        brc20RouterProxy = _brc20RouterProxy;
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
        // Check the msg origin
        require(msg.sender == across, "PolyConnectorLogic: not across");

        // Determine the function call
        (string memory purpose, uint256 uniqueCounter, uint256 chainId) = abi
            .decode(_message, (string, uint256, uint256));
        emit MsgReceived(purpose, uniqueCounter, chainId, _message);

        if (_isEqualString(purpose, "unwrapBrc20")) {
            _unwrapBrc20(_amount, _message, _tokenSent);
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

        require(
            _amount > 0 && failedReqs[user][_chainId][_token] >= _amount,
            "PolyConnectorLogic: low balance"
        );

        // Send token back to the user
        _sendTokenUsingAcross(
            user,
            _chainId,
            _token,
            _amount,
            _relayerFeePercentage
        );

        // Update witholded amount
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
        // TODO: change function

        // Find user address after verifying the signature
        address user = _verifySig(_message, _r, _s, _v);

        exchangeForBrc20Arguments memory arguments = _decodeReqUnwrap(_message);

        require(
            arguments.amount > 0 &&
                failedReqs[user][arguments.chainId][arguments.path[0]] >=
                arguments.amount,
            "PolyConnectorLogic: low balance"
        );

        failedReqs[user][arguments.chainId][arguments.path[0]] -= arguments
            .amount;

        IERC20(arguments.path[0]).approve(brc20RouterProxy, arguments.amount);

        IBrc20Router(brc20RouterProxy).unwrapBrc20(
            arguments.thirdPartyId,
            arguments.tokenId,
            arguments.amount,
            arguments.userScript.userScript,
            arguments.userScript.scriptType,
            arguments.appId,
            arguments.inputAmount,
            arguments.path
        );

        emit NewSwapAndUnwrapBrc20(
            arguments.chainId,
            arguments.user,
            arguments.thirdPartyId,
            arguments.tokenId,
            arguments.appId,
            arguments.amount,
            arguments.inputAmount,
            arguments.path,
            arguments.userScript.userScript,
            arguments.userScript.scriptType
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
    function _unwrapBrc20(
        uint256 _amount,
        bytes memory _message,
        address _tokenSent
    ) internal {
        exchangeForBrc20Arguments memory arguments = _decodeReqUnwrap(_message);

        IERC20(_tokenSent).approve(brc20RouterProxy, _amount);

        try
            IBrc20Router(brc20RouterProxy).unwrapBrc20(
                arguments.thirdPartyId,
                arguments.tokenId,
                arguments.amount,
                arguments.userScript.userScript,
                arguments.userScript.scriptType,
                arguments.appId,
                arguments.inputAmount,
                arguments.path
            )
        {
            emit NewSwapAndUnwrapBrc20(
                arguments.chainId,
                arguments.user,
                arguments.thirdPartyId,
                arguments.tokenId,
                arguments.appId,
                arguments.amount,
                arguments.inputAmount,
                arguments.path,
                arguments.userScript.userScript,
                arguments.userScript.scriptType
            );
        } catch {
            // Remove spending allowance
            IERC20(arguments.path[0]).approve(brc20RouterProxy, 0);

            // Save token amount so user can withdraw it in future
            failedReqs[arguments.user][arguments.chainId][
                _tokenSent
            ] += _amount;
            emit FailedSwapAndUnwrapBrc20(
                arguments.chainId,
                arguments.user,
                arguments.thirdPartyId,
                arguments.tokenId,
                arguments.appId,
                arguments.amount,
                arguments.inputAmount,
                arguments.path,
                arguments.userScript.userScript,
                arguments.userScript.scriptType
            );
        }
    }

    /// @notice Helper for exchanging token for BTC
    // function _swapAndWrap(
    //     uint256 _amount,
    //     bytes memory _message,
    //     address _tokenSent
    // ) internal {
    //     exchangeForBtcArguments memory arguments = _decodeReqWrap( //TODO implement
    //         _message
    //     );

    //     IERC20(_tokenSent).approve(brc20RouterProxy, _amount);

    //     try
    //         IBrc20Router(brc20RouterProxy).wrapBrc20(
    //             arguments._version,
    //             arguments._vin,
    //             arguments._vout,
    //             arguments._locktime,
    //             arguments._blockNumber,
    //             arguments._intermediateNodes,
    //             arguments._index,
    //             arguments._path
    //         )
    //     {
    //         // emit NewSwapAndWrap(
    //         //     arguments.chainId,
    //         //     arguments.exchangeConnector,
    //         //     _tokenSent,
    //         //     _amount,
    //         //     arguments.user,
    //         //     arguments.scripts.userScript,
    //         //     arguments.scripts.scriptType,
    //         //     ILockersManager(lockersProxy).lockerTargetAddress(
    //         //         arguments.scripts.lockerLockingScript
    //         //     ),
    //         //     BurnRouterStorage(brc20RouterProxy).burnRequestCounter(
    //         //         ILockersManager(lockersProxy).lockerTargetAddress(
    //         //             arguments.scripts.lockerLockingScript
    //         //         )
    //         //     ) - 1,
    //         //     arguments.path
    //         // ); TODO
    //     } catch {
    //         // Remove spending allowance
    //         IERC20(arguments.path[0]).approve(brc20RouterProxy, 0);

    //         // Save token amount so user can withdraw it in future
    //         failedReqs[arguments.user][arguments.chainId][
    //             _tokenSent
    //         ] += _amount;
    //         // emit FailedSwapAndWrap(
    //         //     arguments.chainId,
    //         //     arguments.exchangeConnector,
    //         //     _tokenSent,
    //         //     _amount,
    //         //     arguments.user,
    //         //     arguments.scripts.userScript,
    //         //     arguments.scripts.scriptType,
    //         //     arguments.path
    //         // ); TODO
    //     }
    // }

    function _decodeReqUnwrap(
        bytes memory _message
    ) private pure returns (exchangeForBrc20Arguments memory arguments) {
        (
            ,
            ,
            // purpose,
            // uniqueCounter
            arguments.chainId,
            arguments.user,
            arguments.thirdPartyId,
            arguments.tokenId,
            arguments.appId,
            arguments.amount,
            arguments.inputAmount
            // arguments.path,
            // arguments.userScript
        ) = abi.decode(
            _message,
            (
                string,
                uint256,
                uint256,
                address,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256
                // address[],
                // UserScriptAndType
            )
        );

        // to handle stack too deep

        (, , , , , , , , , arguments.path, arguments.userScript) = abi.decode(
            _message,
            (
                string,
                uint256,
                uint256,
                address,
                uint256,
                uint256,
                uint256,
                uint256,
                uint256,
                address[],
                UserScriptAndType
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
        require(signer != address(0), "PolyConnectorLogic: Invalid sig");

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
