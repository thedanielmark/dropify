
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IVault{


    function releaseTokens(address to, uint256 amount) external;
}