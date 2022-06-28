pragma solidity 0.8.0;

import '../erc20/interfaces/IERC20.sol';
import './interfaces/IFastRouter.sol';
import '../pools/FastPool.sol';
import '../pools/interfaces/IFastPool.sol';
import './interfaces/ICCTransferRouter.sol';
import '../libraries/SafeMath.sol';

contract FastRouter is IFastRouter {
    
    using SafeMath for uint;
    address public override bitcoinFastPool;
    address public override ccTransferRouter;
    address public wrappedBitcoin;
    address public override owner;
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    constructor (address _ccTransferRouter, uint _fastLimit, uint _fastFee, uint _neededConfirmations) public {
        ccTransferRouter = _ccTransferRouter;
        wrappedBitcoin = ICCTransferRouter(ccTransferRouter).wrappedBitcoin();
        FastPool _bitcoinFastPool;
        _bitcoinFastPool = new FastPool(
            wrappedBitcoin, 
            address(this), 
            "BitcoinFastPoolToken", 
            "BTCFPT", 
            _fastLimit, 
            _fastFee, 
            _neededConfirmations,
            msg.sender
        );
        bitcoinFastPool = address(_bitcoinFastPool);
        owner = msg.sender;
    }
    
    function changeOwner(address _owner) external override onlyOwner {
        owner = _owner;
    }

    function setCCTransferRouter(address _ccTransferRouter) external override onlyOwner {
        ccTransferRouter = _ccTransferRouter;
    }
    // it is called by cc transfer router
    function fastTransfer(address receiver, uint amount, uint blockNumber) external override returns(bool){
        require(msg.sender == ccTransferRouter, "message sender was not cc transfer router");
        require(IFastPool(bitcoinFastPool).fastTransfer(
                receiver,
                amount,
                blockNumber),
            "transfer was not succesfull"
        ); // transfer bitcoin to user
        return true;
    }

    function getNeededConfirmations() public view override returns(uint) {
        return IFastPool(bitcoinFastPool).fastConfirmationParameter();
    }
    
    function addLiquidity(address user, uint wrappedBitcoinAmount) external override returns(uint){
        require(IERC20(wrappedBitcoin).transferFrom(
            msg.sender, address(this), 
            wrappedBitcoinAmount), 
            "user balance is not sufficient"
        );
        require(IERC20(wrappedBitcoin).approve(
            bitcoinFastPool, 
            wrappedBitcoinAmount), 
            "fast router balance is not sufficient"
        );
        return IFastPool(bitcoinFastPool).addLiquidity(user, wrappedBitcoinAmount);
    }

    function removeLiquidity(address user, uint fastPoolTokenAmount) external override returns(uint) {
        require(IFastPool(bitcoinFastPool).transferFrom(
            msg.sender, address(this), 
            fastPoolTokenAmount), 
            "user balance is not sufficient"
        );
        return IFastPool(bitcoinFastPool).removeLiquidity(user, fastPoolTokenAmount);
    }

}
