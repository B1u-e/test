// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGamblingGame {
    function setBetToken(
        address _tokenAddress,
        uint256 _betTokenDecimal
    ) external;

    function setGameBlock(uint256 _block) external;

    function getBalance() external view returns (uint256);

    function createBettor(
        uint256 _betAmount,
        uint8 _betType
    ) external returns (bool);

    function luckyDraw(uint256[2] memory _threeNumbers) external returns (bool);
}
