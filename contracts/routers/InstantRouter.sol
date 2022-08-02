// pragma solidity 0.8.0;


// import '../libraries/TeleportDAOLibrary.sol';
// import '../libraries/SafeMath.sol';
// import './interfaces/IInstantRouter.sol';
// import './interfaces/IExchangeRouter.sol';
// import './interfaces/ICCTransferRouter.sol';
// import '../pools/interfaces/IInstantPool.sol';
// import '../erc20/interfaces/IERC20.sol';
// import '../pools/interfaces/IInstantPool.sol';
// import '../pools/InstantPool.sol';
// import '../staking/interfaces/IStaking.sol';
// import "../relay/interfaces/IBitcoinRelay.sol";
// import 'hardhat/console.sol';

// contract InstantRouter is IInstantRouter {

//     using SafeMath for uint;
//     // mapping(address => uint) override public lockedTDT;
//     mapping(bytes32 => InstantTransferRequest) public requests;
//     mapping(bytes32 => bool) public isUsed;
//     mapping(address => debt[]) public debts;
//     uint punisherReward;
// uint override public paybackDeadline; // this is the deadline for paying back the borrowed amount
// address public liquidityPoolFactory;
// address public override wrappedBitcoin;
// address public override ccTransferRouter;
// address public override bitcoinInstantPool;
// address public TeleportDAOToken;
// address public WAVAX;
// address public exchangeRouter;
// address public staking;
// address public bitcoinRelay;
// uint public override collateralRatio; // multplied by 100
// address public override owner;

// modifier onlyOwner {
// require(msg.sender == owner);
// _;
// }

// constructor (
// address _ccTransferRouter,
// address _exchangeRouter,
// address _TeleportDAOToken,
// address _liquidityPoolFactory,
// address _staking,
// address _bitcoinRelay,
// uint _punisherReward,
// uint _paybackDeadline,
// uint _collateralRatio,
// uint _instantFee
// ) public {
// ccTransferRouter = _ccTransferRouter;
// // FIXME: update based on new cc transfer
// // wrappedBitcoin = ICCTransferRouter(ccTransferRouter).wrappedBitcoin();
// exchangeRouter = _exchangeRouter;
// WAVAX = IExchangeRouter(exchangeRouter).WAVAX();
// TeleportDAOToken = _TeleportDAOToken;
// staking = _staking;
// bitcoinRelay = _bitcoinRelay;
// punisherReward = _punisherReward;
// liquidityPoolFactory = _liquidityPoolFactory;
// paybackDeadline = _paybackDeadline;
// collateralRatio = _collateralRatio;
// InstantPool _bitcoinInstantPool;
// _bitcoinInstantPool = new InstantPool(
// address(this),
// wrappedBitcoin,
// "BitcoinInstantPoolToken",
// "BIPT",
// msg.sender,
// _instantFee
// );
// bitcoinInstantPool = address(_bitcoinInstantPool);
// owner = msg.sender;
// }

// function changeOwner(address _owner) external override onlyOwner {
// owner = _owner;
// }

// function setExchangeRouter (address _exchangeRouter) external override onlyOwner {
// exchangeRouter = _exchangeRouter;
// WAVAX = IExchangeRouter(exchangeRouter).WAVAX();
// }

// function setCCTransferRouter (address _ccTransferRouter) external override onlyOwner {
// ccTransferRouter = _ccTransferRouter;
// }

// function setPaybackDeadline (uint _paybackDeadline) external override onlyOwner {
// paybackDeadline = _paybackDeadline;
// }

// function setPunisherReward (uint _punisherReward) external override onlyOwner {
// punisherReward = _punisherReward;
// }

// function setCollateralRatio (uint _paybackDeadline) external override onlyOwner {
// paybackDeadline = _paybackDeadline;
// }

// function requestCollateralAmount (bytes32 messageHash) public view override returns(uint) {
// return requests[messageHash].collateralAmount;
// }

// function addLiquidity(address user, uint wrappedBitcoinAmount) public override returns(uint) {
// IERC20(wrappedBitcoin).transferFrom(msg.sender, address(this), wrappedBitcoinAmount);
// // InstantRouter allows instantPool to transfer from it
// IERC20(wrappedBitcoin).approve(bitcoinInstantPool, wrappedBitcoinAmount);
// return IInstantPool(bitcoinInstantPool).addLiquidity(user, wrappedBitcoinAmount);
// }

// function removeLiquidity(address user, uint instantPoolTokenAmount) public override returns(uint) {
// uint ipBalance = IInstantPool(bitcoinInstantPool).balanceOf(msg.sender);
// require(ipBalance >= instantPoolTokenAmount, "instant pool token is not enough");
// // send ipToken to InstantRouter
// IInstantPool(bitcoinInstantPool).transferFrom(msg.sender, address(this), instantPoolTokenAmount);
// // remove liquidity from instant pool
// return IInstantPool(bitcoinInstantPool).removeLiquidity(user, instantPoolTokenAmount);
// }

// function _instantTransfer (
// address user,
// address receiver,
// uint amount,
// uint deadline,
// bytes32 messageHash
// ) internal returns(bool) {
// require(deadline >= block.number, "deadline has passed");
// uint _requiredTDT = requiredTDT(amount)*(collateralRatio/100);
// uint requiredStakingShare = IStaking(staking).equivalentStakingShare(_requiredTDT);
// uint userStakingShare = IStaking(staking).stakingShare(user);
// require(userStakingShare >= requiredStakingShare,"TDT staked amount is not sufficient");
// IStaking(staking).unstake(user, requiredStakingShare);
// // transfer wrappedBitcoin to user
// require(
// IInstantPool(bitcoinInstantPool).instantTransfer(receiver, amount),
// "transfer was not succesfull"
// );
// debt memory _debt;
// _debt.user = user;
// _debt.wrappedBitcoinAmount = amount;
// _debt.collateralAmount = _requiredTDT;
// _debt.deadline = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight() + paybackDeadline;
// debts[user].push(_debt);
// isUsed[messageHash] = true;

// }

// function _instantExchange (
// address user,
// address receiver,
// uint amountIn,
// uint amountOutMin,
// address[] memory path,
// uint deadline,
// bytes32 messageHash
// ) internal returns(uint[] memory amounts, bool result) {
// require(deadline >= block.number, "deadline has passed");
// // check that path[0] is wrapped bitcoin
// require(path[0] == wrappedBitcoin, "input token is not correct");
// // check that the signer has locked enough TDT
// uint _requiredTDT = requiredTDT(amountIn)*(collateralRatio/100);
// uint requiredStakingShare = IStaking(staking).equivalentStakingShare(_requiredTDT);
// require(IStaking(staking).stakingShare(user) >= requiredStakingShare,"TDT staked amount is not sufficient");
// IStaking(staking).unstake(user, requiredStakingShare);
// // transfer wrappedBitcoin to the instant router
// require(
// IInstantPool(bitcoinInstantPool).instantTransfer(address(this), amountIn),
// "transfer was not succesfull"
// );
// debt memory _debt;
// _debt.user = user;
// _debt.wrappedBitcoinAmount = amountIn;
// _debt.collateralAmount = _requiredTDT;
// _debt.deadline = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight() + paybackDeadline;
// debts[user].push(_debt);
// isUsed[messageHash] = true;
// // reduce the instant fee from amountIn
// amountIn = amountIn*(100-InstantPool(bitcoinInstantPool).instantFee())/100;
// // give allowance to exchangeRouter
// IERC20(path[0]).approve(exchangeRouter, amountIn);
// // call exchangeRouter
// if (path[path.length-1] == WAVAX) {
// (amounts, result) = IExchangeRouter(exchangeRouter).swapExactTokensForAVAX(
// amountIn,
// amountOutMin,
// path,
// receiver,
// deadline
// );
// } else {
// (amounts, result) = IExchangeRouter(exchangeRouter).swapExactTokensForTokens(
// amountIn,
// amountOutMin,
// path,
// receiver,
// deadline
// );
// }

// }

// function instantCCTransfer (address receiver, uint amount, uint deadline) public override returns (bool) {
// bytes32 messageHash = keccak256(abi.encodePacked(msg.sender, amount, deadline));
// _instantTransfer(msg.sender, receiver, amount, deadline, messageHash);
// }

// // TODO: give time to user to pay back the instant transfer based on the last finalized block header of the relay
// // user signs the request using the target blockchain wallet
// function instantCCTransferWithPermit (
// address signer,
// bytes memory signature,
// address receiver,
// uint amount,
// uint deadline
// ) public override returns(bool) {
// bytes32 messageHash = keccak256(abi.encodePacked(signer, amount, deadline));
// // require(requests[messageHash].isUsed == false, "request has been executed before");
// require(isUsed[messageHash] == false, "request has been executed before");
// require(
// verifySignature(signer, signature, messageHash),
// "signature is not valid"
// );
// _instantTransfer(signer, receiver, amount, deadline, messageHash);
// }

// function instantCCExchange (
// uint amountIn,
// uint amountOutMin,
// address[] memory path,
// address receiver,
// uint deadline
// ) public override returns(uint[] memory amounts, bool result) {
// bytes32 messageHash = keccak256(
// abi.encodePacked(amountIn, amountOutMin, path[path.length-1], msg.sender, deadline)
// );
// return _instantExchange(msg.sender, receiver, amountIn, amountOutMin, path, deadline, messageHash);
// }

// function instantCCExchangeWithPermit(
// address signer,
// bytes memory signature,
// uint amountIn,
// uint amountOutMin,
// address[] memory path,
// address receiver,
// uint deadline
// ) public override returns(uint[] memory amounts, bool result) {
// bytes32 messageHash = keccak256(
// abi.encodePacked(amountIn, amountOutMin, path[path.length-1], receiver, deadline)
// );
// require(isUsed[messageHash] == false, "request has been executed before");
// // require(requests[messageHash].isUsed == false, "request has been executed before");
// // verify the correctness of signature
// require(
// verifySignature(signer, signature, messageHash),
// "signature is not valid"
// );
// return _instantExchange(signer, receiver, amountIn, amountOutMin, path, deadline, messageHash);
// }

// function payBackInstantTransfer (uint bitcoinAmount, address user) public override returns (bool) {

// uint unlockedCollateralAmount;
// uint _bitcoinAmount = bitcoinAmount;
// uint lastSubmittedHeight = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight();
// for (uint i = 0; i < debts[user].length; i++) {
// if (_bitcoinAmount >= debts[user][i].wrappedBitcoinAmount && debts[user][i].deadline >= lastSubmittedHeight) {
// IERC20(wrappedBitcoin).transferFrom(msg.sender, bitcoinInstantPool, debts[user][i].wrappedBitcoinAmount);
// unlockedCollateralAmount = unlockedCollateralAmount + debts[user][i].collateralAmount;
// _bitcoinAmount = _bitcoinAmount - debts[user][i].wrappedBitcoinAmount;
// // delete debt after user pay it
// delete debts[user][i];
// } else if (debts[user][i].deadline <= lastSubmittedHeight) {
// IERC20(wrappedBitcoin).transferFrom(ccTransferRouter, bitcoinInstantPool, _bitcoinAmount);
// debts[user][i].wrappedBitcoinAmount = debts[user][i].wrappedBitcoinAmount - _bitcoinAmount;
// _bitcoinAmount = 0;
// break;
// }
// }

// if (_bitcoinAmount > 0) {
// IERC20(wrappedBitcoin).transferFrom(msg.sender, user, _bitcoinAmount);
// }

// // stake the unlocked collateral
// if (unlockedCollateralAmount > 0) {
// IERC20(TeleportDAOToken).approve(staking, unlockedCollateralAmount);
// IStaking(staking).stake(user, unlockedCollateralAmount);
// }

// emit PaybackInstantLoan(user, bitcoinAmount);
// return true;

// }

// function requiredTDT (uint wrappedBitcoinAmount) private returns(uint){
// (uint wrappedBitcoinReserve, uint TeleportDAOTokenReserve) = TeleportDAOLibrary.getReserves(
// liquidityPoolFactory,
// wrappedBitcoin,
// TeleportDAOToken);
// uint _requiredTDT = TeleportDAOLibrary.getAmountIn(wrappedBitcoinAmount, TeleportDAOTokenReserve, wrappedBitcoinReserve);
// return _requiredTDT;
// }

// function punishUser (address user, uint[] memory debtIndex) override external returns (bool) {

// require(debts[user].length >= debtIndex.length, "too many indexes");
// uint wrappedBitcoinAmount;
// uint collateralAmount;
// uint lastSubmittedHeight = IBitcoinRelay(bitcoinRelay).lastSubmittedHeight();

// for (uint i = 0; i < debtIndex.length; i++) {
// require(debts[user][debtIndex[i]].deadline < lastSubmittedHeight, "deadline has not passed");
// wrappedBitcoinAmount = wrappedBitcoinAmount + debts[user][debtIndex[i]].wrappedBitcoinAmount;
// collateralAmount = collateralAmount + debts[user][debtIndex[i]].collateralAmount;
// delete debts[user][debtIndex[i]];
// // TODO: delete operation leaves gaps. remove gaps
// }
// uint _requiredTDT = requiredTDT(wrappedBitcoinAmount); // needed TDT amount to buy wrappedBitcoin
// // address[] memory path;
// address[] memory path = new address[](2);
// path[0] = TeleportDAOToken;
// path[1] = wrappedBitcoin;
// buyWrappedBitcoinUsingTDT(
// _requiredTDT,
// wrappedBitcoinAmount,
// path,
// bitcoinInstantPool,
// 2*block.timestamp
// );

// // send rest of TDT to TeleportDAOTreasury and punisher
// uint remainedTDT = collateralAmount - _requiredTDT;
// IERC20(TeleportDAOToken).transfer(msg.sender, punisherReward*remainedTDT/100); // send reward to punisher
// emit PunishUser(user, wrappedBitcoinAmount);
// return true;
// }

// function buyWrappedBitcoinUsingTDT (
// uint amountIn,
// uint amountOutMin,
// address[] memory path,
// address to,
// uint deadline
// ) internal {
// console.log("buyWrappedBitcoinUsingTDT...");
// console.log("deadline");
// console.log(deadline);

// IERC20(TeleportDAOToken).approve(exchangeRouter, amountIn);
// IExchangeRouter(exchangeRouter).swapExactTokensForTokens(
// amountIn,
// amountOutMin,
// path,
// to,
// deadline
// );
// }
// // TODO: replace the buyWrappedBitcoinUsingTDT with the below function
// function _buyWrappedBitcoinUsingTDT(
// uint amountOut,
// uint amountInMax,
// address[] memory path,
// address to,
// uint deadline
// ) internal {
// IERC20(TeleportDAOToken).approve(exchangeRouter, amountInMax);
// IExchangeRouter(exchangeRouter).swapTokensForExactTokens(
// amountOut,
// amountInMax,
// path,
// to,
// deadline
// );
// }

// function verifySignature(
// address signer,
// bytes memory signature,
// bytes32 messageHash
// ) internal pure returns (bool) {
// bytes32 ethSignedMessageHash = keccak256(
// abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
// );
// return recoverSigner(ethSignedMessageHash, signature) == signer;
// }

// function recoverSigner(
// bytes32 ethSignedMessageHash,
// bytes memory signature
// ) internal pure returns (address) {
// (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);

// return ecrecover(ethSignedMessageHash, v, r, s);
// }

// function splitSignature(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
// require(signature.length == 65, "invalid signature length");
// assembly {
// r := mload(add(signature, 32))
// s := mload(add(signature, 64))
// v := byte(0, mload(add(signature, 96)))
// }
// }
// }
