//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract LayerEdgeToken is ERC20 {
    constructor(string memory name, string memory symbol, uint256 _totalSupply, address _to) ERC20(name, symbol) {
        _mint(_to, _totalSupply);
    }
}
