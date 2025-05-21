// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library FenwickTree {
    struct Tree {
        mapping(uint256 => uint256) data;
        uint256 size;
    }

    function update(Tree storage self, uint256 index, int256 delta) internal {
        require(index > 0, "Index must be > 0");
        while (index <= self.size) {
            self.data[index] = uint256(int256(self.data[index]) + delta);
            index += lsb(index);
        }
    }

    function query(Tree storage self, uint256 index) internal view returns (uint256 sum) {
        while (index > 0) {
            sum += self.data[index];
            index -= lsb(index);
        }
    }

    function lsb(uint256 x) private pure returns (uint256) {
        return x & (~x + 1);
    }

    function findByCumulativeFrequency(Tree storage self, uint256 freq) internal view returns (uint256) {
        uint256 idx = 0;
        uint256 bitMask = highestPowerOfTwo(self.size);

        while (bitMask > 0) {
            uint256 next = idx + bitMask;
            if (next <= self.size && self.data[next] < freq) {
                freq -= self.data[next];
                idx = next;
            }
            bitMask >>= 1;
        }

        return idx + 1; // +1 since idx is the largest with prefixSum < freq
    }

    function highestPowerOfTwo(uint256 x) private pure returns (uint256) {
        uint256 power = 1;
        while (power << 1 <= x) {
            power <<= 1;
        }
        return power;
    }
}
