//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.8;
pragma experimental ABIEncoderV2;

import "./TinyBoxesStore.sol";
import "./TinyBoxesRenderer.sol";

contract TinyBoxes is TinyBoxesStore {
    using TinyBoxesRenderer for TinyBox;
    using SVGBuffer for bytes;

    /**
     * @dev Contract constructor.
     * @notice Constructor inherits from TinyBoxesStore
     */
    constructor(
        address _link,
        address _feed
    )
        public
        TinyBoxesStore(_link, _feed)
    {}

    /**
     * @dev Update the token URI field
     * @dev Only the animator role can call this
     */
    function updateURI(uint256 _id, string calldata _uri)
        external
        onlyRole(ANIMATOR_ROLE)
    {
        _setTokenURI(_id, _uri);
    }

    /**
     * @dev Generate the token SVG art preview for given parameters
     * @param _seed for renderer RNG
     * @param counts for colors and shapes
     * @param dials for perpetual renderer
     * @param mirrors switches
     * @return preview SVG art
     */
    function tokenPreview(
        string memory _seed,
        uint8[2] memory counts,
        int16[13] memory dials,
        bool[3] memory mirrors
    ) public view returns (string memory) {
        TinyBox memory box = TinyBox({
            randomness: _seed.stringToUint(),
            animation: 0,
            shapes: counts[1],
            colors: counts[0],
            spacing: [
                uint16(dials[0]),
                uint16(dials[1]),
                uint16(dials[2]),
                uint16(dials[3])
            ],
            size: [
                uint16(dials[4]),
                uint16(dials[5]),
                uint16(dials[6]),
                uint16(dials[7])
            ],
            hatching: uint16(dials[8]),
            mirrorPositions: [dials[9], dials[10], dials[11]],
            scale: uint16(dials[12]),
            mirrors: mirrors
        });
        return box.perpetualRenderer(0).toString();
    }

    /**
     * @dev Generate the token SVG art of a specified frame
     * @param _id for which we want art
     * @param _frame for which we want art
     * @return animated SVG art of token _id at _frame.
     */
    function tokenFrame(uint256 _id, uint256 _frame)
        public
        view
        returns (string memory)
    {
        TinyBox memory box = boxes[_id];
        return box.perpetualRenderer(_frame).toString();
    }

    /**
     * @dev Generate the static token SVG art
     * @param _id for which we want art
     * @return URI of _id.
     */
    function tokenArt(uint256 _id) external view returns (string memory) {
        // render frame 0 of the token animation
        return tokenFrame(_id, 0);
    }
}
