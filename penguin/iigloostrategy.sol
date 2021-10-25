// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;


import "./IERC20.sol";

//owned by the IglooMaster contract
interface IIglooStrategy {
    // Deposit amount of tokens for 'caller' to address 'to'
    function deposit(address caller, address to, uint256 tokenAmount, uint256 shareAmount) external;
    // Transfer tokens from strategy for 'caller' to address 'to'
    function withdraw(address caller, address to, uint256 tokenAmount, uint256 shareAmount) external;
    function inCaseTokensGetStuck(IERC20 token, address to, uint256 amount) external;
    function setAllowances() external;
    function revokeAllowance(address token, address spender) external;
    function migrate(address newStrategy) external;
    function onMigration() external;
    function pendingTokens(uint256 pid, address user, uint256 pefiAmount) external view returns (address[] memory, uint256[] memory);
    function transferOwnership(address newOwner) external;
    function setPerformanceFeeBips(uint256 newPerformanceFeeBips) external;
}