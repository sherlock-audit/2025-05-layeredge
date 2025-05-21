//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FenwickTree} from "@src/library/FenwickTree.sol";
import {console2} from "forge-std/console2.sol";

contract FenwickTreeTest is Test {
    using FenwickTree for FenwickTree.Tree;

    FenwickTree.Tree tree;
    FenwickTree.Tree tree2;

    function setUp() public {
        tree.size = 100_000_000;
        tree2.size = 1_000_000_000;
        vm.pauseGasMetering();
        _fillTree();
        vm.resumeGasMetering();
    }

    function _fillTree() internal {
        for (uint256 i = 1; i < 100_000; i++) {
            tree.update(i, 1);
        }
    }

    function test_FenwickTree_query() public {
        //Remove randomnly 1000 values from the tree
        vm.pauseGasMetering();
        for (uint256 i = 0; i < 1000; i++) {
            tree.update(uint256(keccak256(abi.encodePacked(i))) % 100_000, -1);
        }
        vm.resetGasMetering();

        tree.query(10_000);
    }

    function test_FenwickTree_update() public {
        vm.pauseGasMetering();
        for (uint256 i = 1; i <= 100_000; i++) {
            tree2.update(i, 1);
        }
        vm.resumeGasMetering();

        tree2.update(100_001, 1);
    }
}
