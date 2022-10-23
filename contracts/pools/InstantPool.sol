// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "./interfaces/IInstantPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract InstantPool is IInstantPool, ERC20, Ownable, ReentrancyGuard {

    // Constants
    uint constant MAX_INSTANT_PERCENTAGE_FEE = 10000;

    address public override teleBTC;
    uint public override instantPercentageFee; // a number between 0-10000 to show %0.01
    uint public override totalAddedTeleBTC;
    address public override instantRouter;

    constructor(
        address _teleBTC,
        address _instantRouter,
        uint _instantPercentageFee,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _setTeleBTC(_teleBTC);
        _setInstantRouter(_instantRouter);
        _setInstantPercentageFee(_instantPercentageFee);
    }

    function renounceOwnership() public virtual override onlyOwner {}

    /// @notice                               Gives available teleBTC amount
    /// @return                               Available amount of teleBTC that can be borrowed
    function availableTeleBTC() override public view returns (uint) {
        return IERC20(teleBTC).balanceOf(address(this));
    }

    /// @notice                               Gives the unpaid loans amount
    /// @return                               Amount of teleBTC that has been borrowed but has not been paid back
    function totalUnpaidLoan() override external view returns (uint) {
        uint _availableTeleBTC = availableTeleBTC();
        return totalAddedTeleBTC >= _availableTeleBTC ? totalAddedTeleBTC - _availableTeleBTC : 0;
    }

    /// @notice                 Changes instant router contract address
    /// @dev                    Only owner can call this
    /// @param _instantRouter   The new instant router contract address
    function setInstantRouter(address _instantRouter) external override onlyOwner {
        _setInstantRouter(_instantRouter);
    }

    /// @notice                        Changes instant loan fee
    /// @dev                           Only current owner can call this
    /// @param _instantPercentageFee   The new percentage fee
    function setInstantPercentageFee(uint _instantPercentageFee) external override onlyOwner {
        _setInstantPercentageFee(_instantPercentageFee);
    }

    /// @notice                 Changes teleBTC contract address
    /// @dev                    Only owner can call this
    /// @param _teleBTC         The new teleBTC contract address
    function setTeleBTC(address _teleBTC) external override onlyOwner {
        _setTeleBTC(_teleBTC);
    }

    /// @notice                 Internal setter for instant router contract address
    /// @param _instantRouter   The new instant router contract address
    function _setInstantRouter(address _instantRouter) private {
        emit NewInstantRouter(instantRouter, _instantRouter);
        instantRouter = _instantRouter;
    }

    /// @notice                         Internal setter for instant loan fee
    /// @param _instantPercentageFee    The new percentage fee
    function _setInstantPercentageFee(uint _instantPercentageFee) private {
        emit NewInstantPercentageFee(instantPercentageFee, _instantPercentageFee);
        instantPercentageFee = _instantPercentageFee;
    }

    /// @notice                 Internal setter for teleBTC contract address
    /// @param _teleBTC         The new teleBTC contract address
    function _setTeleBTC(address _teleBTC) private {
        emit NewTeleBTC(teleBTC, _teleBTC);
        teleBTC = _teleBTC;
    }

    function getFee(uint _loanAmount) external view override returns (uint) {
        return _loanAmount*instantPercentageFee/MAX_INSTANT_PERCENTAGE_FEE;
    }

    /// @notice               Adds liquidity to instant pool
    /// @dev
    /// @param _user          Address of user who receives instant pool token
    /// @param _amount        Amount of liquidity that user wants to add
    /// @return               Amount of instant pool token that user receives
    function addLiquidity(address _user, uint _amount) external nonReentrant override returns (uint) {
        require(_amount > 0, "InstantPool: input amount is zero");
        uint instantPoolTokenAmount;
        // Transfers teleBTC from user
        IERC20(teleBTC).transferFrom(_msgSender(), address(this), _amount);
        if (totalAddedTeleBTC == 0 || totalSupply() == 0) {
            instantPoolTokenAmount = _amount;
        } else {
            instantPoolTokenAmount = _amount*totalSupply()/totalAddedTeleBTC;
        }
        totalAddedTeleBTC = totalAddedTeleBTC + _amount;
        // Mints instant pool token for user
        _mint(_user, instantPoolTokenAmount);
        emit AddLiquidity(_user, _amount, instantPoolTokenAmount);
        return instantPoolTokenAmount;
    }

    /// @notice               Adds liquidity to instant pool without minting instant pool tokens
    /// @dev                  Updates totalAddedTeleBTC (transferring teleBTC directly does not update it)
    /// @param _amount        Amount of liquidity that user wants to add
    /// @return               True if liquidity is added successfully
    function addLiquidityWithoutMint(uint _amount) external nonReentrant override returns (bool) {
        require(_amount > 0, "InstantPool: input amount is zero");
        // Transfers teleBTC from user
        IERC20(teleBTC).transferFrom(_msgSender(), address(this), _amount);
        totalAddedTeleBTC = totalAddedTeleBTC + _amount;
        emit AddLiquidity(_msgSender(), _amount, 0);
        return true;
    }

    /// @notice                               Removes liquidity from instant pool
    /// @dev
    /// @param _user                          Address of user who receives teleBTC
    /// @param _instantPoolTokenAmount        Amount of instant pool token that is burnt
    /// @return                               Amount of teleBTC that user receives
    function removeLiquidity(address _user, uint _instantPoolTokenAmount) external nonReentrant override returns (uint) {
        require(_instantPoolTokenAmount > 0, "InstantPool: input amount is zero");
        require(balanceOf(_msgSender()) >= _instantPoolTokenAmount, "InstantPool: balance is not sufficient");
        uint teleBTCAmount = _instantPoolTokenAmount*totalAddedTeleBTC/totalSupply();
        totalAddedTeleBTC = totalAddedTeleBTC - teleBTCAmount;
        IERC20(teleBTC).transfer(_user, teleBTCAmount);
        _burn(_msgSender(), _instantPoolTokenAmount);
        emit RemoveLiquidity(_msgSender(), teleBTCAmount, _instantPoolTokenAmount);
        return teleBTCAmount;
    }

    /// @notice                               Gives loan to user
    /// @dev                                  Only instant router contract can call this
    /// @param _user                          Address of user who wants loan
    /// @param _amount                        Amount of requested loan
    /// @return                               Amount of given loan after reducing the fee
    function getLoan(address _user, uint _amount) nonReentrant override external returns (bool) {
        require(_msgSender() == instantRouter, "InstantPool: sender is not allowed");
        require(availableTeleBTC() >= _amount, "InstantPool: liquidity is not sufficient");
        // Instant fee increases the total teleBTC amount
        uint instantFee = _amount*instantPercentageFee/10000;
        // totalAddedTeleBTC = totalAddedTeleBTC + instantFee;
        IERC20(teleBTC).transfer(_user, _amount);
        emit InstantLoan(_user, _amount, instantFee);
        return true;
    }

}