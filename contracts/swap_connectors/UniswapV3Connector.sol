// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.4;

import "./interfaces/IExchangeConnector.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract UniswapV3Connector is IExchangeConnector, Ownable, ReentrancyGuard {

    modifier nonZeroAddress(address _address) {
        require(_address != address(0), "UniswapV3Connector: zero address");
        _;
    }

    string public override name;
    address public override exchangeRouter;
    address public override liquidityPoolFactory;
    address public override wrappedNativeToken;
    address public middleToken;
    address public quoterAddress;
    mapping(address => string) public tokenName;
    mapping(address => mapping(address => uint24)) public feeTier;

    /// @notice                          This contract is used for interacting with UniswapV2 contract
    /// @param _name                     Name of the underlying DEX
    /// @param _exchangeRouter           Address of the DEX router contract
    constructor(string memory _name, address _exchangeRouter, address _quoterAddress, address _middleToken) {
        name = _name;
        exchangeRouter = _exchangeRouter;
        // liquidityPoolFactory = IPeripheryImmutableState(exchangeRouter).factory();
        // wrappedNativeToken = IPeripheryImmutableState(exchangeRouter).WETH9();
        quoterAddress = _quoterAddress;
        middleToken = wrappedNativeToken;
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice                             Setter for exchange router
    /// @dev                                Gets address of liquidity pool factory from new exchange router
    /// @param _exchangeRouter              Address of the new exchange router contract
    function setExchangeRouter(address _exchangeRouter) external nonZeroAddress(_exchangeRouter) override onlyOwner {
        exchangeRouter = _exchangeRouter;
        liquidityPoolFactory = IPeripheryImmutableState(exchangeRouter).factory();
        wrappedNativeToken = IPeripheryImmutableState(exchangeRouter).WETH9();
    }

    /// @notice            Setter for liquidity pool factory
    /// @dev               Gets address from exchange router
    function setLiquidityPoolFactory() external override onlyOwner {
        liquidityPoolFactory = IPeripheryImmutableState(exchangeRouter).factory();
    }

    /// @notice            Setter for quoter
    function setQuoter(address _quoterAddress) external onlyOwner {
        quoterAddress = _quoterAddress;
    }

    /// @notice            Setter for wrapped native token
    /// @dev               Gets address from exchange router
    function setWrappedNativeToken() external override onlyOwner {
        wrappedNativeToken = IPeripheryImmutableState(exchangeRouter).WETH9();
    }

    /// @notice            Setter for middle token
    function setMiddleToken(address _middleToken) external onlyOwner {
        middleToken = _middleToken;
    }

    function setTokenName(address _token, string memory _name) external onlyOwner {
        tokenName[_token] = _name;
    }

    function setFeeTier(address _firstToken, address _secondToken, uint24 _feeTier) external onlyOwner {
        feeTier[_firstToken][_secondToken] = _feeTier;
    }

    function convertedPath (address[] memory _path, bool forSwap) public onlyOwner returns (bytes memory packedData) {
        if (forSwap) 
            packedData = abi.encodePacked(tokenName[_path[0]]);
        else 
            packedData = abi.encodePacked(_path[0]);

        for (uint i = 1; i < _path.length; i++) {
            address firstToken = _path[i - 1];
            address secondToken = _path[i];
            uint _feeTier = feeTier[firstToken][secondToken];
            if (forSwap) 
                packedData = abi.encodePacked(packedData, _feeTier, tokenName[secondToken]);
            else 
                packedData = abi.encodePacked(packedData, _feeTier, secondToken);
        }
    }

    function _buildInputSwap ( uint _amountIn, uint _amountOutMin, address[] memory _path, address _recipient, uint _deadline) private returns (ISwapRouter.ExactInputParams memory) {
        return ISwapRouter.ExactInputParams({
            path: convertedPath(_path, true),
            recipient: _recipient,
            deadline: _deadline,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMin
        });
    }

    function _buildOutputSwap (uint _amountInMaximum, uint _amountOut, address[] memory _path, address _recipient, uint _deadline) private returns (ISwapRouter.ExactOutputParams memory) {
        return ISwapRouter.ExactOutputParams({
            path: convertedPath(_path, true),
            recipient: _recipient,
            deadline: _deadline,
            amountOut: _amountOut,
            amountInMaximum: _amountInMaximum
        });
    }

    function getExactInput (address[] memory _path, uint256 amountIn) public returns (bool, uint256) {
        if (!isPathValid(_path)) {
            return (false, 0);
        }
        (uint amountOut, , ,) = IQuoterV2(quoterAddress).quoteExactInput(convertedPath(_path, false), amountIn);
        return (true, amountOut);
    }

    function getExactOutput (address[] memory _path, uint256 amountOut) public returns (bool, uint256) {
        if (!isPathValid(_path)) {
            return (false, 0);
        }
        (uint amountIn, , ,) = IQuoterV2(quoterAddress).quoteExactOutput(convertedPath(_path, false), amountOut);
         return (true, amountIn);
    }


    /// @notice                     Returns required input amount to get desired output amount
    /// @dev                        Returns (false, 0) if liquidity pool of inputToken-outputToken doesn't exist
    ///                             Returns (false, 0) if desired output amount is greater than or equal to output reserve
    /// @param _outputAmount        Desired output amount
    /// @param _inputToken          Address of the input token
    /// @param _outputToken         Address of the output token
    function getInputAmount(
        uint _outputAmount,
        address _inputToken,
        address _outputToken
    ) external view nonZeroAddress(_inputToken) nonZeroAddress(_outputToken) override returns (bool, uint) {
        // address[] memory path = new address[](2);
        // path[0] = _inputToken;
        // path[1] = _outputToken;
        // return getExactOutput(
        //     path,
        //     _outputAmount
        // );
        return (true, 0);
    }

    /// @notice                     Returns amount of output token that user receives 
    /// @dev                        Returns (false, 0) if liquidity pool of inputToken-outputToken doesn't exist
    /// @param _inputAmount         Amount of input token
    /// @param _inputToken          Address of the input token
    /// @param _outputToken         Address of the output token
    function getOutputAmount(
        uint _inputAmount,
        address _inputToken,
        address _outputToken
    ) external view nonZeroAddress(_inputToken) nonZeroAddress(_outputToken) override returns (bool, uint) {
        // address[] memory path = new address[](2);
        // path[0] = _inputToken;
        // path[1] = _outputToken;
        // return getExactInput(
        //     path,
        //     _inputAmount
        // );
        return (true, 0);
    }

    /// @notice                     Exchanges input token for output token through exchange router
    /// @dev                        Checks exchange conditions before exchanging
    ///                             We assume that the input token is not WETH (it is teleBTC)
    /// @param _inputAmount         Amount of input token
    /// @param _outputAmount        Amount of output token
    /// @param _path                List of tokens that are used for exchanging
    /// @param _to                  Receiver address
    /// @param _deadline            Deadline of exchanging tokens
    /// @param _isFixedToken        True if the input token amount is fixed
    /// @return _result             True if the exchange is successful
    /// @return _amounts            Amounts of tokens that are involved in exchanging
    function swap(
        uint256 _inputAmount,
        uint256 _outputAmount,
        address[] memory _path,
        address _to,
        uint256 _deadline,
        bool _isFixedToken
    ) external nonReentrant nonZeroAddress(_to) override returns (bool _result, uint[] memory) {
        uint neededInputAmount;
        (_result, neededInputAmount) = _checkExchangeConditions(
            _inputAmount,
            _outputAmount,
            _path,
            _deadline,
            _isFixedToken
        );
        
        uint _amount;
        if (_result) {
            // Gets tokens from user
            IERC20(_path[0]).transferFrom(_msgSender(), address(this), neededInputAmount);
            // Gives allowance to exchange router
            IERC20(_path[0]).approve(exchangeRouter, neededInputAmount);

            if (_isFixedToken == false) {
                _amount = ISwapRouter(exchangeRouter).exactInput(
                    _buildInputSwap(
                        _inputAmount, 
                        _outputAmount,
                        _path, 
                        _to, 
                        _deadline
                    )
                );
            }

            if (_isFixedToken == true) {
                _amount = ISwapRouter(exchangeRouter).exactOutput(
                    _buildOutputSwap(
                        _inputAmount, 
                        _outputAmount,
                        _path, 
                        _to, 
                        _deadline
                    )
                );
            }

            uint[] memory amounts = new uint[](1);
            amounts[0] = _amount;
            emit Swap(_path, amounts, _to);
        }
    }

    /// @notice                     Returns true if the exchange path is valid
    /// @param _path                List of tokens that are used for exchanging
    function isPathValid(address[] memory _path) public view override returns (bool _result) {
        address liquidityPool;

        // Checks that path length is greater than one
        if (_path.length < 2) {
            return false;
        }

        for (uint i = 0; i < _path.length - 1; i++) {
            liquidityPool =
                IUniswapV3Factory(liquidityPoolFactory).getPool(_path[i], _path[i + 1], feeTier[_path[i]][_path[i + 1]]);
            if (liquidityPool == address(0)) {
                return false;
            }
        }

        return true;
    }

    /// @notice                     Checks if exchanging can happen successfully
    /// @dev                        Avoids reverting the execution by exchange router
    /// @param _inputAmount         Amount of input token
    /// @param _outputAmount        Amount of output token
    /// @param _path                List of tokens that are used for exchanging
    /// @param _deadline            Deadline of exchanging tokens
    /// @param _isFixedToken        True if the input token amount is fixed
    /// @return                     True if exchange conditions are satisfied
    /// @return                     Needed amount of input token
    function _checkExchangeConditions(
        uint256 _inputAmount,
        uint256 _outputAmount,
        address[] memory _path,
        uint256 _deadline,
        bool _isFixedToken
    ) private returns (bool, uint) {

        // Checks deadline has not passed
        if (_deadline < block.timestamp) {
            return (false, 0);
        }

        // Finds maximum output amount
        (bool success, uint outputResult) = getExactInput(
            _path,
            _inputAmount
        );

        // Checks that exchanging is possible or not
        if (_outputAmount > outputResult) {
            return (false, 0);
        } else {
            if (_isFixedToken == true) {
                return (success, _inputAmount);
            } else {
                return getExactOutput(
                    _path,
                    _outputAmount
                );
            }
        }
    }

    //TODO reentrancy guard

}