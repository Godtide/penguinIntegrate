 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;


interface IRewarder {
    function onPefiReward(uint256 pid, address user, address recipient, uint256 pefiAmount, uint256 newShareAmount) external;
    function pendingTokens(uint256 pid, address user, uint256 pefiAmount) external view returns (address[] memory, uint256[] memory);
}