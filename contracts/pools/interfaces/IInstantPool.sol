// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IInstantPool is IERC20 {

	// Events

	/// @notice                             emits when some liquidity gets added to the pool               
	/// @param user                         User who added the liquidity
	/// @param teleBTCAmount                Amount of teleBTC added to the pool
	/// @param instantPoolTokenAmount       User's share from the pool
	event AddLiquidity(address indexed user, uint teleBTCAmount, uint instantPoolTokenAmount); 

	/// @notice                             Emits when some liquidity gets removed from the pool
	/// @param user                         User who removed the liquidity
	/// @param teleBTCAmount                Amount of teleBTC removed from the pool
	/// @param instantPoolTokenAmount       User's share from the pool
	event RemoveLiquidity(address indexed user, uint teleBTCAmount, uint instantPoolTokenAmount);

	/// @notice                       Adds collateral to collateral pool
	/// @param user                   User who wants to get the loan
	/// @param requestedAmount        Amount of loan requested and sent to the user
	/// @param instantFee             Amount of fee that the user should pay back later with the loan
	event InstantLoan(address indexed user, uint256 requestedAmount, uint instantFee);

	// Read-only functions

	function teleBTC() external view returns (address);

	function instantRouter() external view returns (address);

	function totalAddedTeleBTC() external view returns (uint);

	function availableTeleBTC() external view returns (uint);

	function totalUnpaidLoan() external view returns (uint);

	function instantPercentageFee() external view returns (uint);

	function getFee(uint _loanAmount) external view returns (uint);

	// State-changing functions

	function setInstantRouter(address _instantRouter) external;

	function setInstantPercentageFee(uint _instantPercentageFee) external;

	function setTeleBTC(address _teleBTC) external;

	function addLiquidity(address _user, uint _amount) external returns (uint);

	function addLiquidityWithoutMint(uint _amount) external returns (bool);

	function removeLiquidity(address _user, uint _instantPoolTokenAmount) external returns (uint);

	function getLoan(address _user, uint _amount) external returns (bool);

}