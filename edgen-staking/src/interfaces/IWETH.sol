// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}
