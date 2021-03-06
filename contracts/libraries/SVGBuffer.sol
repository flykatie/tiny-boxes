//SPDX-License-Identifier: Unlicensed

pragma solidity ^0.6.4;

import "@openzeppelin/contracts/utils/Strings.sol";

import "../structs/Decimal.sol";

import "./Decimal.sol";

library SVGBuffer {
    using DecimalUtils for Decimal;
    using Strings for *;

    function hasCapacityFor(bytes memory buffer, uint256 needed)
        internal
        pure
        returns (bool)
    {
        uint256 size;
        uint256 used;

        assembly {
            size := mload(buffer)
            used := mload(add(buffer, 32))
        }
        return size >= 32 && used <= size - 32 && used + needed <= size - 32;
    }

    function toString(bytes memory buffer)
        internal
        pure
        returns (string memory)
    {
        require(hasCapacityFor(buffer, 0), "Buffer.toString: invalid buffer");
        string memory ret;
        assembly {
            ret := add(buffer, 32)
        }
        return ret;
    }

    function append(bytes memory buffer, string memory str) internal view {
        require(
            hasCapacityFor(buffer, bytes(str).length),
            "Buffer.append: no capacity"
        );
        assembly {
            let len := mload(add(buffer, 32))
            pop(
                staticcall(
                    gas(),
                    0x4,
                    add(str, 32),
                    mload(str),
                    add(len, add(buffer, 64)),
                    mload(str)
                )
            )
            mstore(add(buffer, 32), add(len, mload(str)))
        }
    }

    function rect(
        bytes memory buffer,
        Decimal[2] memory positions,
        Decimal[2] memory size,
        Decimal memory opacity,
        uint256 _radius,
        uint256 rgb
    ) internal view {
        require(hasCapacityFor(buffer, 102), "Buffer.rect: no capacity");
        string memory xpos = positions[0].toString();
        string memory ypos = positions[1].toString();
        string memory width = size[0].toString();
        string memory height = size[1].toString();
        string memory radius = _radius.toString();
        string memory opacityString = opacity.toString();
        assembly {
            function numbx1(x, v) -> y {
                // v must be in the closed interval [0, 9]
                // otherwise it outputs junk
                mstore8(x, add(v, 48))
                y := add(x, 1)
            }
            function numbx2(x, v) -> y {
                // v must be in the closed interval [0, 99]
                // otherwise it outputs junk
                y := numbx1(numbx1(x, div(v, 10)), mod(v, 10))
            }
            function numbu3(x, v) -> y {
                // v must be in the closed interval [0, 999]
                // otherwise only the last 3 digits will be converted
                switch lt(v, 100)
                    case 0 {
                        // without input value sanitation: y := numbx2(numbx1(x, div(v, 100)), mod(v, 100))
                        y := numbx2(
                            numbx1(x, mod(div(v, 100), 10)),
                            mod(v, 100)
                        )
                    }
                    default {
                        switch lt(v, 10)
                            case 0 {
                                y := numbx2(x, v)
                            }
                            default {
                                y := numbx1(x, v)
                            }
                    }
            }
            function numbi3(x, v) -> y {
                // v must be in the closed interval [-999, 999]
                // otherwise only the last 3 digits will be converted
                if slt(v, 0) {
                    v := add(not(v), 1)
                    mstore8(x, 45) // minus sign
                    x := add(x, 1)
                }
                y := numbu3(x, v)
            }
            function hexrgb(x, v) -> y {
                let blo := and(v, 0xf)
                let bhi := and(shr(4, v), 0xf)
                let glo := and(shr(8, v), 0xf)
                let ghi := and(shr(12, v), 0xf)
                let rlo := and(shr(16, v), 0xf)
                let rhi := and(shr(20, v), 0xf)
                mstore8(x, add(add(rhi, mul(div(rhi, 10), 39)), 48))
                mstore8(add(x, 1), add(add(rlo, mul(div(rlo, 10), 39)), 48))
                mstore8(add(x, 2), add(add(ghi, mul(div(ghi, 10), 39)), 48))
                mstore8(add(x, 3), add(add(glo, mul(div(glo, 10), 39)), 48))
                mstore8(add(x, 4), add(add(bhi, mul(div(bhi, 10), 39)), 48))
                mstore8(add(x, 5), add(add(blo, mul(div(blo, 10), 39)), 48))
                y := add(x, 6)
            }
            function append(x, str, len) -> y {
                mstore(x, str)
                y := add(x, len)
            }
            let strIdx := add(mload(add(buffer, 32)), add(buffer, 64))
            strIdx := append(strIdx, '<rect x="', 9)
            strIdx := append(strIdx, xpos, 3)
            strIdx := append(strIdx, '" y="', 5)
            strIdx := append(strIdx, ypos, 3)
            strIdx := append(strIdx, '" width="', 9)
            strIdx := append(strIdx, width, 3)
            strIdx := append(strIdx, '" height="', 10)
            strIdx := append(strIdx, height, 3)
            strIdx := append(strIdx, '" rx="', 6)
            strIdx := append(strIdx, radius, 3)
            strIdx := append(strIdx, '" style="fill:#', 15)
            strIdx := hexrgb(strIdx, rgb)
            strIdx := append(strIdx, "; fill-opacity:", 14)
            strIdx := append(strIdx, opacityString, 7)
            strIdx := append(strIdx, '"/>', 3)
            mstore(add(buffer, 32), sub(sub(strIdx, buffer), 64))
        }
    }
}
