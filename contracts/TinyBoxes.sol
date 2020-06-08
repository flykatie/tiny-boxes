pragma solidity ^0.6.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


library Buffer {
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
        int256[2] memory positions,
        uint256[2] memory size,
        uint256 rgb
    ) internal pure {
        require(hasCapacityFor(buffer, 102), "Buffer.rect: no capacity");
        int256 xpos = positions[0];
        int256 ypos = positions[1];
        uint256 width = size[0];
        uint256 height = size[1];
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
            strIdx := numbi3(strIdx, xpos)
            strIdx := append(strIdx, '" y="', 5)
            strIdx := numbi3(strIdx, ypos)
            strIdx := append(strIdx, '" width="', 9)
            strIdx := numbu3(strIdx, width)
            strIdx := append(strIdx, '" height="', 10)
            strIdx := numbu3(strIdx, height)
            strIdx := append(strIdx, '" style="fill:#', 15)
            strIdx := hexrgb(strIdx, rgb)
            strIdx := append(strIdx, '; fill-opacity:1.0;"/>\n', 23)
            mstore(add(buffer, 32), sub(sub(strIdx, buffer), 64))
        }
    }
}


library Random {
    /**
     * Initialize the pool with the entropy of the blockhashes of the blocks in the closed interval [earliestBlock, latestBlock]
     * The argument "seed" is optional and can be left zero in most cases.
     * This extra seed allows you to select a different sequence of random numbers for the same block range.
     */
    function init(
        uint256 earliestBlock,
        uint256 latestBlock,
        uint256 seed
    ) internal view returns (bytes32[] memory) {
        //require(block.number-1 >= latestBlock && latestBlock >= earliestBlock && earliestBlock >= block.number-256, "Random.init: invalid block interval");
        require(
            block.number - 1 >= latestBlock && latestBlock >= earliestBlock,
            "Random.init: invalid block interval"
        );
        bytes32[] memory pool = new bytes32[](latestBlock - earliestBlock + 2);
        bytes32 salt = keccak256(abi.encodePacked(earliestBlock, seed));
        for (uint256 i = 0; i <= latestBlock - earliestBlock; i++) {
            // Add some salt to each blockhash so that we don't reuse those hash chains
            // when this function gets called again in another block.
            pool[i + 1] = keccak256(
                abi.encodePacked(blockhash(earliestBlock + i), salt)
            );
        }
        return pool;
    }

    /**
     * Initialize the pool from the latest "num" blocks.
     */
    function initLatest(uint256 num, uint256 seed)
        internal
        view
        returns (bytes32[] memory)
    {
        return init(block.number - num, block.number - 1, seed);
    }

    /**
     * Advances to the next 256-bit random number in the pool of hash chains.
     */
    function next(bytes32[] memory pool) internal pure returns (uint256) {
        require(pool.length > 1, "Random.next: invalid pool");
        uint256 roundRobinIdx = (uint256(pool[0]) % (pool.length - 1)) + 1;
        bytes32 hash = keccak256(abi.encodePacked(pool[roundRobinIdx]));
        pool[0] = bytes32(uint256(pool[0]) + 1);
        pool[roundRobinIdx] = hash;
        return uint256(hash);
    }

    function stringToUint(string memory s)
        internal
        pure
        returns (uint256 result)
    {
        bytes memory b = bytes(s);
        uint256 i;
        result = 0;
        for (i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
    }

    /**
     * Produces random integer values, uniformly distributed on the closed interval [a, b]
     */
    function uniform(
        bytes32[] memory pool,
        int256 a,
        int256 b
    ) internal pure returns (int256) {
        require(a <= b, "Random.uniform: invalid interval");
        return int256(next(pool) % uint256(b - a + 1)) + a;
    }
}


contract TinyBoxes is ERC721 {
    uint256 public constant TOKEN_LIMIT = 80; // 80 for testing, 800 for prod;
    uint256 public constant ARTIST_PRINTS = 1;
    address public creator;
    string header = '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="-100 -100 2600 2600" style="stroke-width:0; background-color:#121212;">\n\n<symbol id="upperleftquad4">\n<symbol id="upperleftquad3">\n<symbol id="upperleftquad2">\n<symbol id="upperleftquad">\n\n';
    address payable artmuseum = 0x027Fb48bC4e3999DCF88690aEbEBCC3D1748A0Eb; //lolz

    mapping(uint256 => uint256) internal idToSeed;
    mapping(uint256 => uint256[]) internal idToCounts;
    mapping(uint256 => int256[]) internal idToDials;
    mapping(uint256 => bool[]) internal idToSwitches;

    /**
     * @dev Contract constructor.
     */
    constructor() public ERC721("tinyboxes", "[#][#]") {
        creator = msg.sender;
    }

    /**
     * @dev generate a color
     * @param pool randomn numbers
     * @param _id of token to render
     * @return color value
     */
    function _generateColor(bytes32[] memory pool, uint256 _id)
        internal
        view
        returns (uint256)
    {
        uint256 red = uint256(Random.uniform(pool, 0x000012, 0x0000ff));
        uint256 green = uint256(Random.uniform(pool, 0x000012, 0x0000ff) * 256);
        uint256 blue = uint256(
            Random.uniform(pool, 0x000012, 0x0000ff) * 65536
        );
        uint256 colorscheme = uint256(Random.uniform(pool, 0, 99));

        if (_id == 0) {
            return 0x000000; // all black
        } else if (_id > 73 && _id < 80) {
            return uint256(0xffffff); // all white
        } else if (colorscheme < 7) {
            return blue;
        } else if (colorscheme < 14) {
            return green;
        } else if (colorscheme < 21) {
            return red;
        } else if (colorscheme < 35) {
            return green + blue;
        } else if (colorscheme < 49) {
            return red + blue;
        } else if (colorscheme < 63) {
            return red + green;
        } else if (colorscheme < 66) {
            uint256 brightness = uint256(
                Random.uniform(pool, 0x000022, 0x0000ee)
            ); // random greys
            return (brightness * 65536) + (brightness * 256) + brightness;
        } else {
            return blue;
        }
    }

    /**
     * @dev generate a shape
     * @param pool randomn numbers
     * @param dials for generator settings
     * @param hatch mode on
     * @return positions of shape
     */
    function _generateShape(
        bytes32[] memory pool,
        int256[13] memory dials,
        bool hatch
    )
        internal
        view
        returns (int256[2] memory positions, uint256[2] memory size)
    {
        positions = [
            Random.uniform(pool, -(dials[0]), dials[0]) +
                ((Random.uniform(pool, 0, dials[2] - 1) * 800) / (dials[2])),
            Random.uniform(pool, -(dials[1]), dials[1]) +
                ((Random.uniform(pool, 0, dials[3] - 1) * 800) / (dials[3]))
        ];
        if (hatch) {
            uint256 horizontal = uint256(Random.uniform(pool, 0, 1));
            // 		size[0] = uint(Random.uniform(pool, dials[4], dials[5])) + horizontal * uint(dials[6]);
            //      size[1] = uint(dials[6]) + uint(dials[5])  - size[0] + uint256(Random.uniform(pool, dials[7], dials[4]));
            uint256 width = uint256(Random.uniform(pool, 25, 40)) +
                uint256(700 * horizontal);
            size = [
                width,
                uint256(Random.uniform(pool, 10, 25)) + uint256(740 - width)
            ];
        } else
            size = [
                uint256(Random.uniform(pool, dials[4], dials[5])),
                uint256(Random.uniform(pool, dials[6], dials[7]))
            ];
    }

    /**
     * @dev render the footer string for mirring effects
     * @param switches for each mirroring stage
     * @param mirrorDials for generator settings
     * @return footer string
     */
    function _generateFooter(
        bool[3] memory switches,
        int256[4] memory mirrorDials
    ) internal view returns (string memory footer) {
        bytes memory buffer = new bytes(8192);

        string[3] memory scales = ["-1 1", "-1 -1", "1 -1"];
        string[7] memory template = [
            "\n<g>",
            '\n<g transform="scale(',
            ") translate(",
            ')">',
            '\n<use xlink:href="#upperleftquad',
            '"/>\n</g>',
            "\n</symbol>"
        ];

        for (uint8 s = 0; s < 3; s++) {
            // loop through mirroring effects
            Buffer.append(buffer, template[6]);

            if (!switches[s]) {
                // turn off this level of mirroring
                // add a scale transform
                Buffer.append(buffer, template[0]);
                // denote what quad the transform should be used for
                Buffer.append(buffer, template[4]);
                if (s > 0)
                    Buffer.append(buffer, Strings.toString(uint256(s + 1)));
                Buffer.append(buffer, template[5]);
            } else {
                string memory value = Strings.toString(uint256(mirrorDials[s]));
                for (uint8 i = 0; i < 4; i++) {
                    // loop through transforms
                    if (i == 0) Buffer.append(buffer, template[0]);
                    else {
                        Buffer.append(buffer, template[1]);
                        Buffer.append(buffer, scales[i - 1]);
                        Buffer.append(buffer, template[2]);
                        if (i <= 2) Buffer.append(buffer, "-");
                        Buffer.append(buffer, i <= 2 ? value : "0");
                        Buffer.append(buffer, " ");
                        if (i >= 2) Buffer.append(buffer, "-");
                        Buffer.append(buffer, i >= 2 ? value : "0");
                        Buffer.append(buffer, template[3]);
                    }
                    // denote what quad the transformsshould be used for
                    Buffer.append(buffer, template[4]);
                    if (s > 0)
                        Buffer.append(buffer, Strings.toString(uint256(s + 1)));
                    Buffer.append(buffer, template[5]);
                }
            }
        }
        // add final scaling
        uint256 scaleDial = uint256(mirrorDials[3]);
        string memory scaleWhole = Strings.toString(scaleDial.div(100));
        string memory scaleDecimals = Strings.toString(scaleDial.mod(100));
        Buffer.append(buffer, template[6]);
        Buffer.append(buffer, template[1]);
        Buffer.append(buffer, scaleWhole);
        Buffer.append(buffer, ".");
        Buffer.append(buffer, scaleDecimals);
        Buffer.append(buffer, " ");
        Buffer.append(buffer, scaleWhole);
        Buffer.append(buffer, ".");
        Buffer.append(buffer, scaleDecimals);
        Buffer.append(buffer, template[3]);
        Buffer.append(buffer, template[4]);
        Buffer.append(buffer, "4");
        Buffer.append(buffer, template[5]);

        Buffer.append(buffer, "\n</svg>"); // add closing svg tag
        return Buffer.toString(buffer);
    }

    /**
     * @dev render a token's art
     * @param _id of token
     * @param seed for randomness
     * @param counts of colors and shapes
     * @param dials for shape generator
     * @param switches for renderer options
     * @return the SVG graphiccs of the token
     */
    function perpetualRenderer(
        uint256 _id,
        string memory seed,
        uint256[2] memory counts,
        int256[13] memory dials,
        bool[3] memory switches
    ) public view returns (string memory) {
        bytes memory buffer = new bytes(8192);
        Buffer.append(buffer, header);

        // initilized RNG with the seed and blocks 0 through 1
        bytes32[] memory pool = Random.init(0, 1, Random.stringToUint(seed));

        // generate colors
        uint256[] memory colorValues = new uint256[](counts[0]);
        for (uint256 i = 0; i < counts[0]; i++)
            colorValues[i] = _generateColor(pool, _id);

        // generate shapes
        uint256 hybrid = uint256(dials[8]); // hatching mod. 1 in hybrid shapes will be hatching type
        for (uint256 i = 0; i < counts[1]; i++) {
            uint256 colorRand = uint256(
                Random.uniform(pool, 0, int256(counts[0].sub(1)))
            );
            (
                int256[2] memory positions,
                uint256[2] memory size
            ) = _generateShape(pool, dials, (hybrid > 0 && i.mod(hybrid) == 0));
            Buffer.rect(buffer, positions, size, colorValues[colorRand]);
        }

        // generate the footer with mirroring transforms
        int256[4] memory mirrorDials = [
            dials[9],
            dials[10],
            dials[11],
            dials[12]
        ];
        Buffer.append(buffer, _generateFooter(switches, mirrorDials));

        return Buffer.toString(buffer);
    }

    /**
     * @dev Create a new TinyBox Token
     * @param seed for the string
     * @param counts of colors and shapes
     * @param dials for settings of the renderer
     * @param switches for renderer settings
     */
    function createBox(
        string calldata seed,
        uint256[2] calldata counts,
        int256[13] calldata dials,
        bool[3] calldata switches
    ) external payable {
        require(msg.sender != address(0), "token recipient man not be the zero address");
        require(
            totalSupply() < TOKEN_LIMIT,
            "ART SALE IS OVER. Tinyboxes are now only available on the secondary market."
        );
        //require(block.timestamp < 1574711999, "ART SALE IS OVER. Tinyboxes are now only available on the secondary market.");

        if (totalSupply() < ARTIST_PRINTS) {
            require(
                msg.sender == address(creator),
                "Only the creator can mint the alpha token. Wait your turn FFS"
            );
        } else {
            uint256 amount = currentPrice();
            require(msg.value >= amount, "insuficient payment"); // return if they dont pay enough
            if (msg.value > amount) msg.sender.transfer(msg.value - amount); // give change if they over pay
            artmuseum.transfer(amount); // send the payment amount to the artmuseum account
        }

        uint256 id = totalSupply();

        idToSeed[id] = Random.stringToUint(seed);
        idToCounts[id] = counts;
        idToDials[id] = dials;
        idToSwitches[id] = switches;

        _safeMint(msg.sender, id);
    }

    /**
     * @dev Get the current price of a token
     * @return price in wei of a token currently
     */
    function currentPrice() public view returns (uint256 price) {
        price = priceAt(totalSupply());
    }

    /**
     * @dev Get the price of a specific token id
     * @param _id of the token
     * @return price in wei of that token
     */
    function priceAt(uint256 _id) public view returns (uint256 price) {
        uint256 tokeninflation = (_id / 2) * 1000000000000000; // add .001 eth inflation per token
        price = tokeninflation + 160000000000000000; // in wei, starting price .16 eth, ending price .2 eth
    }

    /**
     * @dev Lookup the seed
     * @param _id for which we want the seed
     * @return seed value of _id.
     */
    function tokenSeed(uint256 _id) external view returns (uint256) {
        return idToSeed[_id];
    }

    /**
     * @dev Lookup the counts
     * @param _id for which we want a count
     * @return colorCount of _id.
     */
    function tokenCounts(uint256 _id) external view returns (uint256[] memory) {
        return idToCounts[_id];
    }

    /**
     * @dev Lookup the dials
     * @param _id for which we want the dials
     * @return dial values of _id.
     */
    function tokenDials(uint256 _id) external view returns (int256[] memory) {
        return idToDials[_id];
    }

    /**
     * @dev Lookup the switches
     * @param _id for which we want the dials
     * @return switch values of _id.
     */
    function tokenSwitches(uint256 _id) external view returns (bool[] memory) {
        return idToSwitches[_id];
    }

    /**
     * @dev Generate the token SVG art
     * @param _id for which we want art
     * @return URI of _id.
     */
    function tokenArt(uint256 _id) external view returns (string memory) {
        string memory seed = Strings.toString(idToSeed[_id]);
        uint256[2] memory counts = [idToCounts[_id][0], idToCounts[_id][1]];
        int256[13] memory dials = [
            idToDials[_id][0],
            idToDials[_id][1],
            idToDials[_id][2],
            idToDials[_id][3],
            idToDials[_id][4],
            idToDials[_id][5],
            idToDials[_id][6],
            idToDials[_id][7],
            idToDials[_id][8],
            idToDials[_id][9],
            idToDials[_id][10],
            idToDials[_id][11],
            idToDials[_id][12]
        ];
        bool[3] memory switches = [
            idToSwitches[_id][0],
            idToSwitches[_id][1],
            idToSwitches[_id][2]
        ];
        return perpetualRenderer(_id, seed, counts, dials, switches);
    }
}